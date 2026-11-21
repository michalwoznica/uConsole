#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/rootfs.lock"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/release-baseline.lock"

stage10_workdir="${UCONSOLE_BUILD_DIR:-$repo_root/build/stage10-host}"
artifact_dir="${UCONSOLE_ARTIFACT_DIR:-$repo_root/out/stage10}"
bundle_dir="${UCONSOLE_BASELINE_OUTPUT_DIR:-$repo_root/out/baselines/$BASELINE_ID}"
capture_dir="${bundle_dir}.capturing.$$"
rootfs_tree="$stage10_workdir/rootfs"
pacman_cache="$rootfs_tree/var/cache/pacman/pkg"

required_commands=(
    awk bsdtar comm cp curl date find gpg gpgv grep head md5sum mkdir mktemp
    mv readlink sed sha256sum sort stat tr wc xargs
)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing required commands: %s\n' "${missing[*]}" >&2
    exit 1
fi

if [[ "$BASELINE_STATUS" != "accepted" ]]; then
    printf 'ERROR: release baseline is not marked accepted.\n' >&2
    exit 1
fi
if [[ "$BASELINE_REBUILD_MODE" != "locked-rebuild" ]]; then
    printf 'ERROR: baseline rebuild mode is not locked-rebuild.\n' >&2
    exit 1
fi
if [[ ! -d "$rootfs_tree/var/lib/pacman/local" ]]; then
    printf 'ERROR: final Stage 10 rootfs workspace not found: %s\n' "$rootfs_tree" >&2
    printf 'Do not run another clean Stage 10 build before capturing the accepted baseline.\n' >&2
    exit 1
fi
if [[ ! -d "$pacman_cache" ]]; then
    printf 'ERROR: target pacman cache not found: %s\n' "$pacman_cache" >&2
    exit 1
fi

manifest_file="$artifact_dir/uconsole-archlinuxarm-${BASELINE_ROOTFS_RELEASE}-cm4.manifest"
compressed_image="$artifact_dir/uconsole-archlinuxarm-${BASELINE_ROOTFS_RELEASE}-cm4.img.zst"
raw_hash_file="$artifact_dir/uconsole-archlinuxarm-${BASELINE_ROOTFS_RELEASE}-cm4.img.sha256"

for path in "$manifest_file" "$compressed_image" "$raw_hash_file"; do
    if [[ ! -s "$path" ]]; then
        printf 'ERROR: expected accepted Stage 10 artifact missing: %s\n' "$path" >&2
        exit 1
    fi
done

actual_compressed_sha256="$(sha256sum "$compressed_image" | awk '{print $1}')"
if [[ "$actual_compressed_sha256" != "$BASELINE_IMAGE_COMPRESSED_SHA256" ]]; then
    printf 'ERROR: compressed image hash does not match accepted baseline.\n' >&2
    printf 'got:      %s\nexpected: %s\n' \
        "$actual_compressed_sha256" "$BASELINE_IMAGE_COMPRESSED_SHA256" >&2
    exit 1
fi

recorded_raw_sha256="$(awk 'NF {print $1; exit}' "$raw_hash_file")"
if [[ "$recorded_raw_sha256" != "$BASELINE_IMAGE_RAW_SHA256" ]]; then
    printf 'ERROR: raw image checksum record does not match accepted baseline.\n' >&2
    exit 1
fi

mapfile -t kernel_packages < <(
    find "$artifact_dir" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' \
        ! -name '*.sig' \
        | sort
)
if [[ "${#kernel_packages[@]}" -ne 1 ]]; then
    printf 'ERROR: expected exactly one Stage 10 linux-uconsole package, got %s.\n' \
        "${#kernel_packages[@]}" >&2
    exit 1
fi
kernel_package="${kernel_packages[0]}"
kernel_sha256="$(sha256sum "$kernel_package" | awk '{print $1}')"
if [[ "$kernel_sha256" != "$BASELINE_KERNEL_PACKAGE_SHA256" ]]; then
    printf 'ERROR: kernel package hash does not match accepted baseline.\n' >&2
    exit 1
fi

if [[ -e "$bundle_dir" ]]; then
    printf 'ERROR: baseline bundle directory already exists: %s\n' "$bundle_dir" >&2
    printf 'Refusing to overwrite an existing baseline capture.\n' >&2
    exit 1
fi
if [[ -e "$capture_dir" ]]; then
    printf 'ERROR: temporary capture path already exists: %s\n' "$capture_dir" >&2
    exit 1
fi

mkdir -p \
    "$capture_dir/rootfs" \
    "$capture_dir/target-packages" \
    "$capture_dir/kernel" \
    "$capture_dir/inventories" \
    "$capture_dir/build-metadata"

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmpdir"
    if [[ -n "${capture_dir:-}" && -d "$capture_dir" ]]; then
        rm -rf "$capture_dir"
    fi
}
trap cleanup EXIT

inventory_from_local_db() {
    local db_root="$1"
    local output="$2"
    : > "$output"
    while IFS= read -r -d '' desc; do
        awk '
            $0 == "%NAME%" { getline; name=$0 }
            $0 == "%VERSION%" { getline; version=$0 }
            END {
                if (name != "" && version != "")
                    printf "%s\t%s\n", name, version
            }
        ' "$desc" >> "$output"
    done < <(
        find "$db_root/var/lib/pacman/local" \
            -mindepth 2 -maxdepth 2 -type f -name desc -print0
    )
    sort -u -o "$output" "$output"
}

inventory_from_rootfs_archive() {
    local archive="$1"
    local output="$2"
    local members="$tmpdir/rootfs-pacman-desc-members.txt"
    local extracted="$tmpdir/rootfs-pacman-db"

    mkdir -p "$extracted"

    # List once, then extract every pacman local-database desc file in one
    # archive pass. Reopening a compressed rootfs once per package would force
    # thousands of repeated single-threaded decompressions.
    bsdtar -tf "$archive" |
        grep -E '^(\./)?var/lib/pacman/local/[^/]+/desc$' > "$members"
    if [[ ! -s "$members" ]]; then
        printf 'ERROR: no pacman local-database entries found in pinned rootfs archive.\n' >&2
        exit 1
    fi

    bsdtar -xf "$archive" -C "$extracted" -T "$members"
    inventory_from_local_db "$extracted" "$output"
}

download_from_base() {
    local base_url="$1"
    local name="$2"
    local output="$3"
    curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 \
        "${base_url}/${name}" \
        --output "$output"
}

download_versioned_input() {
    local name="$1"
    local output="$2"
    if download_from_base "$ROOTFS_PRIMARY_BASE_URL" "$name" "$output"; then
        return 0
    fi
    printf 'Primary mirror failed for %s; trying fallback mirror.\n' "$name" >&2
    download_from_base "$ROOTFS_FALLBACK_BASE_URL" "$name" "$output"
}

printf 'Capturing accepted baseline: %s\n' "$BASELINE_ID"
printf 'Final Stage 10 workspace: %s\n' "$stage10_workdir"
printf 'Baseline bundle: %s\n' "$bundle_dir"

printf 'Recording final installed package inventory...\n'
final_inventory="$capture_dir/inventories/final-packages.txt"
inventory_from_local_db "$rootfs_tree" "$final_inventory"
if [[ ! -s "$final_inventory" ]]; then
    printf 'ERROR: final package inventory is empty.\n' >&2
    exit 1
fi

grep -Fqx $'linux-uconsole\t6.18.60-1' "$final_inventory"
if grep -Eq $'^(linux-aarch64|uboot-raspberrypi)\t' "$final_inventory"; then
    printf 'ERROR: final inventory still contains stock kernel/U-Boot package.\n' >&2
    exit 1
fi

printf 'Reacquiring pinned rootfs and provenance sidecars...\n'
archive="$capture_dir/rootfs/$ROOTFS_FILENAME"
md5_file="${archive}${ROOTFS_MD5_SUFFIX}"
sig_file="${archive}${ROOTFS_SIGNATURE_SUFFIX}"
download_versioned_input "$ROOTFS_FILENAME" "$archive"
download_versioned_input "${ROOTFS_FILENAME}${ROOTFS_MD5_SUFFIX}" "$md5_file"
download_versioned_input "${ROOTFS_FILENAME}${ROOTFS_SIGNATURE_SUFFIX}" "$sig_file"

actual_size="$(stat -c '%s' "$archive")"
if [[ "$actual_size" != "$ROOTFS_EXPECTED_SIZE" ]]; then
    printf 'ERROR: rootfs size mismatch.\n' >&2
    exit 1
fi
published_md5="$(awk 'NF {print $1; exit}' "$md5_file")"
actual_md5="$(md5sum "$archive" | awk '{print $1}')"
if [[ "${actual_md5,,}" != "${published_md5,,}" ]]; then
    printf 'ERROR: rootfs MD5 mismatch.\n' >&2
    exit 1
fi
actual_rootfs_sha256="$(sha256sum "$archive" | awk '{print $1}')"
if [[ "$actual_rootfs_sha256" != "$ROOTFS_SHA256" || "$actual_rootfs_sha256" != "$BASELINE_ROOTFS_SHA256" ]]; then
    printf 'ERROR: rootfs SHA-256 does not match repository/baseline lock.\n' >&2
    exit 1
fi

printf 'Verifying pinned rootfs detached signature...\n'
keyring_member="$(
    bsdtar -tf "$archive" |
        grep -E '^(\./)?usr/share/pacman/keyrings/archlinuxarm\.gpg$' |
        head -n 1
)"
if [[ -z "$keyring_member" ]]; then
    printf 'ERROR: Arch Linux ARM keyring not found in pinned rootfs archive.\n' >&2
    exit 1
fi
keyring_source="$tmpdir/archlinuxarm-source.gpg"
keyring="$tmpdir/archlinuxarm-binary.gpg"
bsdtar -xOf "$archive" "$keyring_member" > "$keyring_source"
if grep -aqm1 '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$keyring_source"; then
    gpg --batch --yes --dearmor --output "$keyring" "$keyring_source"
else
    cp "$keyring_source" "$keyring"
fi

gpgv_status="$tmpdir/gpgv-status.txt"
if ! gpgv --status-fd=1 --keyring "$keyring" "$sig_file" "$archive" \
    >"$gpgv_status" 2>"$tmpdir/gpgv-log.txt"; then
    printf 'ERROR: rootfs detached signature verification failed.\n' >&2
    cat "$tmpdir/gpgv-log.txt" >&2 || true
    exit 1
fi
if ! awk -v expected="$ROOTFS_SIGNING_FINGERPRINT" '
    $1 == "[GNUPG:]" && $2 == "VALIDSIG" &&
    ($3 == expected || $12 == expected) { found=1 }
    END { exit(found ? 0 : 1) }
' "$gpgv_status"; then
    printf 'ERROR: rootfs signature identity mismatch.\n' >&2
    exit 1
fi

printf 'Recording pinned-rootfs package inventory...\n'
rootfs_inventory="$capture_dir/inventories/rootfs-packages.txt"
inventory_from_rootfs_archive "$archive" "$rootfs_inventory"
if [[ ! -s "$rootfs_inventory" ]]; then
    printf 'ERROR: rootfs package inventory is empty.\n' >&2
    exit 1
fi

printf 'Calculating exact package delta...\n'
package_delta="$capture_dir/inventories/package-delta.txt"
removed_packages="$capture_dir/inventories/removed-packages.txt"
comm -13 "$rootfs_inventory" "$final_inventory" > "$package_delta"
comm -23 "$rootfs_inventory" "$final_inventory" > "$removed_packages"

if ! grep -Eq $'^linux-uconsole\t6\.18\.60-1$' "$package_delta"; then
    printf 'ERROR: expected linux-uconsole addition missing from package delta.\n' >&2
    exit 1
fi
for removed in linux-aarch64 uboot-raspberrypi; do
    if ! awk -F '\t' -v pkg="$removed" '$1 == pkg { found=1 } END { exit(found ? 0 : 1) }' \
        "$removed_packages"; then
        printf 'ERROR: expected removed package missing from delta: %s\n' "$removed" >&2
        exit 1
    fi
done

printf 'Indexing final target pacman cache...\n'
cache_index="$tmpdir/cache-index.tsv"
: > "$cache_index"
while IFS= read -r -d '' pkgfile; do
    pkginfo=""
    if ! pkginfo="$(bsdtar -xOf "$pkgfile" .PKGINFO 2>/dev/null)"; then
        pkginfo="$(bsdtar -xOf "$pkgfile" ./.PKGINFO 2>/dev/null || true)"
    fi
    [[ -n "$pkginfo" ]] || continue
    pkgname="$(awk -F ' = ' '$1 == "pkgname" {print $2; exit}' <<<"$pkginfo")"
    pkgver="$(awk -F ' = ' '$1 == "pkgver" {print $2; exit}' <<<"$pkginfo")"
    pkgarch="$(awk -F ' = ' '$1 == "arch" {print $2; exit}' <<<"$pkginfo")"
    if [[ -n "$pkgname" && -n "$pkgver" ]]; then
        printf '%s\t%s\t%s\t%s\n' "$pkgname" "$pkgver" "$pkgarch" "$pkgfile" >> "$cache_index"
    fi
done < <(
    find "$pacman_cache" -maxdepth 1 -type f \
        -name '*.pkg.tar.*' \
        ! -name '*.sig' \
        ! -name '*.part' \
        -print0
)
sort -u -o "$cache_index" "$cache_index"

printf 'Preserving exact target package payloads required by the delta...\n'
captured_target_count=0
while IFS=$'\t' read -r pkgname pkgver; do
    [[ -n "$pkgname" ]] || continue
    if [[ "$pkgname" == "linux-uconsole" ]]; then
        continue
    fi
    mapfile -t matches < <(
        awk -F '\t' -v name="$pkgname" -v version="$pkgver" \
            '$1 == name && $2 == version { print $4 }' "$cache_index"
    )
    if [[ "${#matches[@]}" -eq 0 ]]; then
        printf 'ERROR: required final package payload not found in pacman cache: %s %s\n' \
            "$pkgname" "$pkgver" >&2
        exit 1
    fi
    source_pkg="${matches[0]}"
    cp -a "$source_pkg" "$capture_dir/target-packages/"
    if [[ -f "${source_pkg}.sig" ]]; then
        cp -a "${source_pkg}.sig" "$capture_dir/target-packages/"
    fi
    captured_target_count=$((captured_target_count + 1))
done < "$package_delta"

printf 'Preserving exact accepted linux-uconsole package...\n'
cp -a "$kernel_package" "$capture_dir/kernel/"
if [[ -f "${kernel_package}.sig" ]]; then
    cp -a "${kernel_package}.sig" "$capture_dir/kernel/"
fi

printf 'Recording build/release metadata...\n'
cp -a "$manifest_file" "$capture_dir/build-metadata/stage10.manifest"
cp -a "$repo_root/image/archlinuxarm/release-baseline.lock" \
    "$capture_dir/build-metadata/release-baseline.lock"
cp -a "$repo_root/image/archlinuxarm/rootfs.lock" \
    "$capture_dir/build-metadata/rootfs.lock"
cp -a "$repo_root/image/archlinuxarm/image-layout.lock" \
    "$capture_dir/build-metadata/image-layout.lock"
cp -a "$repo_root/kernel/source.lock" \
    "$capture_dir/build-metadata/kernel-source.lock"

rootfs_inventory_sha256="$(sha256sum "$rootfs_inventory" | awk '{print $1}')"
final_inventory_sha256="$(sha256sum "$final_inventory" | awk '{print $1}')"
package_delta_sha256="$(sha256sum "$package_delta" | awk '{print $1}')"
removed_packages_sha256="$(sha256sum "$removed_packages" | awk '{print $1}')"
stage10_manifest_sha256="$(sha256sum "$capture_dir/build-metadata/stage10.manifest" | awk '{print $1}')"
rootfs_package_count="$(wc -l < "$rootfs_inventory" | tr -d ' ')"
final_package_count="$(wc -l < "$final_inventory" | tr -d ' ')"
package_delta_count="$(wc -l < "$package_delta" | tr -d ' ')"
removed_package_count="$(wc -l < "$removed_packages" | tr -d ' ')"

cat > "$capture_dir/bundle.lock" <<LOCK
BUNDLE_FORMAT=1
BUNDLE_MODE=locked-rebuild-inputs
BUNDLE_BASELINE_ID=$BASELINE_ID
BUNDLE_CAPTURED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUNDLE_ROOTFS_RELEASE=$ROOTFS_RELEASE
BUNDLE_ROOTFS_SHA256=$actual_rootfs_sha256
BUNDLE_KERNEL_RELEASE=$BASELINE_KERNEL_RELEASE
BUNDLE_KERNEL_PACKAGE_SHA256=$kernel_sha256
BUNDLE_ACCEPTED_IMAGE_COMPRESSED_SHA256=$actual_compressed_sha256
BUNDLE_ROOTFS_INVENTORY_SHA256=$rootfs_inventory_sha256
BUNDLE_FINAL_INVENTORY_SHA256=$final_inventory_sha256
BUNDLE_PACKAGE_DELTA_SHA256=$package_delta_sha256
BUNDLE_REMOVED_PACKAGES_SHA256=$removed_packages_sha256
BUNDLE_STAGE10_MANIFEST_SHA256=$stage10_manifest_sha256
BUNDLE_ROOTFS_PACKAGE_COUNT=$rootfs_package_count
BUNDLE_FINAL_PACKAGE_COUNT=$final_package_count
BUNDLE_PACKAGE_DELTA_COUNT=$package_delta_count
BUNDLE_REMOVED_PACKAGE_COUNT=$removed_package_count
BUNDLE_TARGET_PAYLOAD_COUNT=$captured_target_count
LOCK

printf 'Hashing complete baseline bundle...\n'
(
    cd "$capture_dir"
    find . -type f ! -name bundle-files.sha256 -print0 |
        sort -z |
        xargs -0 sha256sum
) > "$capture_dir/bundle-files.sha256"

printf 'Verifying captured baseline bundle...\n'
bash "$repo_root/scripts/verify-release-baseline-bundle.sh" "$capture_dir"

printf 'Promoting verified capture atomically to final bundle path...\n'
mv "$capture_dir" "$bundle_dir"
capture_dir=""

printf '\n=== STAGE 12C BASELINE CAPTURE ===\n'
printf 'baseline_id=%s\n' "$BASELINE_ID"
printf 'bundle_dir=%s\n' "$bundle_dir"
printf 'bundle_lock_sha256=%s\n' "$(sha256sum "$bundle_dir/bundle.lock" | awk '{print $1}')"
printf 'bundle_files_sha256=%s\n' "$(sha256sum "$bundle_dir/bundle-files.sha256" | awk '{print $1}')"
printf 'rootfs_inventory_sha256=%s\n' "$rootfs_inventory_sha256"
printf 'final_inventory_sha256=%s\n' "$final_inventory_sha256"
printf 'package_delta_count=%s\n' "$package_delta_count"
printf 'removed_package_count=%s\n' "$removed_package_count"
printf 'target_payload_count=%s\n' "$captured_target_count"
printf '=== END STAGE 12C BASELINE CAPTURE ===\n'
printf '\nPASS: accepted Stage 11 baseline inputs captured and verified.\n'

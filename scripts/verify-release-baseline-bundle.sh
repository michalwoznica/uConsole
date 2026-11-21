#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/release-baseline.lock"

bundle_dir="${1:-$repo_root/out/baselines/$BASELINE_ID}"
if [[ ! -d "$bundle_dir" ]]; then
    printf 'ERROR: baseline bundle directory not found: %s\n' "$bundle_dir" >&2
    exit 1
fi
if [[ ! -s "$bundle_dir/bundle.lock" || ! -s "$bundle_dir/bundle-files.sha256" ]]; then
    printf 'ERROR: baseline bundle metadata is incomplete.\n' >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$bundle_dir/bundle.lock"

actual_bundle_lock_sha256="$(sha256sum "$bundle_dir/bundle.lock" | awk '{print $1}')"
actual_bundle_files_sha256="$(sha256sum "$bundle_dir/bundle-files.sha256" | awk '{print $1}')"
if [[ "$actual_bundle_lock_sha256" != "$BASELINE_BUNDLE_LOCK_SHA256" ]]; then
    printf 'ERROR: bundle.lock hash does not match accepted repository baseline metadata.\n' >&2
    exit 1
fi
if [[ "$actual_bundle_files_sha256" != "$BASELINE_BUNDLE_FILES_SHA256" ]]; then
    printf 'ERROR: bundle-files.sha256 hash does not match accepted repository baseline metadata.\n' >&2
    exit 1
fi

if [[ "$BUNDLE_FORMAT" != "1" ]]; then
    printf 'ERROR: unsupported baseline bundle format: %s\n' "$BUNDLE_FORMAT" >&2
    exit 1
fi
if [[ "$BUNDLE_MODE" != "locked-rebuild-inputs" ]]; then
    printf 'ERROR: unexpected bundle mode: %s\n' "$BUNDLE_MODE" >&2
    exit 1
fi
if [[ "$BUNDLE_BASELINE_ID" != "$BASELINE_ID" ]]; then
    printf 'ERROR: bundle baseline ID does not match repository baseline lock.\n' >&2
    exit 1
fi
if [[ "$BUNDLE_ROOTFS_SHA256" != "$BASELINE_ROOTFS_SHA256" ]]; then
    printf 'ERROR: bundle rootfs hash does not match accepted baseline.\n' >&2
    exit 1
fi
if [[ "$BUNDLE_KERNEL_PACKAGE_SHA256" != "$BASELINE_KERNEL_PACKAGE_SHA256" ]]; then
    printf 'ERROR: bundle kernel package hash does not match accepted baseline.\n' >&2
    exit 1
fi
if [[ "$BUNDLE_ACCEPTED_IMAGE_COMPRESSED_SHA256" != "$BASELINE_IMAGE_COMPRESSED_SHA256" ]]; then
    printf 'ERROR: bundle was not captured from the accepted compressed image.\n' >&2
    exit 1
fi

if [[ "$BUNDLE_FORMAT" != "$BASELINE_BUNDLE_FORMAT" ]]; then
    printf 'ERROR: bundle format does not match repository baseline metadata.\n' >&2
    exit 1
fi
if [[ "$BUNDLE_ROOTFS_INVENTORY_SHA256" != "$BASELINE_ROOTFS_INVENTORY_SHA256" ||
      "$BUNDLE_FINAL_INVENTORY_SHA256" != "$BASELINE_FINAL_INVENTORY_SHA256" ]]; then
    printf 'ERROR: bundle package inventory identity does not match accepted baseline.\n' >&2
    exit 1
fi
if [[ "$BUNDLE_PACKAGE_DELTA_COUNT" != "$BASELINE_PACKAGE_DELTA_COUNT" ||
      "$BUNDLE_REMOVED_PACKAGE_COUNT" != "$BASELINE_REMOVED_PACKAGE_COUNT" ||
      "$BUNDLE_TARGET_PAYLOAD_COUNT" != "$BASELINE_TARGET_PAYLOAD_COUNT" ]]; then
    printf 'ERROR: bundle package counts do not match accepted baseline.\n' >&2
    exit 1
fi

printf 'Checking baseline bundle file hashes...\n'
(
    cd "$bundle_dir"
    sha256sum -c bundle-files.sha256 >/dev/null
)

check_hash() {
    local path="$1"
    local expected="$2"
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        printf 'ERROR: hash mismatch for %s\n' "$path" >&2
        exit 1
    fi
}

check_hash "$bundle_dir/inventories/rootfs-packages.txt" "$BUNDLE_ROOTFS_INVENTORY_SHA256"
check_hash "$bundle_dir/inventories/final-packages.txt" "$BUNDLE_FINAL_INVENTORY_SHA256"
check_hash "$bundle_dir/inventories/package-delta.txt" "$BUNDLE_PACKAGE_DELTA_SHA256"
check_hash "$bundle_dir/inventories/removed-packages.txt" "$BUNDLE_REMOVED_PACKAGES_SHA256"
check_hash "$bundle_dir/build-metadata/stage10.manifest" "$BUNDLE_STAGE10_MANIFEST_SHA256"

mapfile -t kernel_packages < <(
    find "$bundle_dir/kernel" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' \
        ! -name '*.sig' | sort
)
if [[ "${#kernel_packages[@]}" -ne 1 ]]; then
    printf 'ERROR: bundle must contain exactly one linux-uconsole package.\n' >&2
    exit 1
fi
check_hash "${kernel_packages[0]}" "$BASELINE_KERNEL_PACKAGE_SHA256"

grep -Fqx $'linux-uconsole\t6.18.60-1' \
    "$bundle_dir/inventories/final-packages.txt"
if grep -Eq $'^(linux-aarch64|uboot-raspberrypi)\t' \
    "$bundle_dir/inventories/final-packages.txt"; then
    printf 'ERROR: final bundle inventory contains stock kernel/U-Boot.\n' >&2
    exit 1
fi

for removed in linux-aarch64 uboot-raspberrypi; do
    if ! awk -F '\t' -v pkg="$removed" '$1 == pkg { found=1 } END { exit(found ? 0 : 1) }' \
        "$bundle_dir/inventories/removed-packages.txt"; then
        printf 'ERROR: expected removed package missing from bundle inventory: %s\n' "$removed" >&2
        exit 1
    fi
done

printf 'Checking target payload coverage for every final package delta...\n'
payload_index="$(mktemp)"
trap 'rm -f "$payload_index"' EXIT
: > "$payload_index"
while IFS= read -r -d '' pkgfile; do
    pkginfo=""
    if ! pkginfo="$(bsdtar -xOf "$pkgfile" .PKGINFO 2>/dev/null)"; then
        pkginfo="$(bsdtar -xOf "$pkgfile" ./.PKGINFO 2>/dev/null || true)"
    fi
    [[ -n "$pkginfo" ]] || continue
    pkgname="$(awk -F ' = ' '$1 == "pkgname" {print $2; exit}' <<<"$pkginfo")"
    pkgver="$(awk -F ' = ' '$1 == "pkgver" {print $2; exit}' <<<"$pkginfo")"
    [[ -n "$pkgname" && -n "$pkgver" ]] || continue
    printf '%s\t%s\n' "$pkgname" "$pkgver" >> "$payload_index"
done < <(
    find "$bundle_dir/target-packages" -maxdepth 1 -type f \
        -name '*.pkg.tar.*' ! -name '*.sig' -print0
)
sort -u -o "$payload_index" "$payload_index"

payload_count="$(wc -l < "$payload_index" | tr -d ' ')"
if [[ "$payload_count" != "$BUNDLE_TARGET_PAYLOAD_COUNT" ]]; then
    printf 'ERROR: target payload count mismatch: got %s expected %s\n' \
        "$payload_count" "$BUNDLE_TARGET_PAYLOAD_COUNT" >&2
    exit 1
fi

while IFS=$'\t' read -r pkgname pkgver; do
    [[ -n "$pkgname" ]] || continue
    [[ "$pkgname" == "linux-uconsole" ]] && continue
    if ! grep -Fqx "${pkgname}"$'\t'"${pkgver}" "$payload_index"; then
        printf 'ERROR: target payload missing for required delta package: %s %s\n' \
            "$pkgname" "$pkgver" >&2
        exit 1
    fi
done < "$bundle_dir/inventories/package-delta.txt"

printf 'PASS: baseline bundle hashes, inventories and package payload coverage verified.\n'

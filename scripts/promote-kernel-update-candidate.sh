#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidate_version="${1:-}"
candidate_commit="${2:-}"
new_baseline_id="${3:-archlinuxarm-stage12h-2026-11-22}"

if [[ -z "$candidate_version" || -z "$candidate_commit" ]]; then
    printf 'usage: %s VERSION COMMIT [NEW_BASELINE_ID]\n' "$0" >&2
    exit 2
fi
if [[ ! "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'ERROR: candidate version must be numeric X.Y.Z: %s\n' "$candidate_version" >&2
    exit 1
fi
if [[ ! "$candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'ERROR: candidate commit must be a full lowercase 40-character SHA-1.\n' >&2
    exit 1
fi
if [[ ! "$new_baseline_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'ERROR: invalid new baseline ID: %s\n' "$new_baseline_id" >&2
    exit 1
fi

baseline_lock="$repo_root/image/archlinuxarm/release-baseline.lock"
rootfs_lock="$repo_root/image/archlinuxarm/rootfs.lock"
kernel_lock="$repo_root/kernel/source.lock"
pkgbuild="$repo_root/image/archlinuxarm/packages/linux-uconsole/PKGBUILD"
physical_lock="$repo_root/image/archlinuxarm/stage12g-physical-validation.lock"

for required in \
    "$baseline_lock" "$rootfs_lock" "$kernel_lock" "$pkgbuild" "$physical_lock" \
    "$repo_root/scripts/verify-release-baseline-bundle.sh" \
    "$repo_root/scripts/build-release-baseline.sh"
do
    if [[ ! -s "$required" ]]; then
        printf 'ERROR: required Stage 12H input missing: %s\n' "$required" >&2
        exit 1
    fi
done

required_commands=(awk bsdtar cmp comm cp date diff find git grep mkdir mktemp mv rm sed sha256sum sort wc)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing required commands: %s\n' "${missing[*]}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$baseline_lock"
# shellcheck disable=SC1090
source "$rootfs_lock"
# shellcheck disable=SC1090
source "$kernel_lock"
# shellcheck disable=SC1090
source "$physical_lock"

old_baseline_id="$BASELINE_ID"
old_kernel_release="$BASELINE_KERNEL_RELEASE"
old_kernel_pkgver="${old_kernel_release%-uconsole}"
old_kernel_version="$RPI_LINUX_VERSION"
old_kernel_commit="$RPI_LINUX_COMMIT"
candidate_release="${candidate_version}-1-uconsole"
candidate_pkgver="${candidate_version}-1"
candidate_id="kernel-${candidate_version}-${candidate_commit:0:12}"
candidate_artifact_dir="$repo_root/out/update-candidate/$candidate_id"
old_bundle_dir="${UCONSOLE_BASELINE_BUNDLE_DIR:-$repo_root/out/baselines/$old_baseline_id}"
new_bundle_dir="$repo_root/out/baselines/$new_baseline_id"
new_bundle_tmp="${new_bundle_dir}.promoting.$$"
locked_build_dir="$repo_root/build/locked-rebuild/$new_baseline_id"
locked_artifact_dir="$repo_root/out/locked-rebuild/$new_baseline_id"

image_stem="uconsole-archlinuxarm-${BASELINE_ROOTFS_RELEASE}-cm4-candidate-kernel-${candidate_version}-${candidate_commit:0:12}"
candidate_manifest="$candidate_artifact_dir/${image_stem}.manifest"
candidate_compressed="$candidate_artifact_dir/${image_stem}.img.zst"
candidate_raw_hash="$candidate_artifact_dir/${image_stem}.img.sha256"
candidate_report="$candidate_artifact_dir/stage12f-candidate-report.txt"
candidate_inventory="$candidate_artifact_dir/final-packages.txt"

mapfile -t candidate_packages < <(
    find "$candidate_artifact_dir" -maxdepth 1 -type f \
        -name "linux-uconsole-${candidate_pkgver}-aarch64.pkg.tar*" \
        ! -name '*.sig' | sort
)
if [[ "${#candidate_packages[@]}" -ne 1 ]]; then
    printf 'ERROR: expected exactly one validated candidate package in %s, got %s.\n' \
        "$candidate_artifact_dir" "${#candidate_packages[@]}" >&2
    exit 1
fi
candidate_package="${candidate_packages[0]}"

for required in \
    "$candidate_manifest" "$candidate_compressed" "$candidate_raw_hash" \
    "$candidate_report" "$candidate_inventory" "$candidate_package"
do
    if [[ ! -s "$required" ]]; then
        printf 'ERROR: validated Stage 12F artifact missing: %s\n' "$required" >&2
        exit 1
    fi
done

if [[ "$BASELINE_STATUS" != accepted || "$BASELINE_REBUILD_MODE" != locked-rebuild ]]; then
    printf 'ERROR: current repository baseline is not an accepted locked-rebuild baseline.\n' >&2
    exit 1
fi
if [[ "$candidate_version" == "$old_kernel_version" && "$candidate_commit" == "$old_kernel_commit" ]]; then
    printf 'ERROR: candidate is already the accepted kernel.\n' >&2
    exit 1
fi

if [[ "$STAGE12G_STATUS" != pass || "$STAGE12G_CANDIDATE_CLASS" != kernel-update ||
      "$STAGE12G_KERNEL_VERSION" != "$candidate_version" ||
      "$STAGE12G_KERNEL_COMMIT" != "$candidate_commit" ||
      "$STAGE12G_KERNEL_RELEASE" != "$candidate_release" ]]; then
    printf 'ERROR: Stage 12G physical-validation lock does not authorize this candidate.\n' >&2
    exit 1
fi

for proof in \
    STAGE12G_BOOT STAGE12G_BRIGHTNESS_KEYS STAGE12G_WIFI_IPV4_DNS \
    STAGE12G_BLUETOOTH_SCAN STAGE12G_USB_STORAGE STAGE12G_BATTERY_REPORTING \
    STAGE12G_SPEAKER_AUDIO STAGE12G_HEADPHONE_AUDIO STAGE12G_LIVE_AUDIO_SWITCHING \
    STAGE12G_POWER_KEY_IGNORE STAGE12G_REBOOT STAGE12G_POWEROFF
do
    if [[ "${!proof}" != pass ]]; then
        printf 'ERROR: physical-validation proof is not PASS: %s=%s\n' "$proof" "${!proof}" >&2
        exit 1
    fi
done
if [[ "$STAGE12G_SYSTEMD_FAILED_UNITS" != 0 ]]; then
    printf 'ERROR: Stage 12G recorded failed systemd units.\n' >&2
    exit 1
fi

candidate_package_sha256="$(sha256sum "$candidate_package" | awk '{print $1}')"
candidate_compressed_sha256="$(sha256sum "$candidate_compressed" | awk '{print $1}')"
candidate_raw_sha256="$(awk 'NF {print $1; exit}' "$candidate_raw_hash")"
candidate_inventory_sha256="$(sha256sum "$candidate_inventory" | awk '{print $1}')"

if [[ "$candidate_package_sha256" != "$STAGE12G_KERNEL_PACKAGE_SHA256" ||
      "$candidate_compressed_sha256" != "$STAGE12G_IMAGE_COMPRESSED_SHA256" ||
      "$candidate_raw_sha256" != "$STAGE12G_IMAGE_RAW_SHA256" ||
      "$candidate_inventory_sha256" != "$STAGE12G_FINAL_INVENTORY_SHA256" ]]; then
    printf 'ERROR: Stage 12F artifacts no longer match the physically validated Stage 12G identity.\n' >&2
    exit 1
fi

for expected in \
    "stage=12F" \
    "candidate_kernel_version=$candidate_version" \
    "candidate_kernel_commit=$candidate_commit" \
    "candidate_kernel_release=$candidate_release" \
    "candidate_package_sha256=$candidate_package_sha256" \
    "final_inventory_sha256=$candidate_inventory_sha256" \
    "compressed_image_sha256=$candidate_compressed_sha256" \
    "project_pins_changed=no" \
    "repository_mutated=no" \
    "promotion=not_performed"
do
    if ! grep -Fxq "$expected" "$candidate_report"; then
        printf 'ERROR: Stage 12F candidate report is missing required proof: %s\n' "$expected" >&2
        exit 1
    fi
done

for expected in \
    "checkpoint=Stage12F" \
    "rpi_linux_commit=$candidate_commit" \
    "kernel_release=$candidate_release" \
    "package_sha256=$candidate_package_sha256" \
    "image_raw_sha256=$candidate_raw_sha256" \
    "compressed_sha256=$candidate_compressed_sha256"
do
    if ! grep -Fxq "$expected" "$candidate_manifest"; then
        printf 'ERROR: Stage 12F image manifest is missing required identity: %s\n' "$expected" >&2
        exit 1
    fi
done

pkginfo="$(bsdtar -xOf "$candidate_package" .PKGINFO 2>/dev/null || bsdtar -xOf "$candidate_package" ./.PKGINFO)"
grep -Fxq 'pkgname = linux-uconsole' <<<"$pkginfo"
grep -Fxq "pkgver = $candidate_pkgver" <<<"$pkginfo"
grep -Fxq 'arch = aarch64' <<<"$pkginfo"

printf 'Verifying current accepted baseline bundle before promotion...\n'
bash "$repo_root/scripts/verify-release-baseline-bundle.sh" "$old_bundle_dir"

if [[ -e "$new_bundle_dir" || -e "$new_bundle_tmp" ]]; then
    printf 'ERROR: new baseline bundle path already exists; refusing overwrite: %s\n' "$new_bundle_dir" >&2
    exit 1
fi

if [[ -n "$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)" ]]; then
    printf 'ERROR: Stage 12H promotion requires a clean Git worktree.\n' >&2
    git -C "$repo_root" status --short >&2
    exit 1
fi

backup_dir="$(mktemp -d)"
promotion_committed=0
cleanup() {
    status=$?
    if [[ "$promotion_committed" -ne 1 ]]; then
        if [[ -f "$backup_dir/release-baseline.lock" ]]; then
            cp -f "$backup_dir/release-baseline.lock" "$baseline_lock" 2>/dev/null || true
        fi
        if [[ -f "$backup_dir/kernel-source.lock" ]]; then
            cp -f "$backup_dir/kernel-source.lock" "$kernel_lock" 2>/dev/null || true
        fi
        if [[ -f "$backup_dir/PKGBUILD" ]]; then
            cp -f "$backup_dir/PKGBUILD" "$pkgbuild" 2>/dev/null || true
        fi
        rm -rf "$new_bundle_tmp" "$new_bundle_dir" 2>/dev/null || true
    fi
    rm -rf "$backup_dir"
    exit "$status"
}
trap cleanup EXIT

cp -a "$baseline_lock" "$backup_dir/release-baseline.lock"
cp -a "$kernel_lock" "$backup_dir/kernel-source.lock"
cp -a "$pkgbuild" "$backup_dir/PKGBUILD"

printf 'Constructing promoted baseline bundle from accepted userspace + validated kernel...\n'
mkdir -p "$new_bundle_tmp"
cp -a "$old_bundle_dir/." "$new_bundle_tmp/"

rm -f "$new_bundle_tmp/kernel"/linux-uconsole-*-aarch64.pkg.tar* \
      "$new_bundle_tmp/kernel"/*.sig 2>/dev/null || true
cp -a "$candidate_package" "$new_bundle_tmp/kernel/"
if [[ -f "${candidate_package}.sig" ]]; then
    cp -a "${candidate_package}.sig" "$new_bundle_tmp/kernel/"
fi

cp -f "$candidate_inventory" "$new_bundle_tmp/inventories/final-packages.txt"
comm -13 \
    "$new_bundle_tmp/inventories/rootfs-packages.txt" \
    "$new_bundle_tmp/inventories/final-packages.txt" \
    > "$new_bundle_tmp/inventories/package-delta.txt"
comm -23 \
    "$new_bundle_tmp/inventories/rootfs-packages.txt" \
    "$new_bundle_tmp/inventories/final-packages.txt" \
    > "$new_bundle_tmp/inventories/removed-packages.txt"

grep -Fqx $'linux-uconsole\t'"$candidate_pkgver" \
    "$new_bundle_tmp/inventories/final-packages.txt"
grep -Fqx $'linux-uconsole\t'"$candidate_pkgver" \
    "$new_bundle_tmp/inventories/package-delta.txt"

old_no_kernel="$backup_dir/old-no-kernel.txt"
new_no_kernel="$backup_dir/new-no-kernel.txt"
awk -F '\t' '$1 != "linux-uconsole"' \
    "$old_bundle_dir/inventories/final-packages.txt" > "$old_no_kernel"
awk -F '\t' '$1 != "linux-uconsole"' \
    "$new_bundle_tmp/inventories/final-packages.txt" > "$new_no_kernel"
if ! cmp -s "$old_no_kernel" "$new_no_kernel"; then
    printf 'ERROR: promotion candidate changes package inventory outside linux-uconsole.\n' >&2
    diff -u "$old_no_kernel" "$new_no_kernel" >&2 || true
    exit 1
fi

cp -f "$candidate_manifest" "$new_bundle_tmp/build-metadata/stage10.manifest"
if [[ -f "$new_bundle_tmp/build-metadata/release-baseline.lock" ]]; then
    mv "$new_bundle_tmp/build-metadata/release-baseline.lock" \
       "$new_bundle_tmp/build-metadata/previous-release-baseline.lock"
fi
cp -f "$candidate_report" "$new_bundle_tmp/build-metadata/stage12f-candidate-report.txt"
cp -f "$physical_lock" "$new_bundle_tmp/build-metadata/stage12g-physical-validation.lock"

cat > "$new_bundle_tmp/build-metadata/kernel-source.lock" <<LOCK
RPI_LINUX_REPOSITORY=$RPI_LINUX_REPOSITORY
RPI_LINUX_BRANCH_FAMILY=$RPI_LINUX_BRANCH_FAMILY
RPI_LINUX_COMMIT=$candidate_commit
RPI_LINUX_VERSION=$candidate_version
LOCK

rootfs_inventory_sha256="$(sha256sum "$new_bundle_tmp/inventories/rootfs-packages.txt" | awk '{print $1}')"
final_inventory_sha256="$(sha256sum "$new_bundle_tmp/inventories/final-packages.txt" | awk '{print $1}')"
package_delta_sha256="$(sha256sum "$new_bundle_tmp/inventories/package-delta.txt" | awk '{print $1}')"
removed_packages_sha256="$(sha256sum "$new_bundle_tmp/inventories/removed-packages.txt" | awk '{print $1}')"
stage10_manifest_sha256="$(sha256sum "$new_bundle_tmp/build-metadata/stage10.manifest" | awk '{print $1}')"
rootfs_package_count="$(wc -l < "$new_bundle_tmp/inventories/rootfs-packages.txt" | tr -d ' ')"
final_package_count="$(wc -l < "$new_bundle_tmp/inventories/final-packages.txt" | tr -d ' ')"
package_delta_count="$(wc -l < "$new_bundle_tmp/inventories/package-delta.txt" | tr -d ' ')"
removed_package_count="$(wc -l < "$new_bundle_tmp/inventories/removed-packages.txt" | tr -d ' ')"
target_payload_count="$(find "$new_bundle_tmp/target-packages" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.sig' | wc -l | tr -d ' ')"

cat > "$new_bundle_tmp/build-metadata/stage12h-promotion.lock" <<LOCK
STAGE12H_STATUS=promotion-inputs-verified
STAGE12H_PROMOTED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STAGE12H_PREVIOUS_BASELINE_ID=$old_baseline_id
STAGE12H_NEW_BASELINE_ID=$new_baseline_id
STAGE12H_KERNEL_VERSION=$candidate_version
STAGE12H_KERNEL_COMMIT=$candidate_commit
STAGE12H_KERNEL_RELEASE=$candidate_release
STAGE12H_KERNEL_PACKAGE_SHA256=$candidate_package_sha256
STAGE12H_IMAGE_RAW_SHA256=$candidate_raw_sha256
STAGE12H_IMAGE_COMPRESSED_SHA256=$candidate_compressed_sha256
STAGE12H_FINAL_INVENTORY_SHA256=$final_inventory_sha256
STAGE12H_PHYSICAL_VALIDATION=pass
LOCK

cat > "$new_bundle_tmp/bundle.lock" <<LOCK
BUNDLE_FORMAT=1
BUNDLE_MODE=locked-rebuild-inputs
BUNDLE_BASELINE_ID=$new_baseline_id
BUNDLE_CAPTURED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUNDLE_ROOTFS_RELEASE=$ROOTFS_RELEASE
BUNDLE_ROOTFS_SHA256=$ROOTFS_SHA256
BUNDLE_KERNEL_RELEASE=$candidate_release
BUNDLE_KERNEL_PACKAGE_SHA256=$candidate_package_sha256
BUNDLE_ACCEPTED_IMAGE_RAW_SHA256=$candidate_raw_sha256
BUNDLE_ACCEPTED_IMAGE_COMPRESSED_SHA256=$candidate_compressed_sha256
BUNDLE_ROOTFS_INVENTORY_SHA256=$rootfs_inventory_sha256
BUNDLE_FINAL_INVENTORY_SHA256=$final_inventory_sha256
BUNDLE_PACKAGE_DELTA_SHA256=$package_delta_sha256
BUNDLE_REMOVED_PACKAGES_SHA256=$removed_packages_sha256
BUNDLE_STAGE10_MANIFEST_SHA256=$stage10_manifest_sha256
BUNDLE_ROOTFS_PACKAGE_COUNT=$rootfs_package_count
BUNDLE_FINAL_PACKAGE_COUNT=$final_package_count
BUNDLE_PACKAGE_DELTA_COUNT=$package_delta_count
BUNDLE_REMOVED_PACKAGE_COUNT=$removed_package_count
BUNDLE_TARGET_PAYLOAD_COUNT=$target_payload_count
BUNDLE_PROMOTION_SOURCE_BASELINE_ID=$old_baseline_id
BUNDLE_PHYSICAL_VALIDATION=pass
LOCK

(
    cd "$new_bundle_tmp"
    find . -type f ! -name bundle-files.sha256 -print0 | sort -z | xargs -0 sha256sum
) > "$new_bundle_tmp/bundle-files.sha256"

bundle_lock_sha256="$(sha256sum "$new_bundle_tmp/bundle.lock" | awk '{print $1}')"
bundle_files_sha256="$(sha256sum "$new_bundle_tmp/bundle-files.sha256" | awk '{print $1}')"

printf 'Preparing promoted repository source/package/baseline locks...\n'
cat > "$kernel_lock" <<LOCK
RPI_LINUX_REPOSITORY=$RPI_LINUX_REPOSITORY
RPI_LINUX_BRANCH_FAMILY=$RPI_LINUX_BRANCH_FAMILY
RPI_LINUX_COMMIT=$candidate_commit
RPI_LINUX_VERSION=$candidate_version
LOCK

sed -i \
    -e "s/^pkgver=.*/pkgver=${candidate_version}/" \
    -e "s/^_commit=.*/_commit=${candidate_commit}/" \
    "$pkgbuild"
grep -Fxq "pkgver=${candidate_version}" "$pkgbuild"
grep -Fxq "_commit=${candidate_commit}" "$pkgbuild"

cat > "$baseline_lock" <<LOCK
BASELINE_ID=$new_baseline_id
BASELINE_STATUS=accepted
BASELINE_ACCEPTED_UTC=$STAGE12G_VALIDATED_UTC
BASELINE_ROOTFS_RELEASE=$BASELINE_ROOTFS_RELEASE
BASELINE_ROOTFS_SHA256=$BASELINE_ROOTFS_SHA256
BASELINE_RPI_LINUX_COMMIT=$candidate_commit
BASELINE_KERNEL_RELEASE=$candidate_release
BASELINE_KERNEL_PACKAGE_SHA256=$candidate_package_sha256
BASELINE_IMAGE_RAW_SHA256=$candidate_raw_sha256
BASELINE_IMAGE_COMPRESSED_SHA256=$candidate_compressed_sha256
BASELINE_REBUILD_MODE=locked-rebuild
BASELINE_BYTE_IDENTICAL_IMAGE_REQUIRED=no
BASELINE_LIVE_PACKAGE_REFRESH_ALLOWED=no
BASELINE_LIVE_KERNEL_REFRESH_ALLOWED=no
BASELINE_BUNDLE_FORMAT=1
BASELINE_BUNDLE_LOCK_SHA256=$bundle_lock_sha256
BASELINE_BUNDLE_FILES_SHA256=$bundle_files_sha256
BASELINE_ROOTFS_INVENTORY_SHA256=$rootfs_inventory_sha256
BASELINE_FINAL_INVENTORY_SHA256=$final_inventory_sha256
BASELINE_PACKAGE_DELTA_COUNT=$package_delta_count
BASELINE_REMOVED_PACKAGE_COUNT=$removed_package_count
BASELINE_TARGET_PAYLOAD_COUNT=$target_payload_count
LOCK

mv "$new_bundle_tmp" "$new_bundle_dir"
new_bundle_tmp=""

printf 'Verifying promoted baseline bundle against promoted repository lock...\n'
bash "$repo_root/scripts/verify-release-baseline-bundle.sh" "$new_bundle_dir"

printf 'Auditing executable/configuration files for stale accepted-kernel identity...\n'
stale_refs="$backup_dir/stale-references.txt"
: > "$stale_refs"
while IFS= read -r tracked; do
    case "$tracked" in
        # kernel/sources/*.lock records immutable source/provenance identities.
        # Those references may intentionally predate the current accepted kernel
        # and must not be rewritten during baseline promotion.
        docs/*|README.md|kernel/BASELINE.md|kernel/sources/*.lock|*.md) continue ;;
    esac
    case "$tracked" in
        *.sh|*.yml|*.yaml|*.lock|*PKGBUILD|*.conf|*.txt)
            if grep -Fq -- "$old_kernel_version" "$repo_root/$tracked" ||
               grep -Fq -- "$old_kernel_commit" "$repo_root/$tracked"; then
                printf '%s\n' "$tracked" >> "$stale_refs"
            fi
            ;;
    esac
done < <(git -C "$repo_root" ls-files)
# Old identity is expected only in the immutable physical-validation evidence's
# historical context if such a field is added later; current lock contains only
# the promoted candidate identity, so any result here is actionable.
if [[ -s "$stale_refs" ]]; then
    printf 'ERROR: stale accepted-kernel identity remains in executable/configuration files:\n' >&2
    cat "$stale_refs" >&2
    exit 1
fi

printf 'Running network-disabled locked rebuild of the promoted baseline...\n'
UCONSOLE_BASELINE_BUNDLE_DIR="$new_bundle_dir" \
UCONSOLE_LOCKED_BUILD_DIR="$locked_build_dir" \
UCONSOLE_LOCKED_ARTIFACT_DIR="$locked_artifact_dir" \
    bash "$repo_root/scripts/build-release-baseline.sh"

locked_inventory="$locked_build_dir/final-packages.txt"
if [[ ! -s "$locked_inventory" ]]; then
    printf 'ERROR: promoted locked rebuild did not emit final inventory.\n' >&2
    exit 1
fi
locked_inventory_sha256="$(sha256sum "$locked_inventory" | awk '{print $1}')"
if [[ "$locked_inventory_sha256" != "$final_inventory_sha256" ]]; then
    printf 'ERROR: promoted locked rebuild inventory hash differs from accepted inventory.\n' >&2
    exit 1
fi

expected_changes=(
    "image/archlinuxarm/release-baseline.lock"
    "image/archlinuxarm/packages/linux-uconsole/PKGBUILD"
    "kernel/source.lock"
)
mapfile -t actual_changes < <(
    git -C "$repo_root" status --porcelain=v1 --untracked-files=all |
        sed -E 's/^.. //' | sort
)
printf '%s\n' "${expected_changes[@]}" | sort > "$backup_dir/expected-changes.txt"
printf '%s\n' "${actual_changes[@]}" > "$backup_dir/actual-changes.txt"
if ! cmp -s "$backup_dir/expected-changes.txt" "$backup_dir/actual-changes.txt"; then
    printf 'ERROR: Stage 12H changed unexpected repository paths.\n' >&2
    printf '%s\n' '--- expected ---' >&2
    cat "$backup_dir/expected-changes.txt" >&2
    printf '%s\n' '--- actual ---' >&2
    cat "$backup_dir/actual-changes.txt" >&2
    exit 1
fi

promotion_committed=1

printf '\n=== STAGE 12H KERNEL BASELINE PROMOTION ===\n'
printf 'previous_baseline_id=%s\n' "$old_baseline_id"
printf 'accepted_baseline_id=%s\n' "$new_baseline_id"
printf 'accepted_rootfs_release=%s\n' "$BASELINE_ROOTFS_RELEASE"
printf 'accepted_kernel_version=%s\n' "$candidate_version"
printf 'accepted_kernel_commit=%s\n' "$candidate_commit"
printf 'accepted_kernel_release=%s\n' "$candidate_release"
printf 'accepted_kernel_package_sha256=%s\n' "$candidate_package_sha256"
printf 'accepted_image_raw_sha256=%s\n' "$candidate_raw_sha256"
printf 'accepted_image_compressed_sha256=%s\n' "$candidate_compressed_sha256"
printf 'accepted_final_inventory_sha256=%s\n' "$final_inventory_sha256"
printf 'baseline_bundle_lock_sha256=%s\n' "$bundle_lock_sha256"
printf 'baseline_bundle_files_sha256=%s\n' "$bundle_files_sha256"
printf 'physical_validation=pass\n'
printf 'locked_rebuild=pass\n'
printf 'locked_rebuild_inventory_sha256=%s\n' "$locked_inventory_sha256"
printf 'new_image_physical_retest_required=no\n'
printf 'promotion_complete=yes\n'
printf '=== END STAGE 12H KERNEL BASELINE PROMOTION ===\n\n'
printf 'PASS: exact physically validated candidate promoted and reproduced offline; update cycle complete.\n'
printf 'Tracked promotion changes are intentionally left uncommitted for review.\n'

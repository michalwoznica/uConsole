#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/release-baseline.lock"

container_runtime="${CONTAINER_RUNTIME:-podman}"
builder_image="${UCONSOLE_LOCKED_BUILDER_IMAGE:-docker.io/library/archlinux:base-devel}"
bundle_dir="${UCONSOLE_BASELINE_BUNDLE_DIR:-$repo_root/out/baselines/$BASELINE_ID}"
workdir="${UCONSOLE_LOCKED_BUILD_DIR:-$repo_root/build/locked-rebuild/$BASELINE_ID}"
artifact_dir="${UCONSOLE_LOCKED_ARTIFACT_DIR:-$repo_root/out/locked-rebuild/$BASELINE_ID}"

case "$container_runtime" in
    podman)
        container_cmd=(sudo -n podman)
        image_exists_cmd=(sudo -n podman image exists "$builder_image")
        image_id_cmd=(sudo -n podman image inspect --format '{{.Id}}' "$builder_image")
        container_run_args=(--network none)
        ;;
    docker)
        container_cmd=(docker)
        image_exists_cmd=(docker image inspect "$builder_image")
        image_id_cmd=(docker image inspect --format '{{.Id}}' "$builder_image")
        container_run_args=(--network none)
        ;;
    *)
        printf 'ERROR: CONTAINER_RUNTIME must be podman or docker, got: %s\n' \
            "$container_runtime" >&2
        exit 1
        ;;
esac

required_commands=(
    sudo sha256sum find sort awk cmp diff losetup blockdev sfdisk udevadm
    mkfs.vfat fsck.vfat mkfs.ext4 e2fsck mount umount mountpoint blkid rsync zstd
)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
command -v "$container_runtime" >/dev/null 2>&1 || missing+=("$container_runtime")
if [[ "$BASELINE_STATUS" != "accepted" || "$BASELINE_REBUILD_MODE" != "locked-rebuild" ||
      "$BASELINE_LIVE_PACKAGE_REFRESH_ALLOWED" != "no" ||
      "$BASELINE_LIVE_KERNEL_REFRESH_ALLOWED" != "no" ]]; then
    printf 'ERROR: repository baseline lock does not permit a locked rebuild.\n' >&2
    exit 1
fi
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing host commands: %s\n' "${missing[*]}" >&2
    exit 1
fi

printf 'Authenticating sudo for locked baseline rebuild...\n'
sudo -v

sudo_keepalive_pid=""
cleanup_sudo_keepalive() {
    if [[ -n "$sudo_keepalive_pid" ]]; then
        kill "$sudo_keepalive_pid" 2>/dev/null || true
        wait "$sudo_keepalive_pid" 2>/dev/null || true
    fi
}
trap cleanup_sudo_keepalive EXIT
(
    while sleep 60; do
        sudo -n -v || exit 1
    done
) &
sudo_keepalive_pid=$!

printf 'Verifying accepted baseline bundle against repository lock...\n'
bash "$repo_root/scripts/verify-release-baseline-bundle.sh" "$bundle_dir"

if ! "${image_exists_cmd[@]}" >/dev/null 2>&1; then
    printf 'ERROR: locked rebuild requires the builder image to exist locally: %s\n' \
        "$builder_image" >&2
    printf 'Refusing to pull a moving container tag during locked-rebuild mode.\n' >&2
    exit 1
fi
builder_image_id="$("${image_id_cmd[@]}")"

printf 'Locked rebuild mode: %s\n' "$BASELINE_REBUILD_MODE"
printf 'Accepted baseline: %s\n' "$BASELINE_ID"
printf 'Baseline bundle: %s\n' "$bundle_dir"
printf 'Local builder image: %s\n' "$builder_image"
printf 'Local builder image ID: %s\n' "$builder_image_id"
printf 'Workspace: %s\n' "$workdir"
printf 'Artifacts: %s\n' "$artifact_dir"
printf 'Container networking: disabled\n'

sudo -n rm -rf "$workdir" "$artifact_dir"
mkdir -p "$workdir" "$artifact_dir"
chmod 0755 "$workdir" "$artifact_dir"

set +e
"${container_cmd[@]}" run --rm \
    "${container_run_args[@]}" \
    -e UCONSOLE_LOCKED_BASELINE_BUNDLE=/baseline \
    -v "$repo_root:/repo:ro" \
    -v "$bundle_dir:/baseline:ro" \
    -v "$workdir:/work" \
    "$builder_image" \
    bash -lc '
        set -euo pipefail
        required=(bsdtar depmod modinfo pacman sha256sum systemctl)
        missing=()
        for cmd in "${required[@]}"; do
            command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
        done
        if (( ${#missing[@]} != 0 )); then
            printf "ERROR: local locked-rebuild container lacks required tools: %s\\n" "${missing[*]}" >&2
            exit 1
        fi
        bash /repo/scripts/build-archlinuxarm-rootfs.sh \
            /work/rootfs \
            /work/packages
    '
container_status=$?
set -e
if [[ "$container_status" -ne 0 ]]; then
    printf 'ERROR: locked baseline rootfs reconstruction failed. Workspace retained at %s\n' \
        "$workdir" >&2
    exit "$container_status"
fi

printf 'Building partitioned image from locked baseline rootfs...\n'
sudo -n bash "$repo_root/scripts/build-archlinuxarm-image.sh" \
    "$workdir/rootfs" \
    "$workdir/packages" \
    "$artifact_dir"

sudo -n chown -R "$(id -u):$(id -g)" "$artifact_dir"

final_inventory="$workdir/final-packages.txt"
: > "$final_inventory"
while IFS= read -r -d '' desc; do
    awk '
        $0 == "%NAME%" { getline; name=$0 }
        $0 == "%VERSION%" { getline; version=$0 }
        END { if (name != "" && version != "") printf "%s\t%s\n", name, version }
    ' "$desc" >> "$final_inventory"
done < <(
    sudo -n find "$workdir/rootfs/var/lib/pacman/local" \
        -mindepth 2 -maxdepth 2 -type f -name desc -print0
)
sort -u -o "$final_inventory" "$final_inventory"
sudo -n chown "$(id -u):$(id -g)" "$final_inventory" 2>/dev/null || true

if ! cmp -s "$bundle_dir/inventories/final-packages.txt" "$final_inventory"; then
    printf 'ERROR: completed locked rebuild package inventory differs from accepted baseline.\n' >&2
    diff -u "$bundle_dir/inventories/final-packages.txt" "$final_inventory" >&2 || true
    exit 1
fi

compressed_image="$artifact_dir/uconsole-archlinuxarm-${BASELINE_ROOTFS_RELEASE}-cm4.img.zst"
if [[ ! -s "$compressed_image" ]]; then
    printf 'ERROR: locked rebuild compressed image artifact missing.\n' >&2
    exit 1
fi

printf '\n=== STAGE 12 LOCKED REBUILD ===\n'
printf 'baseline_id=%s\n' "$BASELINE_ID"
printf 'builder_image_id=%s\n' "$builder_image_id"
printf 'final_inventory_sha256=%s\n' "$(sha256sum "$final_inventory" | awk '{print $1}')"
printf 'accepted_final_inventory_sha256=%s\n' "$BASELINE_FINAL_INVENTORY_SHA256"
printf 'compressed_image_sha256=%s\n' "$(sha256sum "$compressed_image" | awk '{print $1}')"
printf 'accepted_compressed_image_sha256=%s\n' "$BASELINE_IMAGE_COMPRESSED_SHA256"
printf 'byte_identical_image_required=%s\n' "$BASELINE_BYTE_IDENTICAL_IMAGE_REQUIRED"
printf '=== END STAGE 12 LOCKED REBUILD ===\n'
printf '\nPASS: locked baseline rebuild completed with exact accepted package inventory and no container network.\n'

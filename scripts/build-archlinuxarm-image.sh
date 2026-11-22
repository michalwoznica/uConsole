#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Arch Linux ARM image builder must run as root on the build host.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 3 ]]; then
    printf 'usage: %s INTEGRATED_ROOTFS PACKAGE_DIR OUTPUT_DIR\n' "$0" >&2
    exit 2
fi

rootfs="$1"
package_dir="$2"
output_dir="$3"

# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/rootfs.lock"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/image-layout.lock"
# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/release-baseline.lock"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/image-partition-filesystems.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/image-rootfs-copy.sh"

kernel_release="${UCONSOLE_IMAGE_KERNEL_RELEASE:-$BASELINE_KERNEL_RELEASE}"
rpi_linux_commit="${UCONSOLE_IMAGE_RPI_LINUX_COMMIT:-$RPI_LINUX_COMMIT}"
image_checkpoint="${UCONSOLE_IMAGE_CHECKPOINT:-archlinuxarm}"
image_variant="${UCONSOLE_IMAGE_VARIANT:-}"

if [[ ! "$kernel_release" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-uconsole$ ]]; then
    printf 'ERROR: invalid UCONSOLE_IMAGE_KERNEL_RELEASE: %s\n' "$kernel_release" >&2
    exit 1
fi
if [[ ! "$rpi_linux_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'ERROR: invalid UCONSOLE_IMAGE_RPI_LINUX_COMMIT.\n' >&2
    exit 1
fi
if [[ ! "$image_checkpoint" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'ERROR: invalid UCONSOLE_IMAGE_CHECKPOINT: %s\n' "$image_checkpoint" >&2
    exit 1
fi
if [[ -n "$image_variant" && ! "$image_variant" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
    printf 'ERROR: invalid UCONSOLE_IMAGE_VARIANT: %s\n' "$image_variant" >&2
    exit 1
fi

mkdir -p "$output_dir"

image_stem="uconsole-archlinuxarm-${ROOTFS_RELEASE}-cm4"
if [[ -n "$image_variant" ]]; then
    image_stem+="-${image_variant}"
fi
image_name="${image_stem}.img"
image="$output_dir/$image_name"
compressed="$image.zst"
manifest="$output_dir/${image_stem}.manifest"
raw_sha_file="$output_dir/${image_name}.sha256"
compressed_sha_file="$output_dir/${image_name}.zst.sha256"

mount_root="$(mktemp -d)"
loopdev=""

cleanup() {
    set +e
    if mountpoint -q "$mount_root/boot"; then
        umount "$mount_root/boot"
    fi
    if mountpoint -q "$mount_root"; then
        umount "$mount_root"
    fi
    if [[ -n "$loopdev" ]]; then
        losetup -d "$loopdev" 2>/dev/null || true
    fi
    rm -rf "$mount_root"
}
trap cleanup EXIT

printf 'Checking Arch Linux ARM image-layout contract...\n'

[[ "$PARTITION_TABLE" == "dos" ]]
[[ "$LOGICAL_SECTOR_SIZE" == "512" ]]
[[ "$IMAGE_SIZE_BYTES" == "8589934592" ]]
[[ "$BOOT_PARTITION_NUMBER" == "1" ]]
[[ "$ROOT_PARTITION_NUMBER" == "2" ]]
[[ "$BOOT_FILESYSTEM" == "vfat" ]]
[[ "$ROOT_FILESYSTEM" == "ext4" ]]
[[ "$BOOT_START_SECTOR" == "8192" ]]
[[ "$BOOT_SIZE_SECTORS" == "1048576" ]]

expected_root_start="$((BOOT_START_SECTOR + BOOT_SIZE_SECTORS))"
if [[ "$ROOT_START_SECTOR" != "$expected_root_start" ]]; then
    printf 'ERROR: root partition does not begin immediately after boot partition.\n' >&2
    exit 1
fi

disk_id="${DISK_IDENTIFIER_HEX#0x}"
disk_id="${disk_id,,}"
[[ "$BOOT_PARTUUID" == "${disk_id}-01" ]]
[[ "$ROOT_PARTUUID" == "${disk_id}-02" ]]

printf 'Checking integrated rootfs inputs...\n'
test -d "$rootfs"
test -s "$rootfs/boot/kernel8.img"
test -s "$rootfs/boot/bcm2711-rpi-cm4.dtb"
test -s "$rootfs/boot/overlays/clockworkpi-uconsole-cm4.dtbo"
test -d "$rootfs/usr/lib/modules/$kernel_release"
test -s "$rootfs/usr/lib/modules/$kernel_release/modules.dep"
test -s "$rootfs/usr/lib/modules/$kernel_release/modules.alias"
test -e "$rootfs/usr/lib/modules/$kernel_release/modules.devname"

cmp -s \
    "$repo_root/image/shared/boot/config-uconsole-cm4.txt" \
    "$rootfs/boot/config.txt"
cmp -s \
    "$repo_root/image/archlinuxarm/boot/cmdline-uconsole-cm4.txt" \
    "$rootfs/boot/cmdline.txt"
cmp -s \
    "$repo_root/image/archlinuxarm/rootfs/fstab-uconsole-cm4" \
    "$rootfs/etc/fstab"

mapfile -t package_files < <(
    find "$package_dir" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' \
        ! -name '*.sig' \
        | sort
)
if [[ "${#package_files[@]}" -ne 1 ]]; then
    printf 'ERROR: expected exactly one Arch Linux ARM linux-uconsole package.\n' >&2
    exit 1
fi
package_file="${package_files[0]}"

printf 'Creating sparse %s-byte raw image...\n' "$IMAGE_SIZE_BYTES"
rm -f "$image" "$compressed" "$manifest" "$raw_sha_file" "$compressed_sha_file"
truncate -s "$IMAGE_SIZE_BYTES" "$image"

printf 'Attaching raw image with explicit logical sector size...\n'
loopdev="$(
    losetup \
        --find \
        --show \
        --sector-size "$LOGICAL_SECTOR_SIZE" \
        "$image"
)"

actual_sector_size="$(blockdev --getss "$loopdev")"
if [[ "$actual_sector_size" != "$LOGICAL_SECTOR_SIZE" ]]; then
    printf 'ERROR: loop logical sector size mismatch: got %s expected %s\n' \
        "$actual_sector_size" "$LOGICAL_SECTOR_SIZE" >&2
    exit 1
fi

uconsole_write_image_partition_table "$loopdev"

printf 'Reattaching image with partition scanning enabled...\n'
losetup -d "$loopdev"
loopdev=""

loopdev="$(
    losetup \
        --find \
        --partscan \
        --show \
        --sector-size "$LOGICAL_SECTOR_SIZE" \
        "$image"
)"
udevadm settle

actual_sector_size="$(blockdev --getss "$loopdev")"
if [[ "$actual_sector_size" != "$LOGICAL_SECTOR_SIZE" ]]; then
    printf 'ERROR: reattached loop logical sector size mismatch: got %s expected %s\n' \
        "$actual_sector_size" "$LOGICAL_SECTOR_SIZE" >&2
    exit 1
fi

boot_part="${loopdev}p${BOOT_PARTITION_NUMBER}"
root_part="${loopdev}p${ROOT_PARTITION_NUMBER}"

for part in "$boot_part" "$root_part"; do
    for _ in $(seq 1 50); do
        [[ -b "$part" ]] && break
        sleep 0.1
    done
    if [[ ! -b "$part" ]]; then
        printf 'ERROR: loop partition device did not appear: %s\n' "$part" >&2
        exit 1
    fi
done

uconsole_format_image_filesystems "$boot_part" "$root_part"

printf 'Mounting image filesystems...\n'
mount "$root_part" "$mount_root"
mkdir -p "$mount_root/boot"
mount "$boot_part" "$mount_root/boot"

printf 'Checking rootfs capacity before copy...\n'
# Require at least 512 MiB free after the estimated root copy.
safety_bytes=$((512 * 1024 * 1024))
uconsole_check_image_rootfs_capacity \
    "$rootfs" \
    "$mount_root" \
    "$safety_bytes" \
    "Arch Linux ARM"

uconsole_copy_integrated_rootfs "$rootfs" "$mount_root"

sync

printf 'Validating populated image while mounted...\n'
test -s "$mount_root/boot/kernel8.img"
test -s "$mount_root/boot/bcm2711-rpi-cm4.dtb"
test -s "$mount_root/boot/overlays/clockworkpi-uconsole-cm4.dtbo"
test -d "$mount_root/usr/lib/modules/$kernel_release"
test -s "$mount_root/usr/lib/modules/$kernel_release/modules.dep"
test -s "$mount_root/usr/lib/modules/$kernel_release/modules.alias"
test -e "$mount_root/usr/lib/modules/$kernel_release/modules.devname"

cmp -s \
    "$repo_root/image/shared/boot/config-uconsole-cm4.txt" \
    "$mount_root/boot/config.txt"
cmp -s \
    "$repo_root/image/archlinuxarm/boot/cmdline-uconsole-cm4.txt" \
    "$mount_root/boot/cmdline.txt"
cmp -s \
    "$repo_root/image/archlinuxarm/rootfs/fstab-uconsole-cm4" \
    "$mount_root/etc/fstab"

mapfile -t image_linux_uconsole_dbs < <(
    find "$mount_root/var/lib/pacman/local" \
        -mindepth 2 \
        -maxdepth 2 \
        -type f \
        -name files \
        -path '*/linux-uconsole-*/files' \
        -print |
        sort
)
if [[ "${#image_linux_uconsole_dbs[@]}" -ne 1 ]]; then
    printf 'ERROR: image does not contain exactly one linux-uconsole local DB record.\n' >&2
    exit 1
fi
grep -Fxq 'boot/kernel8.img' "${image_linux_uconsole_dbs[0]}"

if find "$mount_root/var/lib/pacman/local" -maxdepth 1 -type d \
    \( -name 'linux-aarch64-*' -o -name 'uboot-raspberrypi-*' \) \
    | grep -q .; then
    printf 'ERROR: stock kernel/U-Boot package database residue found in image.\n' >&2
    exit 1
fi

if [[ -e "$mount_root/boot/boot.scr" || -e "$mount_root/boot/boot.txt" ]]; then
    printf 'ERROR: U-Boot boot-script residue found in image.\n' >&2
    exit 1
fi

printf 'Unmounting and checking filesystem consistency...\n'
umount "$mount_root/boot"
umount "$mount_root"

fsck.vfat -n "$boot_part"
e2fsck -f -n "$root_part"

losetup -d "$loopdev"
loopdev=""

printf 'Recording raw image checksum...\n'
raw_sha256="$(sha256sum "$image" | awk '{print $1}')"
printf '%s  %s\n' "$raw_sha256" "$(basename "$image")" > "$raw_sha_file"

printf 'Compressing image with zstd using all available CPUs...\n'
zstd \
    -T0 \
    -10 \
    --force \
    "$image" \
    -o "$compressed"

zstd -t "$compressed"

compressed_sha256="$(sha256sum "$compressed" | awk '{print $1}')"
printf '%s  %s\n' \
    "$compressed_sha256" "$(basename "$compressed")" \
    > "$compressed_sha_file"

package_sha256="$(sha256sum "$package_file" | awk '{print $1}')"

cat > "$manifest" <<EOF
checkpoint=$image_checkpoint
rootfs_release=$ROOTFS_RELEASE
rootfs_filename=$ROOTFS_FILENAME
rootfs_sha256=$ROOTFS_SHA256
rpi_linux_commit=$rpi_linux_commit
kernel_release=$kernel_release
package_filename=$(basename "$package_file")
package_sha256=$package_sha256
image_filename=$(basename "$image")
image_size_bytes=$IMAGE_SIZE_BYTES
image_raw_sha256=$raw_sha256
compressed_filename=$(basename "$compressed")
compressed_sha256=$compressed_sha256
partition_table=$PARTITION_TABLE
disk_identifier=$DISK_IDENTIFIER_HEX
boot_partuuid=$BOOT_PARTUUID
root_partuuid=$ROOT_PARTUUID
boot_filesystem=$BOOT_FILESYSTEM
root_filesystem=$ROOT_FILESYSTEM
boot_filesystem_label=$BOOT_FILESYSTEM_LABEL
root_filesystem_label=$ROOT_FILESYSTEM_LABEL
root_filesystem_uuid=$ROOT_FILESYSTEM_UUID
boot_start_sector=$BOOT_START_SECTOR
boot_size_sectors=$BOOT_SIZE_SECTORS
root_start_sector=$ROOT_START_SECTOR
initramfs_loaded=no
uboot_used=no
EOF

cp -f "$package_file" "$output_dir/"

# The compressed image is the distributable artifact. Keep checksums/manifest
# but remove the 8 GiB raw image to control CI workspace/artifact size.
rm -f "$image"

printf '\n=== ARCH LINUX ARM IMAGE ARTIFACT ===\n'
cat "$manifest"
printf '=== END ARCH LINUX ARM IMAGE ARTIFACT ===\n\n'

printf 'PASS: Arch Linux ARM partitioned microSD image built and validated.\n'

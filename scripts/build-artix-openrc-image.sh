#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Artix/OpenRC image builder must run as root on the build host.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 3 ]]; then
    printf 'usage: %s FINALIZED_ROOTFS LINUX_UCONSOLE_PACKAGE OUTPUT_DIR\n' "$0" >&2
    exit 2
fi

rootfs="$1"
package_file="$2"
output_dir="$3"

# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/rootfs.lock"
# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/rpi-support.lock"
# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/networking.lock"
# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/bluetooth.lock"
# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/image-layout.lock"
# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/image-partition-filesystems.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/image-rootfs-copy.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/image-artifacts.sh"

pkgbuild="$repo_root/image/shared/packages/linux-uconsole/PKGBUILD"
kernel_pkgver="$(awk -F= '$1 == "pkgver" { gsub(/[[:space:]'"'"']/, "", $2); print $2; exit }' "$pkgbuild")"
kernel_pkgrel="$(awk -F= '$1 == "pkgrel" { gsub(/[[:space:]'"'"']/, "", $2); print $2; exit }' "$pkgbuild")"
if [[ -z "$kernel_pkgver" || -z "$kernel_pkgrel" ]]; then
    printf 'ERROR: could not determine linux-uconsole package version from %s\n' "$pkgbuild" >&2
    exit 1
fi
kernel_package_version="${kernel_pkgver}-${kernel_pkgrel}"
kernel_release="${kernel_package_version}-uconsole"
rpi_linux_commit="${UCONSOLE_IMAGE_RPI_LINUX_COMMIT:-$RPI_LINUX_COMMIT}"
image_checkpoint="${UCONSOLE_IMAGE_CHECKPOINT:-artix-openrc}"
image_variant="${UCONSOLE_IMAGE_VARIANT:-}"

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

required_commands=(
    awk basename blkid blockdev bsdtar cat cmp cp df du e2fsck find
    fsck.vfat grep losetup mkdir mkfs.ext4 mkfs.vfat mktemp mount mountpoint
    readlink rm rsync seq sfdisk sha256sum sleep sort sync tail tr truncate
    udevadm umount zstd
)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing image-builder commands: %s\n' "${missing[*]}" >&2
    exit 1
fi

pkginfo_value() {
    local key="$1"
    bsdtar -xOf "$package_file" .PKGINFO |
        awk -F ' = ' -v key="$key" '$1 == key { print $2; exit }'
}

if [[ ! -s "$package_file" ]]; then
    printf 'ERROR: linux-uconsole package is missing or empty: %s\n' "$package_file" >&2
    exit 1
fi
if [[ "$(pkginfo_value pkgname)" != "linux-uconsole" ||
      "$(pkginfo_value pkgver)" != "$kernel_package_version" ||
      "$(pkginfo_value arch)" != "aarch64" ]]; then
    printf 'ERROR: supplied linux-uconsole package identity does not match repository PKGBUILD.\n' >&2
    exit 1
fi

mkdir -p "$output_dir"

image_stem="uconsole-artix-openrc-${ROOTFS_RELEASE}-cm4"
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

printf 'Checking Artix/OpenRC image-layout contract...\n'
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

validate_finalized_rootfs() {
    local tree="$1"

    test -d "$tree"
    test -s "$tree/boot/kernel8.img"
    test -s "$tree/boot/bcm2711-rpi-cm4.dtb"
    test -s "$tree/boot/overlays/clockworkpi-uconsole-cm4.dtbo"
    test -d "$tree/usr/lib/modules/$kernel_release"
    test -s "$tree/usr/lib/modules/$kernel_release/modules.dep"
    test -s "$tree/usr/lib/modules/$kernel_release/modules.alias"
    test -e "$tree/usr/lib/modules/$kernel_release/modules.devname"

    [[ "$(readlink "$tree/usr/bin/init")" == "openrc-init" ]]

    cmp -s \
        "$repo_root/image/shared/boot/config-uconsole-cm4.txt" \
        "$tree/boot/config.txt"
    cmp -s \
        "$repo_root/image/artix-openrc/boot/cmdline-uconsole-cm4.txt" \
        "$tree/boot/cmdline.txt"
    cmp -s \
        "$repo_root/image/artix-openrc/rootfs/fstab-uconsole-cm4" \
        "$tree/etc/fstab"
    cmp -s \
        "$repo_root/image/artix-openrc/rootfs/NetworkManager-uconsole.conf" \
        "$tree/etc/NetworkManager/conf.d/10-uconsole-dns.conf"
    cmp -s \
        "$repo_root/image/artix-openrc/rootfs/elogind-uconsole-power.conf" \
        "$tree/etc/elogind/logind.conf.d/99-uconsole-power.conf"

    [[ -L "$tree/etc/runlevels/default/$NETWORKMANAGER_SERVICE" ]]
    [[ "$(readlink "$tree/etc/runlevels/default/$NETWORKMANAGER_SERVICE")" == "/etc/init.d/$NETWORKMANAGER_SERVICE" ]]
    [[ ! -e "$tree/etc/runlevels/default/dhcpcd" && ! -L "$tree/etc/runlevels/default/dhcpcd" ]]
    [[ ! -e "$tree/etc/runlevels/default/wpa_supplicant" && ! -L "$tree/etc/runlevels/default/wpa_supplicant" ]]
    [[ -L "$tree/etc/runlevels/default/$BLUETOOTH_SERVICE" ]]
    [[ "$(readlink "$tree/etc/runlevels/default/$BLUETOOTH_SERVICE")" == "/etc/init.d/$BLUETOOTH_SERVICE" ]]
    [[ -L "$tree/etc/runlevels/default/dbus" ]]
    [[ "$(readlink "$tree/etc/runlevels/default/dbus")" == "/etc/init.d/dbus" ]]
    [[ -L "$tree/etc/runlevels/boot/elogind" ]]
    [[ "$(readlink "$tree/etc/runlevels/boot/elogind")" == "/etc/init.d/elogind" ]]

    if find "$tree/etc/runlevels" -type l -printf '%l\n' |
        grep -Ev '^/etc/init\.d/' |
        grep -q .; then
        printf 'ERROR: finalized Artix rootfs contains a non-OpenRC runlevel target.\n' >&2
        return 1
    fi

    if [[ -L "$tree/etc/resolv.conf" || ! -f "$tree/etc/resolv.conf" ]]; then
        printf 'ERROR: finalized Artix rootfs does not have the expected regular resolv.conf.\n' >&2
        return 1
    fi

    mapfile -t module_dirs < <(
        find "$tree/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    )
    if [[ "${#module_dirs[@]}" -ne 1 || "${module_dirs[0]}" != "$kernel_release" ]]; then
        printf 'ERROR: finalized Artix rootfs contains unexpected kernel module trees.\n' >&2
        printf '  %s\n' "${module_dirs[@]}" >&2
        return 1
    fi

    mapfile -t linux_uconsole_dbs < <(
        find "$tree/var/lib/pacman/local" \
            -mindepth 2 -maxdepth 2 -type f -name files \
            -path '*/linux-uconsole-*/files' -print | sort
    )
    if [[ "${#linux_uconsole_dbs[@]}" -ne 1 ]]; then
        printf 'ERROR: finalized Artix rootfs does not contain exactly one linux-uconsole local DB record.\n' >&2
        return 1
    fi
    grep -Fxq 'boot/kernel8.img' "${linux_uconsole_dbs[0]}"

    if find "$tree/var/lib/pacman/local" -maxdepth 1 -type d \
        \( -name 'linux-aarch64-*' -o -name 'linux-aarch64-lts-*' -o -name 'uboot-raspberrypi-*' \) \
        | grep -q .; then
        printf 'ERROR: stock kernel/U-Boot package database residue found in finalized Artix rootfs.\n' >&2
        return 1
    fi

    if [[ -e "$tree/boot/boot.scr" || -e "$tree/boot/boot.txt" ]]; then
        printf 'ERROR: U-Boot boot-script residue found in finalized Artix rootfs.\n' >&2
        return 1
    fi
}

printf 'Checking finalized Artix/OpenRC rootfs input...\n'
validate_finalized_rootfs "$rootfs"

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
safety_bytes=$((512 * 1024 * 1024))
uconsole_check_image_rootfs_capacity \
    "$rootfs" \
    "$mount_root" \
    "$safety_bytes" \
    "Artix Linux / OpenRC"

uconsole_copy_integrated_rootfs "$rootfs" "$mount_root"

sync

printf 'Validating populated Artix/OpenRC image while mounted...\n'
validate_finalized_rootfs "$mount_root"

printf 'Unmounting and checking filesystem consistency...\n'
umount "$mount_root/boot"
umount "$mount_root"

fsck.vfat -n "$boot_part"
e2fsck -f -n "$root_part"

losetup -d "$loopdev"
loopdev=""

uconsole_compress_and_checksum_image \
    "$image" \
    "$compressed" \
    "$raw_sha_file" \
    "$compressed_sha_file" \
    raw_sha256 \
    compressed_sha256

package_sha256="$(sha256sum "$package_file" | awk '{print $1}')"

cat > "$manifest" <<EOF_MANIFEST
checkpoint=$image_checkpoint
target=artix-openrc
init_system=openrc
rootfs_release=$ROOTFS_RELEASE
rootfs_filename=$ROOTFS_FILENAME
rootfs_sha256=$ROOTFS_SHA256
rpi_linux_commit=$rpi_linux_commit
kernel_release=$kernel_release
linux_uconsole_package_filename=$(basename "$package_file")
linux_uconsole_package_sha256=$package_sha256
rpi_firmware_package=${RPI_FIRMWARE_PKGNAME}-${RPI_FIRMWARE_PKGVER}
rpi_bootloader_package=${RPI_BOOTLOADER_PKGNAME}-${RPI_BOOTLOADER_PKGVER}
networkmanager_package=${NETWORKMANAGER_PKGNAME}-${NETWORKMANAGER_PKGVER}
networkmanager_openrc_package=${NETWORKMANAGER_OPENRC_PKGNAME}-${NETWORKMANAGER_OPENRC_PKGVER}
bluez_package=${BLUEZ_PKGNAME}-${BLUEZ_PKGVER}
bluez_utils_package=${BLUEZ_UTILS_PKGNAME}-${BLUEZ_UTILS_PKGVER}
bluez_openrc_package=${BLUEZ_OPENRC_PKGNAME}-${BLUEZ_OPENRC_PKGVER}
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
network_service=$NETWORKMANAGER_SERVICE
bluetooth_service=$BLUETOOTH_SERVICE
elogind_service=elogind
initramfs_loaded=no
uboot_used=no
EOF_MANIFEST

cp -f "$package_file" "$output_dir/"

# The compressed image is the distributable artifact. Keep checksums/manifest
# but remove the 8 GiB raw image to control workspace/artifact size.
rm -f "$image"

printf '\n=== ARTIX LINUX / OPENRC IMAGE ARTIFACT ===\n'
cat "$manifest"
printf '=== END ARTIX LINUX / OPENRC IMAGE ARTIFACT ===\n\n'

printf 'PASS: Artix Linux / OpenRC partitioned microSD image built and validated.\n'

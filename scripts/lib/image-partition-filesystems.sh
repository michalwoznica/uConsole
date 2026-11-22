#!/usr/bin/env bash

# Shared low-level image partition/filesystem helpers.
#
# The caller must source a target-specific image-layout lock before calling
# these functions. The lock remains authoritative for image identity, geometry,
# partition types, filesystem types, labels, PARTUUIDs and filesystem UUIDs.

uconsole_write_image_partition_table() {
    local loopdev="$1"
    local actual_disk_id

    printf 'Writing deterministic DOS partition table...\n'
    sfdisk \
        --wipe always \
        "$loopdev" <<EOF_LAYOUT
label: dos
label-id: $DISK_IDENTIFIER_HEX
unit: sectors
sector-size: $LOGICAL_SECTOR_SIZE

start=$BOOT_START_SECTOR, size=$BOOT_SIZE_SECTORS, type=$BOOT_PARTITION_TYPE, bootable
start=$ROOT_START_SECTOR, type=$ROOT_PARTITION_TYPE
EOF_LAYOUT

    actual_disk_id="$(sfdisk --disk-id "$loopdev" | tr '[:upper:]' '[:lower:]')"
    if [[ "$actual_disk_id" != "${DISK_IDENTIFIER_HEX,,}" ]]; then
        printf 'ERROR: disk identifier mismatch: got %s expected %s\n' \
            "$actual_disk_id" "${DISK_IDENTIFIER_HEX,,}" >&2
        return 1
    fi
}

uconsole_format_image_filesystems() {
    local boot_part="$1"
    local root_part="$2"
    local actual_boot_partuuid
    local actual_root_partuuid
    local actual_boot_label
    local actual_root_label
    local actual_root_uuid

    printf 'Creating deterministic FAT boot filesystem...\n'
    mkfs.vfat \
        -F 32 \
        -i "$BOOT_VOLUME_ID_HEX" \
        -n "$BOOT_FILESYSTEM_LABEL" \
        "$boot_part"

    printf 'Creating deterministic ext4 root filesystem identity...\n'
    mkfs.ext4 \
        -F \
        -U "$ROOT_FILESYSTEM_UUID" \
        -L "$ROOT_FILESYSTEM_LABEL" \
        -m 0 \
        -E lazy_itable_init=0,lazy_journal_init=0 \
        "$root_part"

    actual_boot_partuuid="$(blkid -s PARTUUID -o value "$boot_part")"
    actual_root_partuuid="$(blkid -s PARTUUID -o value "$root_part")"

    if [[ "${actual_boot_partuuid,,}" != "${BOOT_PARTUUID,,}" ]]; then
        printf 'ERROR: boot PARTUUID mismatch: got %s expected %s\n' \
            "$actual_boot_partuuid" "$BOOT_PARTUUID" >&2
        return 1
    fi

    if [[ "${actual_root_partuuid,,}" != "${ROOT_PARTUUID,,}" ]]; then
        printf 'ERROR: root PARTUUID mismatch: got %s expected %s\n' \
            "$actual_root_partuuid" "$ROOT_PARTUUID" >&2
        return 1
    fi

    actual_boot_label="$(blkid -s LABEL -o value "$boot_part")"
    actual_root_label="$(blkid -s LABEL -o value "$root_part")"
    actual_root_uuid="$(blkid -s UUID -o value "$root_part")"

    [[ "$actual_boot_label" == "$BOOT_FILESYSTEM_LABEL" ]]
    [[ "$actual_root_label" == "$ROOT_FILESYSTEM_LABEL" ]]
    [[ "${actual_root_uuid,,}" == "${ROOT_FILESYSTEM_UUID,,}" ]]
}

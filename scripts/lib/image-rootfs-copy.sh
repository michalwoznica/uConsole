#!/usr/bin/env bash

# Shared low-level helpers for sizing and copying an already-integrated rootfs
# into mounted image filesystems.
#
# The caller remains responsible for target-specific rootfs integration,
# filesystem mounting, validation, image identity and lifecycle policy.

uconsole_check_image_rootfs_capacity() {
    local rootfs="$1"
    local mount_root="$2"
    local safety_bytes="$3"
    local target_label="$4"
    local root_available
    local root_required

    root_available="$(df --output=avail -B1 "$mount_root" | tail -n1 | tr -d ' ')"
    root_required="$(du -sx -B1 "$rootfs" --exclude="$rootfs/boot" | awk '{print $1}')"

    if (( root_required + safety_bytes > root_available )); then
        printf 'ERROR: %s root partition too small: required=%s available=%s safety=%s\n' \
            "$target_label" "$root_required" "$root_available" "$safety_bytes" >&2
        return 1
    fi
}

uconsole_copy_integrated_rootfs() {
    local rootfs="$1"
    local mount_root="$2"

    printf 'Copying root filesystem with ownership/xattrs preserved...\n'
    rsync \
        -aHAX \
        --numeric-ids \
        --exclude='/boot/***' \
        "$rootfs/" \
        "$mount_root/"

    printf 'Copying boot filesystem content to FAT partition...\n'
    rsync \
        -rltL \
        --delete \
        --no-perms \
        --no-owner \
        --no-group \
        "$rootfs/boot/" \
        "$mount_root/boot/"
}

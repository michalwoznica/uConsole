#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
container_runtime="${CONTAINER_RUNTIME:-podman}"
workdir="${UCONSOLE_BUILD_DIR:-$repo_root/build/artix-openrc}"
artifact_dir="${UCONSOLE_ARTIFACT_DIR:-$repo_root/out/artix-openrc}"
rootfs_archive="${UCONSOLE_ARTIX_ROOTFS_ARCHIVE:-}"

if [[ "$#" -ne 5 ]]; then
    printf 'usage: %s LINUX_UCONSOLE_PACKAGE RPI_FIRMWARE_PACKAGE RPI_BOOTLOADER_PACKAGE NETWORK_PACKAGE_DIR BLUETOOTH_PACKAGE_DIR\n' "$0" >&2
    exit 2
fi

kernel_package="$(readlink -f "$1")"
firmware_package="$(readlink -f "$2")"
bootloader_package="$(readlink -f "$3")"
network_package_dir="$(readlink -f "$4")"
bluetooth_package_dir="$(readlink -f "$5")"

for package_file in "$kernel_package" "$firmware_package" "$bootloader_package"; do
    if [[ ! -s "$package_file" ]]; then
        printf 'ERROR: required package payload is missing or empty: %s\n' "$package_file" >&2
        exit 1
    fi
done
for package_dir in "$network_package_dir" "$bluetooth_package_dir"; do
    if [[ ! -d "$package_dir" ]]; then
        printf 'ERROR: required offline package directory is missing: %s\n' "$package_dir" >&2
        exit 1
    fi
    if ! find "$package_dir" -maxdepth 1 -type f \
        -name '*.pkg.tar*' ! -name '*.sig' -print -quit | grep -q .; then
        printf 'ERROR: offline package directory contains no package payloads: %s\n' \
            "$package_dir" >&2
        exit 1
    fi
done

if [[ -n "$rootfs_archive" ]]; then
    rootfs_archive="$(readlink -f "$rootfs_archive")"
    if [[ ! -s "$rootfs_archive" ]]; then
        printf 'ERROR: UCONSOLE_ARTIX_ROOTFS_ARCHIVE is missing or empty: %s\n' \
            "$rootfs_archive" >&2
        exit 1
    fi
fi

case "$container_runtime" in
    podman)
        container_cmd=(sudo -n podman)
        container_run_args=(--network host)
        ;;
    docker)
        container_cmd=(docker)
        container_run_args=()
        ;;
    *)
        printf 'ERROR: CONTAINER_RUNTIME must be podman or docker, got: %s\n' \
            "$container_runtime" >&2
        exit 1
        ;;
esac

required_commands=(
    awk blkid blockdev bsdtar cmp e2fsck find fsck.vfat grep losetup
    mkfs.ext4 mkfs.vfat mount mountpoint readlink rsync sfdisk sha256sum
    sudo sync truncate umount zstd
)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
command -v "$container_runtime" >/dev/null 2>&1 || missing+=("$container_runtime")
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing host commands: %s\n' "${missing[*]}" >&2
    if [[ -e /etc/arch-release ]]; then
        printf 'On Arch/Artix install local image-build prerequisites with:\n' >&2
        printf '  sudo pacman -S --needed podman dosfstools e2fsprogs libarchive rsync util-linux zstd\n' >&2
    fi
    exit 1
fi

printf 'Authenticating sudo for unattended Artix image build...\n'
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

printf 'Container runtime: %s\n' "$container_runtime"
printf 'Workspace: %s\n' "$workdir"
printf 'Artifacts: %s\n' "$artifact_dir"
printf 'Network package closure: %s\n' "$network_package_dir"
printf 'Bluetooth package closure: %s\n' "$bluetooth_package_dir"

sudo -n rm -rf "$workdir" "$artifact_dir"
mkdir -p "$workdir" "$artifact_dir"
chmod 0755 "$workdir" "$artifact_dir"

container_mounts=(
    -v "$repo_root:/repo:ro"
    -v "$workdir:/work"
    -v "$kernel_package:/input/linux-uconsole.pkg:ro"
    -v "$firmware_package:/input/firmware-raspberrypi.pkg:ro"
    -v "$bootloader_package:/input/raspberrypi-bootloader.pkg:ro"
    -v "$network_package_dir:/input/network-packages:ro"
    -v "$bluetooth_package_dir:/input/bluetooth-packages:ro"
)
container_env=()
if [[ -n "$rootfs_archive" ]]; then
    container_mounts+=( -v "$rootfs_archive:/input/armtix-rootfs.tar.xz:ro" )
    container_env+=( -e ARMTIX_ROOTFS_ARCHIVE=/input/armtix-rootfs.tar.xz )
    printf 'Using supplied pinned ARMtix rootfs archive: %s\n' "$rootfs_archive"
else
    printf 'Pinned ARMtix rootfs archive will be downloaded in the disposable build container.\n'
fi

printf 'Composing complete Artix/OpenRC rootfs in disposable container...\n'
"${container_cmd[@]}" run --rm \
    "${container_run_args[@]}" \
    "${container_env[@]}" \
    "${container_mounts[@]}" \
    docker.io/library/archlinux:base-devel \
    bash -lc '
        set -euo pipefail
        pacman -Syu --needed --noconfirm curl kmod libarchive

        bash /repo/scripts/build-artix-openrc-rootfs.sh \
            /work/rootfs \
            /input/linux-uconsole.pkg \
            /input/firmware-raspberrypi.pkg \
            /input/raspberrypi-bootloader.pkg

        bash /repo/scripts/configure-artix-openrc-networking.sh \
            /work/rootfs \
            /input/network-packages

        bash /repo/scripts/configure-artix-openrc-bluetooth.sh \
            /work/rootfs \
            /input/bluetooth-packages

        bash /repo/scripts/configure-artix-openrc-elogind.sh \
            /work/rootfs

        bash /repo/scripts/finalize-artix-openrc-rootfs.sh \
            /work/rootfs
    '

printf 'Building and validating partitioned Artix/OpenRC microSD image...\n'
sudo -n bash "$repo_root/scripts/build-artix-openrc-image.sh" \
    "$workdir/rootfs" \
    "$kernel_package" \
    "$artifact_dir"

sudo -n chown -R "$(id -u):$(id -g)" "$artifact_dir"

printf '\nPASS: local uConsole Artix/OpenRC image build complete.\n'
printf 'Artifacts:\n'
ls -lh "$artifact_dir"

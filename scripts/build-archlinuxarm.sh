#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
container_runtime="${CONTAINER_RUNTIME:-podman}"
workdir="${UCONSOLE_BUILD_DIR:-$repo_root/build/archlinuxarm}"
artifact_dir="${UCONSOLE_ARTIFACT_DIR:-$repo_root/out/archlinuxarm}"
cache_dir="${UCONSOLE_CACHE_DIR:-$repo_root/build/archlinuxarm-cache}"
jobs="${JOBS:-$(nproc)}"
rebuild_kernel="${UCONSOLE_REBUILD_KERNEL:-0}"

if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: JOBS must be a positive integer, got: %s\n' "$jobs" >&2
    exit 1
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
    sudo
    sha256sum
    find
    sort
    xargs
    awk
    losetup
    blockdev
    sfdisk
    udevadm
    mkfs.vfat
    fsck.vfat
    mkfs.ext4
    e2fsck
    mount
    umount
    mountpoint
    blkid
    rsync
    zstd
)

missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
command -v "$container_runtime" >/dev/null 2>&1 || missing+=("$container_runtime")

if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing host commands: %s\n' "${missing[*]}" >&2
    if [[ -e /etc/arch-release ]]; then
        printf 'On Arch Linux install the local image-build prerequisites with:\n' >&2
        printf '  sudo pacman -S --needed podman dosfstools e2fsprogs rsync util-linux zstd\n' >&2
    fi
    exit 1
fi

# Image construction needs real host numeric ownership and loop/mount access.
# Rootful Podman preserves the same UID/GID semantics as Docker on GitHub Actions.
# Authenticate once before any long-running work, then refresh the sudo timestamp
# in the background so an unattended build never stops later for a password.
printf 'Authenticating sudo for unattended image build...\n'
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
printf 'Parallel build jobs: %s\n' "$jobs"
printf 'Workspace: %s\n' "$workdir"
printf 'Artifacts: %s\n' "$artifact_dir"
printf 'Cache: %s\n' "$cache_dir"

sudo -n rm -rf "$workdir" "$artifact_dir"
mkdir -p "$workdir" "$artifact_dir" "$cache_dir/kernel-packages"
chmod 0755 "$workdir" "$artifact_dir" "$cache_dir" "$cache_dir/kernel-packages"

kernel_inputs=(
    "$repo_root/image/archlinuxarm/packages/linux-uconsole/PKGBUILD"
    "$repo_root/image/archlinuxarm/packages/linux-uconsole/linux-uconsole.preset"
    "$repo_root/kernel/config/uconsole-cm4.config"
    "$repo_root/kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts"
    "$repo_root/kernel/drivers/uconsole-amp-switch.c"
    "$repo_root/scripts/stage-arch-kernel-package.sh"
)
for patch_file in "$repo_root"/kernel/patches/000[1-5]-*.patch; do
    kernel_inputs+=("$patch_file")
done

kernel_input_hash="$({
    printf '%s\0' "${kernel_inputs[@]}" |
        sort -z |
        xargs -0 sha256sum
} | sha256sum | awk '{print $1}')"

kernel_cache_dir="$cache_dir/kernel-packages/$kernel_input_hash"
mkdir -p "$kernel_cache_dir"

mapfile -t cached_packages < <(
    find "$kernel_cache_dir" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' \
        ! -name '*.sig' \
        | sort
)

container_env=(
    -e "JOBS=$jobs"
)

if [[ "$rebuild_kernel" != "1" && "${#cached_packages[@]}" -eq 1 ]]; then
    cached_name="$(basename "${cached_packages[0]}")"
    printf 'Reusing cached linux-uconsole package: %s\n' "$cached_name"
    container_env+=(
        -e "UCONSOLE_PREBUILT_KERNEL_PACKAGE=/cache/kernel-packages/$kernel_input_hash/$cached_name"
    )
else
    if [[ "$rebuild_kernel" == "1" ]]; then
        printf 'Kernel package cache bypassed by UCONSOLE_REBUILD_KERNEL=1.\n'
    else
        printf 'No matching cached linux-uconsole package; kernel will be built.\n'
    fi
fi

set +e
"${container_cmd[@]}" run --rm \
    "${container_run_args[@]}" \
    "${container_env[@]}" \
    -v "$repo_root:/repo:ro" \
    -v "$workdir:/work" \
    -v "$cache_dir:/cache:ro" \
    docker.io/library/archlinux:base-devel \
    bash -lc '
        set -euo pipefail
        pacman -Syu --needed --noconfirm \
            aarch64-linux-gnu-gcc \
            bc bison curl dtc flex git gnupg inetutils kmod \
            libarchive libcap libelf openssl patch perl python rsync
        bash /repo/scripts/build-archlinuxarm-rootfs.sh \
            /work/rootfs \
            /work/packages
    '
container_status=$?
set -e

mapfile -t built_packages < <(
    sudo -n find "$workdir/packages" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' \
        ! -name '*.sig' \
        2>/dev/null \
        | sort
)

if [[ "${#built_packages[@]}" -eq 1 ]]; then
    built_name="$(basename "${built_packages[0]}")"
    if [[ ! -s "$kernel_cache_dir/$built_name" ]]; then
        sudo -n cp -a "${built_packages[0]}" "$kernel_cache_dir/$built_name"
        sudo -n chown "$(id -u):$(id -g)" "$kernel_cache_dir/$built_name"
        printf 'Cached linux-uconsole package for later local builds: %s\n' "$built_name"
    fi
fi

if [[ "$container_status" -ne 0 ]]; then
    printf 'ERROR: integrated rootfs build failed. Workspace retained at %s\n' \
        "$workdir" >&2
    exit "$container_status"
fi

printf 'Building and validating partitioned microSD image...\n'
sudo -n bash "$repo_root/scripts/build-archlinuxarm-image.sh" \
    "$workdir/rootfs" \
    "$workdir/packages" \
    "$artifact_dir"

sudo -n chown -R "$(id -u):$(id -g)" "$artifact_dir"

printf '\nPASS: local uConsole image build complete.\n'
printf 'Artifacts:\n'
ls -lh "$artifact_dir"

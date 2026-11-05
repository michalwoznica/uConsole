#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Stage 9B must run as root inside the disposable CI container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/rootfs.lock"

kernel_release="6.18.60-1-uconsole"
jobs="${JOBS:-$(nproc)}"

if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: JOBS must be a positive integer, got: %s\n' "$jobs" >&2
    exit 1
fi

workdir="$(mktemp -d)"
chmod 0755 "$workdir"

cleanup() {
    chmod -R u+rwX "$workdir" 2>/dev/null || true
    rm -rf "$workdir"
}
trap cleanup EXIT

archive="$workdir/$ROOTFS_FILENAME"
md5_file="$archive$ROOTFS_MD5_SUFFIX"
sig_file="$archive$ROOTFS_SIGNATURE_SUFFIX"
keyring_source="$workdir/archlinuxarm-source.gpg"
keyring="$workdir/archlinuxarm-binary.gpg"
rootfs="$workdir/rootfs"
package_stage="$workdir/linux-uconsole-package"
pkgdest="$workdir/packages"
build_home="$workdir/build-home"

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

printf 'Checking Stage 9B rootfs/package policy...\n'

case "$ROOTFS_FILENAME" in
    *-latest*)
        printf 'ERROR: Stage 9B rootfs input must be versioned, not -latest.\n' >&2
        exit 1
        ;;
esac

for required_stock in \
    linux-aarch64 \
    uboot-raspberrypi \
    firmware-raspberrypi \
    raspberrypi-bootloader \
    mkinitcpio
do
    grep -Fxq "$required_stock" \
        "$repo_root/image/archlinuxarm/stage9a-stock-kernel-boot-packages.txt"
done

printf 'Fetching and authenticating pinned Arch Linux ARM rootfs...\n'
download_versioned_input "$ROOTFS_FILENAME" "$archive"
download_versioned_input \
    "${ROOTFS_FILENAME}${ROOTFS_MD5_SUFFIX}" \
    "$md5_file"
download_versioned_input \
    "${ROOTFS_FILENAME}${ROOTFS_SIGNATURE_SUFFIX}" \
    "$sig_file"

actual_size="$(stat -c '%s' "$archive")"
if [[ "$actual_size" != "$ROOTFS_EXPECTED_SIZE" ]]; then
    printf 'ERROR: rootfs size mismatch: got %s expected %s\n' \
        "$actual_size" "$ROOTFS_EXPECTED_SIZE" >&2
    exit 1
fi

published_md5="$(awk 'NF {print $1; exit}' "$md5_file")"
actual_md5="$(md5sum "$archive" | awk '{print $1}')"
if [[ "${actual_md5,,}" != "${published_md5,,}" ]]; then
    printf 'ERROR: rootfs MD5 mismatch.\n' >&2
    exit 1
fi

actual_sha256="$(sha256sum "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$ROOTFS_SHA256" ]]; then
    printf 'ERROR: rootfs SHA-256 mismatch: got %s expected %s\n' \
        "$actual_sha256" "$ROOTFS_SHA256" >&2
    exit 1
fi

keyring_member="$(
    bsdtar -tf "$archive" |
        grep -E '(^|^\./)usr/share/pacman/keyrings/archlinuxarm\.gpg$' |
        head -n 1
)"
if [[ -z "$keyring_member" ]]; then
    printf 'ERROR: Arch Linux ARM keyring not found in rootfs archive.\n' >&2
    exit 1
fi

bsdtar -xOf "$archive" "$keyring_member" > "$keyring_source"
test -s "$keyring_source"

if grep -aqm1 '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$keyring_source"; then
    gpg \
        --batch \
        --yes \
        --dearmor \
        --output "$keyring" \
        "$keyring_source"
else
    cp "$keyring_source" "$keyring"
fi

gpgv_status="$workdir/gpgv-status.txt"
gpgv_log="$workdir/gpgv-log.txt"

if ! gpgv \
    --status-fd=1 \
    --keyring "$keyring" \
    "$sig_file" "$archive" \
    >"$gpgv_status" \
    2>"$gpgv_log"; then
    printf 'ERROR: detached rootfs signature verification failed.\n' >&2
    cat "$gpgv_status" >&2 || true
    cat "$gpgv_log" >&2 || true
    exit 1
fi

if ! awk \
    -v expected="$ROOTFS_SIGNING_FINGERPRINT" \
    '$1 == "[GNUPG:]" && $2 == "VALIDSIG" &&
     ($3 == expected || $12 == expected) {
         found = 1
     }
     END {
         exit(found ? 0 : 1)
     }' \
    "$gpgv_status"; then
    printf 'ERROR: rootfs signature identity mismatch.\n' >&2
    cat "$gpgv_status" >&2
    exit 1
fi

printf 'Extracting authenticated rootfs as container root...\n'
mkdir -p "$rootfs"
bsdtar -xpf "$archive" -C "$rootfs"

printf 'Verifying Stage 9A stock package state in extracted rootfs...\n'
pacman_target() {
    pacman \
        --sysroot "$rootfs" \
        --arch aarch64 \
        "$@"
}

for pkg in \
    linux-aarch64 \
    uboot-raspberrypi \
    firmware-raspberrypi \
    raspberrypi-bootloader \
    mkinitcpio
do
    pacman_target -Q "$pkg" >/dev/null
done

printf 'Staging real linux-uconsole makepkg workspace...\n'
bash "$repo_root/scripts/stage-arch-kernel-package.sh" "$package_stage"
mkdir -p "$pkgdest" "$build_home"

if ! id -u uconsole-build >/dev/null 2>&1; then
    useradd --no-create-home --home-dir "$build_home" --shell /bin/bash uconsole-build
fi

chown -R uconsole-build:uconsole-build \
    "$package_stage" "$pkgdest" "$build_home"

printf 'Cross-building real aarch64 pacman package with makepkg (-j%s)...\n' "$jobs"
runuser -u uconsole-build -- \
    env \
        HOME="$build_home" \
        CARCH=aarch64 \
        ARCH=arm64 \
        CROSS_COMPILE=aarch64-linux-gnu- \
        MAKEFLAGS="-j${jobs}" \
        PKGDEST="$pkgdest" \
        makepkg \
            --ignorearch \
            --nodeps \
            --cleanbuild \
            --force \
            --noconfirm \
            --nocheck \
            --dir "$package_stage"

mapfile -t package_files < <(
    find "$pkgdest" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' \
        ! -name '*.sig' \
        | sort
)

if [[ "${#package_files[@]}" -ne 1 ]]; then
    printf 'ERROR: expected exactly one linux-uconsole aarch64 package, got %s.\n' \
        "${#package_files[@]}" >&2
    printf '%s\n' "${package_files[@]:-}" >&2
    exit 1
fi

package_file="${package_files[0]}"
printf 'Built package: %s\n' "$(basename "$package_file")"

printf 'Checking built package metadata...\n'
pkginfo="$workdir/PKGINFO"
bsdtar -xOf "$package_file" .PKGINFO > "$pkginfo"

grep -Fxq 'pkgname = linux-uconsole' "$pkginfo"
grep -Fxq 'pkgver = 6.18.60-1' "$pkginfo"
grep -Fxq 'arch = aarch64' "$pkginfo"
grep -Fxq 'conflict = linux-aarch64' "$pkginfo"
grep -Fxq 'conflict = uboot-raspberrypi' "$pkginfo"
grep -Fxq 'depend = firmware-raspberrypi' "$pkginfo"
grep -Fxq 'depend = raspberrypi-bootloader' "$pkginfo"
grep -Eq '^depend = mkinitcpio(>=0\.7)?$' "$pkginfo"

printf 'Temporarily disabling target ALPM hooks for cross-architecture transaction...\n'
system_hooks="$rootfs/usr/share/libalpm/hooks"
system_hooks_saved="$rootfs/usr/share/libalpm/hooks.stage9b-saved"
custom_hooks="$rootfs/etc/pacman.d/hooks"
custom_hooks_saved="$rootfs/etc/pacman.d/hooks.stage9b-saved"

if [[ -e "$system_hooks_saved" || -e "$custom_hooks_saved" ]]; then
    printf 'ERROR: unexpected Stage 9B hook-save path already exists.\n' >&2
    exit 1
fi

if [[ -d "$system_hooks" ]]; then
    mv "$system_hooks" "$system_hooks_saved"
fi
mkdir -p "$system_hooks"

if [[ -d "$custom_hooks" ]]; then
    mv "$custom_hooks" "$custom_hooks_saved"
fi
mkdir -p "$custom_hooks"

printf 'Removing stock kernel and U-Boot packages from target rootfs...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --nosave \
    -Rdd \
    linux-aarch64 \
    uboot-raspberrypi

printf 'Installing linux-uconsole into target rootfs through pacman...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --asexplicit \
    -U "$package_file"

rm -rf "$system_hooks" "$custom_hooks"
if [[ -d "$system_hooks_saved" ]]; then
    mv "$system_hooks_saved" "$system_hooks"
fi
if [[ -d "$custom_hooks_saved" ]]; then
    mv "$custom_hooks_saved" "$custom_hooks"
fi

printf 'Installing project boot policy outside the kernel package...\n'
install -Dm644 \
    "$repo_root/image/archlinuxarm/boot/config-uconsole-cm4.txt" \
    "$rootfs/boot/config.txt"

printf 'Verifying target package database transition...\n'
pacman_target -Q linux-uconsole |
    grep -Fxq 'linux-uconsole 6.18.60-1'

if pacman_target -Q linux-aarch64 >/dev/null 2>&1; then
    printf 'ERROR: linux-aarch64 is still registered after replacement.\n' >&2
    exit 1
fi

if pacman_target -Q uboot-raspberrypi >/dev/null 2>&1; then
    printf 'ERROR: uboot-raspberrypi is still registered after direct-kernel transition.\n' >&2
    exit 1
fi

for retained in \
    firmware-raspberrypi \
    raspberrypi-bootloader \
    mkinitcpio \
    linux-firmware
do
    pacman_target -Q "$retained" >/dev/null
done

printf 'Checking local package database consistency...\n'
pacman_target -Dk

printf 'Checking linux-uconsole installed files...\n'
pacman_target -Qk linux-uconsole

test -s "$rootfs/boot/kernel8.img"
test -s "$rootfs/boot/bcm2711-rpi-cm4.dtb"
test -s "$rootfs/boot/overlays/clockworkpi-uconsole-cm4.dtbo"
test -s "$rootfs/etc/mkinitcpio.d/linux-uconsole.preset"
test -d "$rootfs/usr/lib/modules/$kernel_release"

cmp -s \
    "$repo_root/image/archlinuxarm/boot/config-uconsole-cm4.txt" \
    "$rootfs/boot/config.txt"

pacman_target -Qo /boot/kernel8.img |
    grep -q 'linux-uconsole'

if pacman_target -Qo /boot/config.txt >/dev/null 2>&1; then
    printf 'ERROR: /boot/config.txt unexpectedly remains package-owned.\n' >&2
    exit 1
fi

if [[ -e "$rootfs/boot/boot.scr" || -e "$rootfs/boot/boot.txt" ]]; then
    printf 'ERROR: U-Boot boot script residue remains after package removal.\n' >&2
    ls -l "$rootfs/boot/boot.scr" "$rootfs/boot/boot.txt" 2>/dev/null || true
    exit 1
fi

printf '\n=== STAGE 9B FINAL PACKAGE STATE ===\n'
for pkg in \
    linux-uconsole \
    firmware-raspberrypi \
    raspberrypi-bootloader \
    mkinitcpio \
    linux-firmware
do
    pacman_target -Q "$pkg"
done
printf '=== END PACKAGE STATE ===\n\n'

printf 'PASS: Stage 9B pacman-managed rootfs integration validated.\n'

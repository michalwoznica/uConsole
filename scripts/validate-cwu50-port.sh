#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"
# shellcheck disable=SC1091
source "$repo_root/kernel/sources/cwu50.lock"

arch="${ARCH:-arm64}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
jobs="${JOBS:-2}"

workdir="$(mktemp -d)"
cleanup() {
    rm -rf "$workdir"
}
trap cleanup EXIT

linux_tar="$workdir/linux.tar.gz"
linux_src="$workdir/linux"

printf 'Fetching Raspberry Pi Linux %s (%s)...\n' \
    "$RPI_LINUX_VERSION" "$RPI_LINUX_COMMIT"
curl --fail --location --silent --show-error \
    "https://github.com/raspberrypi/linux/archive/${RPI_LINUX_COMMIT}.tar.gz" \
    --output "$linux_tar"

mkdir "$linux_src"
tar -xzf "$linux_tar" --strip-components=1 -C "$linux_src"

printf 'Fetching pinned AK-Rex CWU50 source (%s)...\n' "$CWU50_SOURCE_COMMIT"
curl --fail --location --silent --show-error \
    "$CWU50_SOURCE_URL" \
    --output "$linux_src/drivers/gpu/drm/panel/panel-cwu50.c"

printf 'Applying CWU50 integration patch...\n'
patch --directory="$linux_src" --strip=1 --forward \
    < "$repo_root/kernel/patches/0001-drm-panel-integrate-cwu50.patch"

printf 'Checking integration...\n'
grep -q '^config DRM_PANEL_CWU50$' "$linux_src/drivers/gpu/drm/panel/Kconfig"
grep -q 'CONFIG_DRM_PANEL_CWU50.*panel-cwu50.o' "$linux_src/drivers/gpu/drm/panel/Makefile"
grep -q 'compatible = "cw,cwu50"' "$linux_src/drivers/gpu/drm/panel/panel-cwu50.c"

printf 'Configuring BCM2711/CM4 kernel...\n'
make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    bcm2711_defconfig

"$linux_src/scripts/config" --file "$linux_src/.config" --module DRM_PANEL_CWU50
make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    olddefconfig

grep -q '^CONFIG_DRM_PANEL_CWU50=m$' "$linux_src/.config"

printf 'Compiling CWU50 panel object...\n'
make -C "$linux_src" -j"$jobs" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    drivers/gpu/drm/panel/panel-cwu50.o

test -s "$linux_src/drivers/gpu/drm/panel/panel-cwu50.o"

printf 'PASS: CWU50 source materialized, patch applied, Kconfig enabled, and panel object compiled.\n'

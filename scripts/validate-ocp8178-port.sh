#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"
# shellcheck disable=SC1091
source "$repo_root/kernel/sources/ocp8178.lock"

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

printf 'Fetching pinned AK-Rex OCP8178 source (%s)...\n' "$OCP8178_SOURCE_COMMIT"
curl --fail --location --silent --show-error \
    "$OCP8178_SOURCE_URL" \
    --output "$linux_src/drivers/video/backlight/ocp8178_bl.c"

printf 'Applying OCP8178 integration/refinement patch...\n'
if ! patch --directory="$linux_src" --strip=1 --forward --fuzz=0 \
    < "$repo_root/kernel/patches/0002-video-backlight-integrate-ocp8178.patch"; then
    printf 'ERROR: OCP8178 patch did not apply to the pinned inputs.\n' >&2
    printf 'Kconfig anchor:\n' >&2
    grep -n -A8 -B5 '^config BACKLIGHT_OMAP1$' \
        "$linux_src/drivers/video/backlight/Kconfig" >&2 || true
    printf 'Makefile anchor:\n' >&2
    grep -n -A3 -B3 'CONFIG_BACKLIGHT_OMAP1' \
        "$linux_src/drivers/video/backlight/Makefile" >&2 || true
    printf 'Driver brightness anchors:\n' >&2
    grep -n -E 'MAX_BRIGHTNESS_VALUE|ocp8178_bl_table' \
        "$linux_src/drivers/video/backlight/ocp8178_bl.c" >&2 || true
    exit 1
fi

printf 'Checking integration and selected behavior...\n'
grep -q '^config BACKLIGHT_OCP8178$' "$linux_src/drivers/video/backlight/Kconfig"
grep -q 'CONFIG_BACKLIGHT_OCP8178.*ocp8178_bl.o' "$linux_src/drivers/video/backlight/Makefile"
grep -q '^#define MAX_BRIGHTNESS_VALUE 21$' "$linux_src/drivers/video/backlight/ocp8178_bl.c"
grep -q '0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 22, 25, 28, 31' \
    "$linux_src/drivers/video/backlight/ocp8178_bl.c"
grep -q 'bool onewire_ready;' "$linux_src/drivers/video/backlight/ocp8178_bl.c"
grep -q 'if (!gbl->onewire_ready' "$linux_src/drivers/video/backlight/ocp8178_bl.c"

printf 'Configuring BCM2711/CM4 kernel...\n'
make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    bcm2711_defconfig

"$linux_src/scripts/config" --file "$linux_src/.config" --module BACKLIGHT_OCP8178
make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    olddefconfig

grep -q '^CONFIG_BACKLIGHT_OCP8178=m$' "$linux_src/.config"

printf 'Compiling OCP8178 backlight object...\n'
make -C "$linux_src" -j"$jobs" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    drivers/video/backlight/ocp8178_bl.o

test -s "$linux_src/drivers/video/backlight/ocp8178_bl.o"

printf 'PASS: OCP8178 source materialized, patch applied, behavior checks passed, and backlight object compiled.\n'

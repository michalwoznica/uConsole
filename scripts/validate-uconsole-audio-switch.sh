#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/kernel/source.lock"

arch="${ARCH:-arm64}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
jobs="${JOBS:-2}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

linux_tar="$workdir/linux.tar.gz"
linux_src="$workdir/linux"
driver_src="$repo_root/kernel/drivers/uconsole-amp-switch.c"
driver_dst="$linux_src/drivers/misc/uconsole-amp-switch.c"
patch_file="$repo_root/kernel/patches/0005-misc-integrate-uconsole-amplifier-switch.patch"
overlay="$repo_root/kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts"

printf 'Checking Stage 6 driver and overlay policy...\n'

grep -q 'devm_request_threaded_irq' "$driver_src"
grep -q 'IRQF_ONESHOT' "$driver_src"
grep -q 'gpiod_get_value_cansleep' "$driver_src"
grep -q 'gpiod_set_value_cansleep' "$driver_src"
grep -q '"clockworkpi,uconsole-amplifier-switch"' "$driver_src"

if grep -qE 'devm_request_irq\(|bitmap_alloc|gpiod_set_array_value_cansleep|msleep|schedule_delayed_work|gpio=11' "$driver_src"; then
    printf 'ERROR: Stage 6 driver contains rejected hard-IRQ/polling/firmware-GPIO behavior.\n' >&2
    exit 1
fi

grep -q 'compatible = "clockworkpi,uconsole-amplifier-switch";' "$overlay"
grep -q 'headphone-detect-gpios = <&gpio 10 GPIO_ACTIVE_HIGH>;' "$overlay"
grep -q 'amplifier-enable-gpios = <&gpio 11 GPIO_ACTIVE_HIGH>;' "$overlay"

if grep -q 'simple-amplifier-switch' "$overlay"; then
    printf 'ERROR: legacy generic amplifier-switch compatible remains in overlay.\n' >&2
    exit 1
fi

printf 'Fetching Raspberry Pi Linux %s (%s)...\n' \
    "$RPI_LINUX_VERSION" "$RPI_LINUX_COMMIT"
curl --fail --location --silent --show-error \
    "https://github.com/raspberrypi/linux/archive/${RPI_LINUX_COMMIT}.tar.gz" \
    --output "$linux_tar"

mkdir "$linux_src"
tar -xzf "$linux_tar" --strip-components=1 -C "$linux_src"

cp "$driver_src" "$driver_dst"

printf 'Checking Stage 6 integration patch against exact pinned source...\n'
if ! patch --directory="$linux_src" --strip=1 --forward --fuzz=0 --dry-run \
    < "$patch_file"; then
    printf 'ERROR: Stage 6 integration patch does not apply.\n' >&2
    printf 'Exact Kconfig anchor:\n' >&2
    grep -n -A6 -B4 '^config BCM2835_SMI' \
        "$linux_src/drivers/misc/Kconfig" >&2 || true
    printf 'Exact Makefile anchor:\n' >&2
    grep -n -A2 -B1 'CONFIG_BCM2835_SMI' \
        "$linux_src/drivers/misc/Makefile" >&2 || true
    exit 1
fi

printf 'Applying Stage 6 integration patch...\n'
patch --directory="$linux_src" --strip=1 --forward --fuzz=0 \
    < "$patch_file"

printf 'Configuring uConsole amplifier switch as a module...\n'
make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    bcm2711_defconfig

"$linux_src/scripts/config" \
    --file "$linux_src/.config" \
    --module UCONSOLE_AMP_SWITCH

make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    olddefconfig

grep -q '^CONFIG_UCONSOLE_AMP_SWITCH=m$' "$linux_src/.config"

printf 'Compiling uConsole amplifier-switch object...\n'
make -C "$linux_src" -j"$jobs" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    drivers/misc/uconsole-amp-switch.o

test -s "$linux_src/drivers/misc/uconsole-amp-switch.o"

printf 'PASS: uConsole threaded-IRQ amplifier switch compiled for ARM64.\n'

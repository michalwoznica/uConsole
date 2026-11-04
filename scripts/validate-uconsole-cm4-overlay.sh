#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"

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
overlay_src="$repo_root/kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts"
overlay_dst="$linux_src/arch/arm/boot/dts/overlays/clockworkpi-uconsole-cm4-overlay.dts"
makefile_patch="$repo_root/kernel/patches/0003-arm-dts-build-uconsole-cm4-overlay.patch"

printf 'Checking project overlay policy...\n'

grep -q 'compatible = "cw,cwu50";' "$overlay_src"
grep -q 'compatible = "ocp8178-backlight";' "$overlay_src"
grep -q 'reset-gpios = <&gpio 8 GPIO_ACTIVE_LOW>;' "$overlay_src"
grep -q 'backlight-control-gpios = <&gpio 9 GPIO_ACTIVE_HIGH>;' "$overlay_src"
grep -q 'iovcc-supply = <&reg_dcdc3>;' "$overlay_src"
grep -q 'vci-supply = <&reg_aldo2>;' "$overlay_src"
grep -q 'regulator-name = "sys-1v8";' "$overlay_src"
grep -q 'default-brightness = <15>;' "$overlay_src"

grep -q 'charge-full-design-microamp-hours = <0>;' "$overlay_src"
grep -q 'energy-full-design-microwatt-hours = <0>;' "$overlay_src"
grep -q 'batt_uah = <&battery>,"charge-full-design-microamp-hours:0";' "$overlay_src"
grep -q 'batt_uwh = <&battery>,"energy-full-design-microwatt-hours:0";' "$overlay_src"
grep -q 'vmin_uv = <&battery>,"voltage-min-design-microvolt:0";' "$overlay_src"

if grep -qE 'target = <&(pcie0|genet)>|sd-uhs-|max-frequency = <100000000>|simple-amplifier-switch|nominal-microvolt|bootargs[[:space:]]*=|irq-gpios' "$overlay_src"; then
    printf 'ERROR: overlay contains intentionally excluded policy or deferred features.\n' >&2
    exit 1
fi

printf 'Fetching Raspberry Pi Linux %s (%s)...\n' \
    "$RPI_LINUX_VERSION" "$RPI_LINUX_COMMIT"
curl --fail --location --silent --show-error \
    "https://github.com/raspberrypi/linux/archive/${RPI_LINUX_COMMIT}.tar.gz" \
    --output "$linux_tar"

mkdir "$linux_src"
tar -xzf "$linux_tar" --strip-components=1 -C "$linux_src"

cp "$overlay_src" "$overlay_dst"

printf 'Checking overlay Makefile integration patch...\n'
patch --directory="$linux_src" --strip=1 --forward --fuzz=0 --dry-run \
    < "$makefile_patch"

printf 'Applying overlay Makefile integration patch...\n'
patch --directory="$linux_src" --strip=1 --forward --fuzz=0 \
    < "$makefile_patch"

printf 'Configuring BCM2711/CM4 device-tree build...\n'
make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    bcm2711_defconfig

printf 'Building Raspberry Pi device trees and overlays...\n'
make -C "$linux_src" -j"$jobs" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    dtbs

dtbo="$(find "$linux_src" -type f -name 'clockworkpi-uconsole-cm4.dtbo' -print -quit)"
base_dtb="$(find "$linux_src" -type f -name 'bcm2711-rpi-cm4.dtb' -print -quit)"

if [[ -z "$dtbo" || ! -s "$dtbo" ]]; then
    printf 'ERROR: compiled uConsole overlay not found.\n' >&2
    exit 1
fi

if [[ -z "$base_dtb" || ! -s "$base_dtb" ]]; then
    printf 'ERROR: compiled CM4 base DTB not found.\n' >&2
    exit 1
fi

printf 'Applying compiled overlay to compiled CM4 base DTB...\n'
fdtoverlay \
    -i "$base_dtb" \
    -o "$workdir/bcm2711-rpi-cm4-uconsole.dtb" \
    "$dtbo"

test -s "$workdir/bcm2711-rpi-cm4-uconsole.dtb"

printf 'Decompiling compiled overlay as final structural sanity check...\n'
dtc -I dtb -O dts "$dtbo" > "$workdir/overlay.compiled.dts"
grep -q 'cw,cwu50' "$workdir/overlay.compiled.dts"
grep -q 'ocp8178-backlight' "$workdir/overlay.compiled.dts"

printf 'PASS: cleaned uConsole CM4 overlay compiled and applied to the pinned CM4 base DTB.\n'

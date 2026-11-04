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
patch_file="$repo_root/kernel/patches/0004-power-axp20x-program-design-capacity.patch"
overlay="$repo_root/kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts"

printf 'Checking Stage 5 scope policy...\n'

grep -q 'charge-full-design-microamp-hours = <0>;' "$overlay"
grep -q 'energy-full-design-microwatt-hours = <0>;' "$overlay"
grep -q 'batt_uah = <&battery>,"charge-full-design-microamp-hours:0";' "$overlay"

if grep -qE 'drivers/mfd/axp20x.c|POWER_SUPPLY_PROP_(CALIBRATE|ENERGY_FULL|ENERGY_NOW|CHARGE_NOW)|AXP20X_(VBUS_IPSOUT_MGMT|OFF_CTRL|CHRG_CTRL2|PEK_KEY|GPIO0_CTRL)' "$patch_file"; then
    printf 'ERROR: Stage 5 patch contains unnecessary MFD or deferred policy behavior.\n' >&2
    exit 1
fi

grep -q 'AXP22X_FG_DES_CAP_LSB_UAH.*1456' "$patch_file"
grep -q 'AXP288_FG_DES_CAP1_REG' "$patch_file"
grep -q 'charge_full_design_uah > 0' "$patch_file"
grep -q '"x-powers,axp221-battery-power-supply"' "$patch_file"

hunk_count="$(grep -c '^@@ ' "$patch_file")"
if [[ "$hunk_count" -ne 1 ]]; then
    printf 'ERROR: Stage 5 patch must contain exactly one hunk; found %s.\n' "$hunk_count" >&2
    exit 1
fi

printf 'Fetching Raspberry Pi Linux %s (%s)...\n' \
    "$RPI_LINUX_VERSION" "$RPI_LINUX_COMMIT"
curl --fail --location --silent --show-error \
    "https://github.com/raspberrypi/linux/archive/${RPI_LINUX_COMMIT}.tar.gz" \
    --output "$linux_tar"

mkdir "$linux_src"
tar -xzf "$linux_tar" --strip-components=1 -C "$linux_src"

printf 'Checking minimal AXP20x patch against exact pinned source...\n'
if ! patch --directory="$linux_src" --strip=1 --forward --fuzz=0 --dry-run \
    < "$patch_file"; then
    printf 'ERROR: Stage 5 patch does not apply to the pinned source.\n' >&2
    printf 'Single Stage 5 anchor region:\n' >&2
    grep -n -A75 -B10 'MODULE_DEVICE_TABLE(of, axp20x_battery_ps_id)' \
        "$linux_src/drivers/power/supply/axp20x_battery.c" >&2 || true
    exit 1
fi

printf 'Applying minimal AXP20x patch...\n'
patch --directory="$linux_src" --strip=1 --forward --fuzz=0 \
    < "$patch_file"

printf 'Verifying patched source shape...\n'
grep -q '#define AXP22X_FG_DES_CAP_LSB_UAH.*1456' \
    "$linux_src/drivers/power/supply/axp20x_battery.c"
grep -q 'charge_full_design_uah > 0' \
    "$linux_src/drivers/power/supply/axp20x_battery.c"
grep -q 'regmap_bulk_write(axp20x_batt->regmap' \
    "$linux_src/drivers/power/supply/axp20x_battery.c"

printf 'Configuring BCM2711/CM4 kernel...\n'
make -C "$linux_src" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    bcm2711_defconfig

printf 'Compiling changed AXP20x battery object...\n'
make -C "$linux_src" -j"$jobs" \
    ARCH="$arch" CROSS_COMPILE="$cross_compile" \
    drivers/power/supply/axp20x_battery.o

test -s "$linux_src/drivers/power/supply/axp20x_battery.o"

printf 'PASS: minimal AXP221 design-capacity delta applied and compiled for ARM64.\n'

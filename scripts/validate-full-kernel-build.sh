#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$repo_root/kernel/source.lock"
source "$repo_root/kernel/sources/cwu50.lock"
source "$repo_root/kernel/sources/ocp8178.lock"

kernel_arch="${ARCH:-arm64}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
jobs="${JOBS:-$(nproc)}"

if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: JOBS must be a positive integer, got: %s\n' "$jobs" >&2
    exit 1
fi

printf 'Stage 8 build parallelism: -j%s\n' "$jobs"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

package_stage="$workdir/linux-uconsole-package"
srcdir="$workdir/src"
pkgdir="$workdir/pkg"

printf 'Checking Stage 8 repository policy...\n'

bash -n "$repo_root/scripts/stage-arch-kernel-package.sh"
bash -n "$repo_root/image/archlinuxarm/packages/linux-uconsole/PKGBUILD"

printf 'Staging Arch package workspace...\n'
bash "$repo_root/scripts/stage-arch-kernel-package.sh" "$package_stage"

printf 'Fetching exact Stage 8 source inputs...\n'
mkdir -p "$srcdir" "$pkgdir"

curl --fail --location --silent --show-error \
    "https://github.com/raspberrypi/linux/archive/${RPI_LINUX_COMMIT}.tar.gz" \
    --output "$workdir/linux.tar.gz"
tar -xzf "$workdir/linux.tar.gz" -C "$srcdir"

curl --fail --location --silent --show-error \
    "$CWU50_SOURCE_URL" \
    --output "$srcdir/panel-cwu50.c"

curl --fail --location --silent --show-error \
    "$OCP8178_SOURCE_URL" \
    --output "$srcdir/ocp8178_bl.c"

find "$package_stage" -maxdepth 1 -type f ! -name PKGBUILD ! -name README.md \
    -exec cp '{}' "$srcdir/" ';'

printf 'Running actual PKGBUILD prepare(), build() and package() paths...\n'
(
    cd "$package_stage"
    # shellcheck disable=SC1091
    source ./PKGBUILD

    export ARCH="$kernel_arch"
    export CROSS_COMPILE="$cross_compile"
    export MAKEFLAGS="-j${jobs}"
    export srcdir
    export pkgdir

    prepare
    build
    package
)

linux_src="$srcdir/linux-${RPI_LINUX_COMMIT}"
kernel_release="$(<"$linux_src/version")"
expected_release="${RPI_LINUX_VERSION}-1-uconsole"

if [[ "$kernel_release" != "$expected_release" ]]; then
    printf 'ERROR: unexpected kernel release: %s (expected %s)\n' \
        "$kernel_release" "$expected_release" >&2
    exit 1
fi

printf 'Verifying complete kernel build outputs...\n'

test -s "$linux_src/arch/arm64/boot/Image"

required_source_modules=(
    "drivers/gpu/drm/panel/panel-cwu50.ko"
    "drivers/video/backlight/ocp8178_bl.ko"
    "drivers/misc/uconsole-amp-switch.ko"
    "drivers/mfd/axp20x.ko"
    "drivers/mfd/axp20x-i2c.ko"
    "drivers/power/supply/axp20x_battery.ko"
    "drivers/power/supply/axp20x_ac_power.ko"
    "drivers/iio/adc/axp20x_adc.ko"
    "drivers/iio/adc/ti-adc081c.ko"
    "drivers/input/misc/axp20x-pek.ko"
    "drivers/regulator/axp20x-regulator.ko"
)

for module_path in "${required_source_modules[@]}"; do
    if [[ ! -s "$linux_src/$module_path" ]]; then
        printf 'ERROR: required built module missing: %s\n' "$module_path" >&2
        exit 1
    fi
done

uconsole_dtbo="$(
    find "$linux_src/arch" -type f \
        -name 'clockworkpi-uconsole-cm4.dtbo' -print -quit
)"
cm4_dtb="$(
    find "$linux_src/arch/arm64/boot/dts" -type f \
        -name 'bcm2711-rpi-cm4.dtb' -print -quit
)"

if [[ -z "$uconsole_dtbo" || ! -s "$uconsole_dtbo" ]]; then
    printf 'ERROR: built uConsole DTBO not found.\n' >&2
    exit 1
fi

if [[ -z "$cm4_dtb" || ! -s "$cm4_dtb" ]]; then
    printf 'ERROR: built CM4 base DTB not found.\n' >&2
    exit 1
fi

printf 'Applying built uConsole DTBO to built CM4 base DTB...\n'
fdtoverlay \
    -i "$cm4_dtb" \
    -o "$workdir/bcm2711-rpi-cm4-uconsole-merged.dtb" \
    "$uconsole_dtbo"

test -s "$workdir/bcm2711-rpi-cm4-uconsole-merged.dtb"

printf 'Verifying package root layout...\n'

test -s "$pkgdir/boot/kernel8.img"
cmp -s "$linux_src/arch/arm64/boot/Image" "$pkgdir/boot/kernel8.img"

package_dtbo="$(
    find "$pkgdir/boot" -type f \
        -name 'clockworkpi-uconsole-cm4.dtbo' -print -quit
)"
package_cm4_dtb="$(
    find "$pkgdir/boot" -type f \
        -name 'bcm2711-rpi-cm4.dtb' -print -quit
)"

if [[ -z "$package_dtbo" || ! -s "$package_dtbo" ]]; then
    printf 'ERROR: packaged uConsole DTBO not found under /boot.\n' >&2
    exit 1
fi

if [[ -z "$package_cm4_dtb" || ! -s "$package_cm4_dtb" ]]; then
    printf 'ERROR: packaged CM4 DTB not found under /boot.\n' >&2
    exit 1
fi

module_root="$pkgdir/usr/lib/modules/$expected_release"
test -d "$module_root"
test -s "$module_root/pkgbase"
grep -qx 'linux-uconsole' "$module_root/pkgbase"
test -e "$module_root/vmlinuz"

required_installed_modules=(
    panel-cwu50
    ocp8178_bl
    uconsole-amp-switch
    axp20x
    axp20x-i2c
    axp20x_battery
    axp20x_ac_power
    axp20x_adc
    ti-adc081c
    axp20x-pek
    axp20x-regulator
)

for module_name in "${required_installed_modules[@]}"; do
    installed="$(
        find "$module_root" -type f \
            -name "${module_name}.ko*" -print -quit
    )"
    if [[ -z "$installed" || ! -s "$installed" ]]; then
        printf 'ERROR: packaged module missing: %s.ko*.\n' "$module_name" >&2
        exit 1
    fi
done

preset="$pkgdir/etc/mkinitcpio.d/linux-uconsole.preset"
test -s "$preset"
grep -q "^ALL_kver=\"${expected_release}\"$" "$preset"
grep -q '^default_image="/boot/initramfs-linux-uconsole.img"$' "$preset"

printf 'Checking package tree for forbidden host/build leakage...\n'
if find "$pkgdir" -type l -print | grep -q .; then
    printf 'ERROR: packaged tree contains unexpected symlinks.\n' >&2
    find "$pkgdir" -type l -ls >&2
    exit 1
fi

printf 'PASS: Stage 8 full kernel build and package-root validation completed.\n'

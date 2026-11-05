#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$repo_root/kernel/source.lock"
source "$repo_root/kernel/sources/cwu50.lock"
source "$repo_root/kernel/sources/ocp8178.lock"

kernel_arch="${ARCH:-arm64}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

package_stage="$workdir/linux-uconsole-package"
srcdir="$workdir/src"

printf 'Checking Stage 7 repository policy...\n'

bash -n "$repo_root/scripts/stage-arch-kernel-package.sh"

grep -q '^CONFIG_DRM_PANEL_CWU50=m$' \
    "$repo_root/kernel/config/uconsole-cm4.config"
grep -q '^CONFIG_BACKLIGHT_OCP8178=m$' \
    "$repo_root/kernel/config/uconsole-cm4.config"
grep -q '^CONFIG_UCONSOLE_AMP_SWITCH=m$' \
    "$repo_root/kernel/config/uconsole-cm4.config"
grep -q '^CONFIG_SECURITY_LANDLOCK=y$' \
    "$repo_root/kernel/config/uconsole-cm4.config"

boot_config="$repo_root/image/archlinuxarm/boot/config-uconsole-cm4.txt"
grep -q '^arm_64bit=1$' "$boot_config"
grep -q '^otg_mode=1$' "$boot_config"
grep -q '^dtparam=audio=on$' "$boot_config"
grep -q '^dtoverlay=audremap,pins_12_13$' "$boot_config"
grep -q '^dtoverlay=clockworkpi-uconsole-cm4$' "$boot_config"
grep -q '^dtoverlay=vc4-kms-v3d-pi4,cma-384$' "$boot_config"
grep -q '^kernel=kernel8.img$' "$boot_config"

if grep -qE 'gpio=11=|sd_overclock|systemctl|systemd' "$boot_config"; then
    printf 'ERROR: deferred/obsolete boot policy leaked into Stage 7 config.\n' >&2
    exit 1
fi

printf 'Staging Arch package workspace...\n'
bash "$repo_root/scripts/stage-arch-kernel-package.sh" "$package_stage"

bash -n "$package_stage/PKGBUILD"

assert_pkgbuild() {
    local description="$1"
    local pattern="$2"

    if ! grep -qE "$pattern" "$package_stage/PKGBUILD"; then
        printf 'ERROR: PKGBUILD invariant failed: %s\n' "$description" >&2
        exit 1
    fi
}

assert_pkgbuild     'package base is linux-uconsole'     '^pkgbase=linux-uconsole$'
assert_pkgbuild     'package version matches pinned Raspberry Pi Linux version'     "^pkgver=${RPI_LINUX_VERSION}$"
assert_pkgbuild     'package commit matches kernel/source.lock'     "^_commit=${RPI_LINUX_COMMIT}$"
assert_pkgbuild     'bcm2711_defconfig is generated with Linux Kbuild ARCH=arm64'     'make[[:space:]]+ARCH=arm64[[:space:]]+bcm2711_defconfig'
assert_pkgbuild     'project config fragment is merged'     'merge_config\.sh[[:space:]]+-m[[:space:]]+\.config'
assert_pkgbuild     'olddefconfig is resolved with Linux Kbuild ARCH=arm64'     'make[[:space:]]+ARCH=arm64[[:space:]]+olddefconfig'
assert_pkgbuild     'kernelrelease is queried with Linux Kbuild ARCH=arm64'     'make[[:space:]]+-s[[:space:]]+ARCH=arm64[[:space:]]+kernelrelease'
assert_pkgbuild     'full build uses Linux Kbuild ARCH=arm64'     'make[[:space:]]+ARCH=arm64[[:space:]]+Image[[:space:]]+modules[[:space:]]+dtbs'
assert_pkgbuild     'module installation uses Linux Kbuild ARCH=arm64'     'make[[:space:]]+ARCH=arm64[[:space:]]+INSTALL_MOD_PATH='
assert_pkgbuild     'DTB installation uses Linux Kbuild ARCH=arm64'     'make[[:space:]]+ARCH=arm64[[:space:]]+INSTALL_DTBS_PATH='
assert_pkgbuild     'kernel image installs as /boot/kernel8.img'     'boot/kernel8\.img'

# Comments may legitimately explain that the package is init-system neutral.
# Enforce this policy only against executable/non-comment PKGBUILD content.
if sed -E '/^[[:space:]]*#/d' "$package_stage/PKGBUILD" |
    grep -qE 'systemctl|systemd|rc-service|openrc'; then
    printf 'ERROR: init-system policy leaked into shared kernel package.\n' >&2
    exit 1
fi

printf 'Fetching exact Stage 7 source inputs...\n'
mkdir -p "$srcdir"

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

printf 'Running the actual PKGBUILD prepare() composition path...\n'
(
    cd "$package_stage"
    # shellcheck disable=SC1091
    source ./PKGBUILD
    export ARCH="$kernel_arch"
    export CROSS_COMPILE="$cross_compile"
    export srcdir
    prepare
)

linux_src="$srcdir/linux-${RPI_LINUX_COMMIT}"

printf 'Verifying resolved kernel configuration...\n'
required_config=(
    CONFIG_DRM=y
    CONFIG_DRM_MIPI_DSI=y
    CONFIG_DRM_VC4=m
    CONFIG_DRM_PANEL_CWU50=m
    CONFIG_BACKLIGHT_OCP8178=m
    CONFIG_MFD_AXP20X_I2C=m
    CONFIG_AXP20X_ADC=m
    CONFIG_BATTERY_AXP20X=m
    CONFIG_CHARGER_AXP20X=m
    CONFIG_REGULATOR_AXP20X=m
    CONFIG_INPUT_AXP20X_PEK=m
    CONFIG_TI_ADC081C=m
    CONFIG_SPI_SPIDEV=m
    CONFIG_SND_BCM2835=m
    CONFIG_UCONSOLE_AMP_SWITCH=m
    CONFIG_SECURITY_LANDLOCK=y
)

for setting in "${required_config[@]}"; do
    if ! grep -qx "$setting" "$linux_src/.config"; then
        printf 'ERROR: required config did not resolve: %s\n' "$setting" >&2
        grep -E "^${setting%%=*}=|^# ${setting%%=*} is not set" \
            "$linux_src/.config" >&2 || true
        exit 1
    fi
done

kernel_release="$(<"$linux_src/version")"
case "$kernel_release" in
    "${RPI_LINUX_VERSION}-1-uconsole")
        ;;
    *)
        printf 'ERROR: unexpected kernel release: %s\n' "$kernel_release" >&2
        exit 1
        ;;
esac

printf 'Checking composed source tree identities...\n'
test -s "$linux_src/drivers/gpu/drm/panel/panel-cwu50.c"
test -s "$linux_src/drivers/video/backlight/ocp8178_bl.c"
test -s "$linux_src/drivers/misc/uconsole-amp-switch.c"
test -s "$linux_src/arch/arm/boot/dts/overlays/clockworkpi-uconsole-cm4-overlay.dts"

grep -q 'clockworkpi-uconsole-cm4.dtbo' \
    "$linux_src/arch/arm/boot/dts/overlays/Makefile"
grep -q 'CONFIG_UCONSOLE_AMP_SWITCH' "$linux_src/drivers/misc/Makefile"

printf 'Running kernel prepare without a full build...\n'
make -C "$linux_src" \
    ARCH="$kernel_arch" CROSS_COMPILE="$cross_compile" \
    prepare

printf 'PASS: Stage 7 composed source, config and Arch package metadata validated.\n'

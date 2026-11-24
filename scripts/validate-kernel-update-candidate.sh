#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

candidate_version="${1:-}"
candidate_commit="${2:-}"

if [[ -z "$candidate_version" || -z "$candidate_commit" ]]; then
    printf 'usage: %s VERSION COMMIT\n' "$0" >&2
    printf 'example: %s 6.18.64 a40f735325391b1705161b07f36ed45e1bf04521\n' "$0" >&2
    exit 2
fi

if [[ ! "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'ERROR: candidate kernel version must be numeric X.Y.Z: %s\n' \
        "$candidate_version" >&2
    exit 1
fi

if [[ ! "$candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'ERROR: candidate kernel commit must be a full 40-character lowercase SHA-1.\n' >&2
    exit 1
fi

# Host execution delegates to the project container launcher so Stage 12E does
# not depend on a cross toolchain installed on the developer workstation.
if [[ "${UCONSOLE_STAGE12E_CONTAINERIZED:-no}" != "yes" ]]; then
    exec bash "$repo_root/scripts/run-kernel-update-candidate.sh" \
        "$candidate_version" "$candidate_commit"
fi

# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"
# shellcheck disable=SC1091
source "$repo_root/kernel/sources/cwu50.lock"
# shellcheck disable=SC1091
source "$repo_root/kernel/sources/ocp8178.lock"

kernel_arch="${ARCH:-arm64}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
jobs="${JOBS:-$(nproc)}"

if [[ "$kernel_arch" != arm64 ]]; then
    printf 'ERROR: Stage 12E requires Linux Kbuild ARCH=arm64.\n' >&2
    exit 1
fi

for cmd in curl tar patch make grep sed awk sort git install find fdtoverlay dtc nproc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$cmd" >&2
        exit 1
    fi
done

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: JOBS must be a positive integer: %s\n' "$jobs" >&2
    exit 1
fi

if ! command -v "${cross_compile}gcc" >/dev/null 2>&1; then
    printf 'ERROR: required cross compiler not found: %sgcc\n' "$cross_compile" >&2
    exit 1
fi

if [[ "$candidate_version" == "$RPI_LINUX_VERSION" && \
      "$candidate_commit" == "$RPI_LINUX_COMMIT" ]]; then
    printf 'ERROR: candidate is identical to the currently pinned kernel.\n' >&2
    exit 1
fi

newest_version="$({ printf '%s\n' "$RPI_LINUX_VERSION"; printf '%s\n' "$candidate_version"; } | sort -V | tail -n 1)"
if [[ "$newest_version" != "$candidate_version" || \
      "$candidate_version" == "$RPI_LINUX_VERSION" ]]; then
    printf 'ERROR: candidate version %s is not newer than pinned version %s.\n' \
        "$candidate_version" "$RPI_LINUX_VERSION" >&2
    exit 1
fi

candidate_major_minor="${candidate_version%.*}"
pinned_major_minor="${RPI_LINUX_VERSION%.*}"
if [[ "$candidate_major_minor" != "$pinned_major_minor" ]]; then
    printf 'ERROR: Stage 12E is limited to the selected %s branch family; candidate is %s.\n' \
        "$pinned_major_minor" "$candidate_major_minor" >&2
    exit 1
fi

candidate_id="kernel-${candidate_version}-${candidate_commit:0:12}"
workdir="${UCONSOLE_UPDATE_CANDIDATE_DIR:-$repo_root/build/update-candidate/$candidate_id}"
package_stage="$workdir/linux-uconsole-package"
srcdir="$workdir/src"
report="$workdir/candidate-report.txt"

inside_git=no
git_status_before=''
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    inside_git=yes
    git_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
fi

err_report() {
    local status=$?
    local line="${BASH_LINENO[0]:-unknown}"
    printf 'ERROR: Stage 12E kernel candidate validation failed at line %s (exit %s).\n' \
        "$line" "$status" >&2
    printf 'Workspace retained at: %s\n' "$workdir" >&2
    exit "$status"
}
trap err_report ERR

printf 'Preparing isolated Stage 12E kernel candidate workspace...\n'
rm -rf "$workdir"
mkdir -p "$srcdir"

printf 'Staging canonical linux-uconsole package inputs...\n'
bash "$repo_root/scripts/stage-kernel-package.sh" "$package_stage"

printf 'Creating candidate-only PKGBUILD metadata...\n'
sed -i \
    -e "s/^pkgver=.*/pkgver=${candidate_version}/" \
    -e "s/^_commit=.*/_commit=${candidate_commit}/" \
    "$package_stage/PKGBUILD"

if ! grep -qx "pkgver=${candidate_version}" "$package_stage/PKGBUILD"; then
    printf 'ERROR: candidate PKGBUILD version substitution failed.\n' >&2
    exit 1
fi
if ! grep -qx "_commit=${candidate_commit}" "$package_stage/PKGBUILD"; then
    printf 'ERROR: candidate PKGBUILD commit substitution failed.\n' >&2
    exit 1
fi

printf 'Fetching exact Raspberry Pi Linux candidate %s (%s)...\n' \
    "$candidate_version" "$candidate_commit"
curl --fail --location --silent --show-error \
    "https://github.com/raspberrypi/linux/archive/${candidate_commit}.tar.gz" \
    --output "$workdir/linux.tar.gz"
tar -xzf "$workdir/linux.tar.gz" -C "$srcdir"

linux_src="$srcdir/linux-${candidate_commit}"
if [[ ! -f "$linux_src/Makefile" ]]; then
    printf 'ERROR: candidate archive did not contain expected source directory.\n' >&2
    exit 1
fi

upstream_major="$(awk '$1 == "VERSION" && $2 == "=" {print $3; exit}' "$linux_src/Makefile")"
upstream_minor="$(awk '$1 == "PATCHLEVEL" && $2 == "=" {print $3; exit}' "$linux_src/Makefile")"
upstream_sublevel="$(awk '$1 == "SUBLEVEL" && $2 == "=" {print $3; exit}' "$linux_src/Makefile")"
upstream_version="${upstream_major}.${upstream_minor}.${upstream_sublevel}"
if [[ "$upstream_version" != "$candidate_version" ]]; then
    printf 'ERROR: candidate version/commit mismatch: requested %s but commit reports %s.\n' \
        "$candidate_version" "$upstream_version" >&2
    exit 1
fi

printf 'Fetching immutable third-party driver inputs...\n'
curl --fail --location --silent --show-error \
    "$CWU50_SOURCE_URL" \
    --output "$srcdir/panel-cwu50.c"
curl --fail --location --silent --show-error \
    "$OCP8178_SOURCE_URL" \
    --output "$srcdir/ocp8178_bl.c"

find "$package_stage" -maxdepth 1 -type f \
    ! -name PKGBUILD ! -name README.md \
    -exec cp '{}' "$srcdir/" ';'

printf 'Running actual candidate PKGBUILD prepare() composition...\n'
(
    cd "$package_stage"
    # shellcheck disable=SC1091
    source ./PKGBUILD
    export ARCH="$kernel_arch"
    export CROSS_COMPILE="$cross_compile"
    export srcdir
    prepare
)

expected_release="${candidate_version}-1-uconsole"
actual_release="$(<"$linux_src/version")"
if [[ "$actual_release" != "$expected_release" ]]; then
    printf 'ERROR: candidate kernel release mismatch: expected %s, got %s.\n' \
        "$expected_release" "$actual_release" >&2
    exit 1
fi

printf 'Verifying candidate resolved kernel configuration...\n'
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
    'CONFIG_LSM="landlock"'
)

for setting in "${required_config[@]}"; do
    if ! grep -qx "$setting" "$linux_src/.config"; then
        printf 'ERROR: required candidate config did not resolve: %s\n' "$setting" >&2
        grep -E "^${setting%%=*}=|^# ${setting%%=*} is not set" \
            "$linux_src/.config" >&2 || true
        exit 1
    fi
done

printf 'Checking composed candidate source identities...\n'
test -s "$linux_src/drivers/gpu/drm/panel/panel-cwu50.c"
test -s "$linux_src/drivers/video/backlight/ocp8178_bl.c"
test -s "$linux_src/drivers/misc/uconsole-amp-switch.c"
test -s "$linux_src/arch/arm/boot/dts/overlays/clockworkpi-uconsole-cm4-overlay.dts"
grep -q 'clockworkpi-uconsole-cm4.dtbo' \
    "$linux_src/arch/arm/boot/dts/overlays/Makefile"
grep -q 'CONFIG_UCONSOLE_AMP_SWITCH' "$linux_src/drivers/misc/Makefile"

printf 'Running candidate kernel prepare...\n'
make -C "$linux_src" \
    ARCH="$kernel_arch" CROSS_COMPILE="$cross_compile" \
    prepare

printf 'Building candidate device trees only...\n'
make -C "$linux_src" -j"$jobs" \
    ARCH="$kernel_arch" CROSS_COMPILE="$cross_compile" \
    dtbs

uconsole_dtbo="$(find "$linux_src/arch" -type f \
    -name 'clockworkpi-uconsole-cm4.dtbo' -print -quit)"
cm4_dtb="$(find "$linux_src/arch/arm64/boot/dts" -type f \
    -name 'bcm2711-rpi-cm4.dtb' -print -quit)"

if [[ -z "$uconsole_dtbo" || ! -s "$uconsole_dtbo" ]]; then
    printf 'ERROR: candidate uConsole DTBO was not built.\n' >&2
    exit 1
fi
if [[ -z "$cm4_dtb" || ! -s "$cm4_dtb" ]]; then
    printf 'ERROR: candidate CM4 base DTB was not built.\n' >&2
    exit 1
fi

printf 'Applying candidate uConsole DTBO to candidate CM4 base DTB...\n'
fdtoverlay \
    -i "$cm4_dtb" \
    -o "$workdir/bcm2711-rpi-cm4-uconsole-merged.dtb" \
    "$uconsole_dtbo"
test -s "$workdir/bcm2711-rpi-cm4-uconsole-merged.dtb"

dtc -I dtb -O dts "$uconsole_dtbo" > "$workdir/uconsole-overlay.compiled.dts" 2>/dev/null
grep -q 'cw,cwu50' "$workdir/uconsole-overlay.compiled.dts"
grep -q 'ocp8178-backlight' "$workdir/uconsole-overlay.compiled.dts"

repository_mutated=no
if [[ "$inside_git" == yes ]]; then
    git_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
    if [[ "$git_status_after" != "$git_status_before" ]]; then
        repository_mutated=yes
        printf 'ERROR: Stage 12E changed tracked/unignored repository state.\n' >&2
        printf '%s\n' '--- git status before ---' >&2
        printf '%s\n' "$git_status_before" >&2
        printf '%s\n' '--- git status after ---' >&2
        printf '%s\n' "$git_status_after" >&2
        exit 1
    fi
fi

cat > "$report" <<REPORT
stage=12E
candidate_class=kernel-update
pinned_kernel_version=${RPI_LINUX_VERSION}
pinned_kernel_commit=${RPI_LINUX_COMMIT}
candidate_kernel_version=${candidate_version}
candidate_kernel_commit=${candidate_commit}
candidate_kernel_release=${actual_release}
patch_series=0001-0005
patch_fuzz=0
required_config_count=${#required_config[@]}
kernel_prepare=pass
device_tree_build=pass
dt_overlay_application=pass
dt_build_jobs=${jobs}
full_kernel_build=not_run
builder_image_id=${UCONSOLE_STAGE12E_BUILDER_IMAGE_ID:-unknown}
cross_gcc_version=${UCONSOLE_STAGE12E_CROSS_GCC_VERSION:-unknown}
cross_ld_version=${UCONSOLE_STAGE12E_CROSS_LD_VERSION:-unknown}
dtc_version=${UCONSOLE_STAGE12E_DTC_VERSION:-unknown}
project_pins_changed=no
repository_mutated=${repository_mutated}
REPORT

printf '\n=== STAGE 12E KERNEL UPDATE CANDIDATE ===\n'
cat "$report"
printf 'workspace=%s\n' "$workdir"
printf '=== END STAGE 12E KERNEL UPDATE CANDIDATE ===\n\n'
printf 'PASS: candidate composition/config/device-tree compatibility validated without changing project pins.\n'

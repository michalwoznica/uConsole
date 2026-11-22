#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Stage 12F candidate kernel installer must run as root in the disposable builder container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 6 ]]; then
    printf 'usage: %s ROOTFS CANDIDATE_PACKAGE BASELINE_BUNDLE VERSION COMMIT OUTPUT_INVENTORY\n' "$0" >&2
    exit 2
fi

rootfs="$1"
candidate_package="$2"
baseline_bundle="$3"
candidate_version="$4"
candidate_commit="$5"
output_inventory="$6"
candidate_pkgver="${candidate_version}-1"
candidate_release="${candidate_version}-1-uconsole"

# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/release-baseline.lock"

for cmd in awk bsdtar cmp depmod diff find grep pacman sort stat; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'ERROR: required command not found in Stage 12F container: %s\n' "$cmd" >&2
        exit 1
    fi
done

if [[ ! "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'ERROR: invalid candidate version: %s\n' "$candidate_version" >&2
    exit 1
fi
if [[ ! "$candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'ERROR: invalid candidate commit.\n' >&2
    exit 1
fi
if [[ ! -d "$rootfs" || ! -s "$candidate_package" ]]; then
    printf 'ERROR: Stage 12F rootfs or candidate package is missing.\n' >&2
    exit 1
fi
if [[ ! -s "$baseline_bundle/inventories/final-packages.txt" ]]; then
    printf 'ERROR: accepted baseline final inventory is missing.\n' >&2
    exit 1
fi
if [[ ! -s "$rootfs/etc/pacman.stage12-locked.conf" ]]; then
    printf 'ERROR: locked rootfs pacman configuration is missing.\n' >&2
    exit 1
fi

workdir="$(mktemp -d)"
target_ldconfig=""
target_ldconfig_mode=""
system_hooks="$rootfs/usr/share/libalpm/hooks"
system_hooks_saved="$rootfs/usr/share/libalpm/hooks.stage12f-saved"
custom_hooks="$rootfs/etc/pacman.d/hooks"
custom_hooks_saved="$rootfs/etc/pacman.d/hooks.stage12f-saved"

restore_ldconfig() {
    if [[ -n "$target_ldconfig" && -n "$target_ldconfig_mode" && -e "$target_ldconfig" ]]; then
        chmod "$target_ldconfig_mode" "$target_ldconfig" 2>/dev/null || true
        target_ldconfig_mode=""
    fi
}

restore_hooks() {
    if [[ -d "$system_hooks_saved" ]]; then
        rm -rf "$system_hooks"
        mv "$system_hooks_saved" "$system_hooks"
    fi
    if [[ -d "$custom_hooks_saved" ]]; then
        rm -rf "$custom_hooks"
        mv "$custom_hooks_saved" "$custom_hooks"
    fi
}

cleanup() {
    restore_ldconfig
    restore_hooks
    rm -rf "$workdir"
}
trap cleanup EXIT

pkginfo="$workdir/PKGINFO"
bsdtar -xOf "$candidate_package" .PKGINFO > "$pkginfo"
grep -Fxq 'pkgname = linux-uconsole' "$pkginfo"
grep -Fxq "pkgver = ${candidate_pkgver}" "$pkginfo"
grep -Fxq 'arch = aarch64' "$pkginfo"
grep -Fxq 'conflict = linux-aarch64' "$pkginfo"
grep -Fxq 'conflict = uboot-raspberrypi' "$pkginfo"

pacman_target() {
    pacman \
        --sysroot "$rootfs" \
        --config /etc/pacman.stage12-locked.conf \
        --arch aarch64 \
        --disable-sandbox-filesystem \
        "$@"
}

printf 'Verifying accepted baseline rootfs before candidate kernel replacement...\n'
pacman_target -Q linux-uconsole | grep -Fxq "linux-uconsole ${BASELINE_KERNEL_RELEASE%-uconsole}"
test -d "$rootfs/usr/lib/modules/$BASELINE_KERNEL_RELEASE"

if [[ -e "$system_hooks_saved" || -e "$custom_hooks_saved" ]]; then
    printf 'ERROR: unexpected Stage 12F hook-save path already exists.\n' >&2
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

target_ldconfig="$rootfs/usr/bin/ldconfig"
if [[ ! -x "$target_ldconfig" ]]; then
    printf 'ERROR: expected executable target ldconfig missing.\n' >&2
    exit 1
fi
target_ldconfig_mode="$(stat -Lc '%a' "$target_ldconfig")"
chmod a-x "$target_ldconfig"

printf 'Installing Stage 12F candidate kernel package offline...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --asexplicit \
    -U "$candidate_package"

restore_ldconfig
restore_hooks

# depmod-generated files from the accepted package are not owned by pacman and
# can otherwise leave a stale old-release directory after the package upgrade.
rm -rf "$rootfs/usr/lib/modules/$BASELINE_KERNEL_RELEASE"

printf 'Generating candidate kernel module dependency metadata...\n'
depmod -b "$rootfs" "$candidate_release"

printf 'Validating candidate kernel integration...\n'
pacman_target -Q linux-uconsole | grep -Fxq "linux-uconsole ${candidate_pkgver}"
test -s "$rootfs/boot/kernel8.img"
test -s "$rootfs/boot/bcm2711-rpi-cm4.dtb"
test -s "$rootfs/boot/overlays/clockworkpi-uconsole-cm4.dtbo"
test -d "$rootfs/usr/lib/modules/$candidate_release"
test -s "$rootfs/usr/lib/modules/$candidate_release/modules.dep"
test -s "$rootfs/usr/lib/modules/$candidate_release/modules.alias"
test -e "$rootfs/usr/lib/modules/$candidate_release/modules.devname"
if [[ -e "$rootfs/usr/lib/modules/$BASELINE_KERNEL_RELEASE" ]]; then
    printf 'ERROR: stale accepted-kernel module tree remains after candidate replacement.\n' >&2
    exit 1
fi

mkdir -p "$(dirname "$output_inventory")"
: > "$output_inventory"
while IFS= read -r -d '' desc; do
    awk '
        $0 == "%NAME%" { getline; name=$0 }
        $0 == "%VERSION%" { getline; version=$0 }
        END { if (name != "" && version != "") printf "%s\t%s\n", name, version }
    ' "$desc" >> "$output_inventory"
done < <(
    find "$rootfs/var/lib/pacman/local" \
        -mindepth 2 -maxdepth 2 -type f -name desc -print0
)
sort -u -o "$output_inventory" "$output_inventory"

baseline_no_kernel="$workdir/baseline-no-kernel.txt"
candidate_no_kernel="$workdir/candidate-no-kernel.txt"
awk -F '\t' '$1 != "linux-uconsole"' \
    "$baseline_bundle/inventories/final-packages.txt" > "$baseline_no_kernel"
awk -F '\t' '$1 != "linux-uconsole"' \
    "$output_inventory" > "$candidate_no_kernel"

if ! cmp -s "$baseline_no_kernel" "$candidate_no_kernel"; then
    printf 'ERROR: Stage 12F changed userspace package inventory outside linux-uconsole.\n' >&2
    diff -u "$baseline_no_kernel" "$candidate_no_kernel" >&2 || true
    exit 1
fi

if ! grep -Fqx $'linux-uconsole\t'"${candidate_pkgver}" "$output_inventory"; then
    printf 'ERROR: candidate final inventory does not contain expected linux-uconsole version.\n' >&2
    exit 1
fi

printf 'PASS: candidate kernel installed with accepted userspace inventory unchanged.\n'

#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Artix/OpenRC rootfs builder must run as root in the disposable build container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 4 ]]; then
    printf 'usage: %s OUTPUT_ROOTFS LINUX_UCONSOLE_PACKAGE RPI_FIRMWARE_PACKAGE RPI_BOOTLOADER_PACKAGE\n' "$0" >&2
    exit 2
fi

output_rootfs="$1"
kernel_package="$2"
firmware_package="$3"
bootloader_package="$4"

if [[ -z "$output_rootfs" || "$output_rootfs" == "/" ]]; then
    printf 'ERROR: refusing unsafe OUTPUT_ROOTFS: %q\n' "$output_rootfs" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/rootfs.lock"
# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/rpi-support.lock"

required_commands=(
    awk
    bsdtar
    curl
    depmod
    find
    modinfo
    pacman
    readlink
    sha256sum
    stat
)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing build-container commands: %s\n' "${missing[*]}" >&2
    exit 1
fi

for required_file in "$kernel_package" "$firmware_package" "$bootloader_package"; do
    if [[ ! -s "$required_file" ]]; then
        printf 'ERROR: required package payload is missing or empty: %s\n' "$required_file" >&2
        exit 1
    fi
done

pkgbuild="$repo_root/image/shared/packages/linux-uconsole/PKGBUILD"
kernel_pkgver="$(awk -F= '$1 == "pkgver" { gsub(/[[:space:]'"'"']/, "", $2); print $2; exit }' "$pkgbuild")"
kernel_pkgrel="$(awk -F= '$1 == "pkgrel" { gsub(/[[:space:]'"'"']/, "", $2); print $2; exit }' "$pkgbuild")"
if [[ -z "$kernel_pkgver" || -z "$kernel_pkgrel" ]]; then
    printf 'ERROR: could not determine linux-uconsole package version from %s\n' "$pkgbuild" >&2
    exit 1
fi
kernel_package_version="${kernel_pkgver}-${kernel_pkgrel}"
kernel_release="${kernel_package_version}-uconsole"

pkginfo_value() {
    local package_file="$1"
    local key="$2"
    bsdtar -xOf "$package_file" .PKGINFO |
        awk -F ' = ' -v key="$key" '$1 == key { print $2; exit }'
}

verify_package_identity() {
    local package_file="$1"
    local expected_name="$2"
    local expected_version="$3"
    local expected_arch="$4"
    local actual_name actual_version actual_arch

    actual_name="$(pkginfo_value "$package_file" pkgname)"
    actual_version="$(pkginfo_value "$package_file" pkgver)"
    actual_arch="$(pkginfo_value "$package_file" arch)"

    if [[ "$actual_name" != "$expected_name" ||
          "$actual_version" != "$expected_version" ||
          "$actual_arch" != "$expected_arch" ]]; then
        printf 'ERROR: package identity mismatch: %s\n' "$package_file" >&2
        printf 'expected: %s %s %s\n' \
            "$expected_name" "$expected_version" "$expected_arch" >&2
        printf 'got:      %s %s %s\n' \
            "$actual_name" "$actual_version" "$actual_arch" >&2
        exit 1
    fi
}

verify_package_identity \
    "$kernel_package" \
    linux-uconsole \
    "$kernel_package_version" \
    aarch64
verify_package_identity \
    "$firmware_package" \
    "$RPI_FIRMWARE_PKGNAME" \
    "$RPI_FIRMWARE_PKGVER" \
    any
verify_package_identity \
    "$bootloader_package" \
    "$RPI_BOOTLOADER_PKGNAME" \
    "$RPI_BOOTLOADER_PKGVER" \
    any

workdir="$(mktemp -d /tmp/uconsole-artix-rootfs.XXXXXX)"
chmod 0755 "$workdir"
archive_owned=0
archive="${ARMTIX_ROOTFS_ARCHIVE:-}"

target_ldconfig=""
target_ldconfig_mode=""
system_hooks=""
system_hooks_saved=""
system_hooks_updated=""
custom_hooks=""
custom_hooks_saved=""
custom_hooks_updated=""
hooks_prepared=0

restore_target_ldconfig() {
    if [[ -n "$target_ldconfig" && -n "$target_ldconfig_mode" && -e "$target_ldconfig" ]]; then
        chmod "$target_ldconfig_mode" "$target_ldconfig" 2>/dev/null || true
        target_ldconfig_mode=""
    fi
}

restore_hooks() {
    (( hooks_prepared )) || return 0

    if [[ -n "$system_hooks" ]]; then
        if [[ -d "$system_hooks" && ! -e "$system_hooks_updated" ]]; then
            mv "$system_hooks" "$system_hooks_updated"
        fi
        mkdir -p "$system_hooks"
        if [[ -d "$system_hooks_saved" ]]; then
            cp -an "$system_hooks_saved/." "$system_hooks/"
        fi
        if [[ -d "$system_hooks_updated" ]]; then
            cp -an "$system_hooks_updated/." "$system_hooks/"
        fi
        rm -rf "$system_hooks_saved" "$system_hooks_updated"
    fi

    if [[ -n "$custom_hooks" ]]; then
        if [[ -d "$custom_hooks" && ! -e "$custom_hooks_updated" ]]; then
            mv "$custom_hooks" "$custom_hooks_updated"
        fi
        mkdir -p "$custom_hooks"
        if [[ -d "$custom_hooks_saved" ]]; then
            cp -an "$custom_hooks_saved/." "$custom_hooks/"
        fi
        if [[ -d "$custom_hooks_updated" ]]; then
            cp -an "$custom_hooks_updated/." "$custom_hooks/"
        fi
        rm -rf "$custom_hooks_saved" "$custom_hooks_updated"
    fi

    hooks_prepared=0
}

cleanup() {
    restore_target_ldconfig
    restore_hooks
    chmod -R u+rwX "$workdir" 2>/dev/null || true
    rm -rf "$workdir"
}
trap cleanup EXIT HUP INT TERM

if [[ -z "$archive" ]]; then
    archive="$workdir/$ROOTFS_FILENAME"
    archive_owned=1
    printf 'Fetching pinned ARMtix/OpenRC rootfs...\n'
    curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 3 \
        --retry-delay 2 \
        "${ROOTFS_PRIMARY_BASE_URL}/${ROOTFS_FILENAME}" \
        --output "$archive"
else
    printf 'Using supplied ARMtix/OpenRC rootfs archive: %s\n' "$archive"
fi

if [[ ! -s "$archive" ]]; then
    printf 'ERROR: ARMtix/OpenRC rootfs archive is missing or empty: %s\n' "$archive" >&2
    exit 1
fi

actual_size="$(stat -Lc '%s' "$archive")"
if [[ "$actual_size" != "$ROOTFS_EXPECTED_SIZE" ]]; then
    printf 'ERROR: ARMtix/OpenRC rootfs size mismatch: got %s expected %s\n' \
        "$actual_size" "$ROOTFS_EXPECTED_SIZE" >&2
    exit 1
fi

actual_sha256="$(sha256sum "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$ROOTFS_SHA256" ]]; then
    printf 'ERROR: ARMtix/OpenRC rootfs SHA-256 mismatch: got %s expected %s\n' \
        "$actual_sha256" "$ROOTFS_SHA256" >&2
    exit 1
fi

printf 'Extracting pinned ARMtix/OpenRC rootfs...\n'
rm -rf "$output_rootfs"
mkdir -p "$output_rootfs"
bsdtar -xpf "$archive" -C "$output_rootfs"

if [[ "$(readlink "$output_rootfs/usr/bin/init")" != "openrc-init" ]]; then
    printf 'ERROR: extracted rootfs does not use the audited OpenRC init target.\n' >&2
    exit 1
fi

pacman_target() {
    pacman \
        --sysroot "$output_rootfs" \
        --arch aarch64 \
        --disable-sandbox-filesystem \
        "$@"
}

printf 'Checking audited ARMtix/OpenRC stock kernel state...\n'
for pkg in \
    linux-aarch64 \
    linux-aarch64-headers \
    linux-aarch64-lts \
    linux-aarch64-lts-headers
 do
    pacman_target -Q "$pkg" >/dev/null
 done

runlevel_hash_before="$(
    find "$output_rootfs/etc/runlevels" -type l -printf '%P -> %l\n' |
        sort |
        sha256sum |
        awk '{print $1}'
)"

printf 'Preparing foreign-architecture pacman transaction...\n'
system_hooks="$output_rootfs/usr/share/libalpm/hooks"
system_hooks_saved="$output_rootfs/usr/share/libalpm/hooks.uconsole-saved"
system_hooks_updated="$output_rootfs/usr/share/libalpm/hooks.uconsole-updated"
custom_hooks="$output_rootfs/etc/pacman.d/hooks"
custom_hooks_saved="$output_rootfs/etc/pacman.d/hooks.uconsole-saved"
custom_hooks_updated="$output_rootfs/etc/pacman.d/hooks.uconsole-updated"

for path in \
    "$system_hooks_saved" \
    "$system_hooks_updated" \
    "$custom_hooks_saved" \
    "$custom_hooks_updated"
 do
    if [[ -e "$path" ]]; then
        printf 'ERROR: unexpected hook-save path already exists: %s\n' "$path" >&2
        exit 1
    fi
 done

if [[ -d "$system_hooks" ]]; then
    mv "$system_hooks" "$system_hooks_saved"
fi
mkdir -p "$system_hooks"

if [[ -d "$custom_hooks" ]]; then
    mv "$custom_hooks" "$custom_hooks_saved"
fi
mkdir -p "$custom_hooks"
hooks_prepared=1

target_ldconfig="$output_rootfs/usr/bin/ldconfig"
if [[ ! -x "$target_ldconfig" ]]; then
    printf 'ERROR: expected executable target ldconfig missing.\n' >&2
    exit 1
fi
target_ldconfig_mode="$(stat -Lc '%a' "$target_ldconfig")"
chmod a-x "$target_ldconfig"

printf 'Removing generic ARMtix kernels and headers...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --nosave \
    -Rdd \
    linux-aarch64 \
    linux-aarch64-headers \
    linux-aarch64-lts \
    linux-aarch64-lts-headers

printf 'Installing Raspberry Pi support payloads and shared linux-uconsole package...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --asexplicit \
    -U \
    "$firmware_package" \
    "$bootloader_package" \
    "$kernel_package"

# Keep package-installed hooks, but do not execute target-architecture hooks in
# the x86_64 build container. The same restoration path is also used by the EXIT
# trap if the transaction fails after hooks have been suppressed.
restore_hooks
restore_target_ldconfig

printf 'Removing stale generated artifacts from the removed ARMtix kernels...\n'
rm -f \
    "$output_rootfs/boot/initramfs-linux.img" \
    "$output_rootfs/boot/initramfs-linux-fallback.img" \
    "$output_rootfs/boot/initramfs-linux-lts.img" \
    "$output_rootfs/boot/initramfs-linux-lts-fallback.img"

for stale_boot_path in \
    Image \
    Image.gz \
    ltsImage \
    ltsImage.gz \
    dtbs \
    dtbs-lts
 do
    if [[ -e "$output_rootfs/boot/$stale_boot_path" ]]; then
        printf 'ERROR: package-owned generic ARMtix boot artifact remains: /boot/%s\n' \
            "$stale_boot_path" >&2
        exit 1
    fi
 done

mapfile -t module_dirs < <(
    find "$output_rootfs/usr/lib/modules" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' |
        sort
)

for module_dir in "${module_dirs[@]}"; do
    [[ "$module_dir" == "$kernel_release" ]] && continue

    stale_tree="$output_rootfs/usr/lib/modules/$module_dir"
    if find "$stale_tree" -type f \
        \( -name '*.ko' -o -name '*.ko.gz' -o -name '*.ko.xz' -o -name '*.ko.zst' \) \
        -print -quit | grep -q .; then
        printf 'ERROR: stale ARMtix module tree still contains kernel modules: %s\n' \
            "$module_dir" >&2
        exit 1
    fi

    rm -rf -- "$stale_tree"
done

printf 'Generating uConsole module dependency metadata...\n'
depmod -b "$output_rootfs" "$kernel_release"

printf 'Installing shared uConsole rootfs/boot policy...\n'
install -Dm644 \
    "$repo_root/image/shared/boot/config-uconsole-cm4.txt" \
    "$output_rootfs/boot/config.txt"
install -Dm644 \
    "$repo_root/image/shared/rootfs/sysctl-uconsole.conf" \
    "$output_rootfs/etc/sysctl.d/50-uconsole-console.conf"
install -Dm755 \
    "$repo_root/image/shared/rootfs/uconsole-brightness-keys" \
    "$output_rootfs/usr/lib/uconsole/uconsole-brightness-keys"

printf 'Validating integrated Artix/OpenRC rootfs tree...\n'
pacman_target -Dk
pacman_target -Qk linux-uconsole
pacman_target -Q linux-uconsole |
    grep -Fxq "linux-uconsole ${kernel_package_version}"
pacman_target -Q "$RPI_FIRMWARE_PKGNAME" |
    grep -Fxq "${RPI_FIRMWARE_PKGNAME} ${RPI_FIRMWARE_PKGVER}"
pacman_target -Q "$RPI_BOOTLOADER_PKGNAME" |
    grep -Fxq "${RPI_BOOTLOADER_PKGNAME} ${RPI_BOOTLOADER_PKGVER}"

for pkg in \
    linux-aarch64 \
    linux-aarch64-headers \
    linux-aarch64-lts \
    linux-aarch64-lts-headers
 do
    if pacman_target -Q "$pkg" >/dev/null 2>&1; then
        printf 'ERROR: generic ARMtix package still installed: %s\n' "$pkg" >&2
        exit 1
    fi
 done

mapfile -t module_dirs < <(
    find "$output_rootfs/usr/lib/modules" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' |
        sort
)
if [[ "${#module_dirs[@]}" -ne 1 || "${module_dirs[0]}" != "$kernel_release" ]]; then
    printf 'ERROR: unexpected module trees remain:\n' >&2
    printf '  %s\n' "${module_dirs[@]}" >&2
    exit 1
fi

test -s "$output_rootfs/boot/kernel8.img"
test -s "$output_rootfs/boot/bcm2711-rpi-cm4.dtb"
test -s "$output_rootfs/boot/overlays/clockworkpi-uconsole-cm4.dtbo"
test -d "$output_rootfs/usr/lib/modules/$kernel_release"

module_dir="$output_rootfs/usr/lib/modules/$kernel_release"
for generated in \
    modules.dep \
    modules.dep.bin \
    modules.alias \
    modules.alias.bin \
    modules.symbols \
    modules.symbols.bin \
    modules.devname
 do
    test -e "$module_dir/$generated"
 done

panel_modinfo="$workdir/panel-cwu50.modinfo"
backlight_modinfo="$workdir/ocp8178-bl.modinfo"
modinfo -b "$output_rootfs" -k "$kernel_release" panel_cwu50 > "$panel_modinfo"
modinfo -b "$output_rootfs" -k "$kernel_release" ocp8178_bl > "$backlight_modinfo"
grep -Eq '^name:[[:space:]]+panel_cwu50$' "$panel_modinfo"
grep -Eq '^alias:[[:space:]]+of:N\*T\*Ccw,cwu50$' "$panel_modinfo"
grep -Eq '^name:[[:space:]]+ocp8178_bl$' "$backlight_modinfo"
grep -Eq '^alias:[[:space:]]+of:N\*T\*Cocp8178-backlight$' "$backlight_modinfo"

shopt -s nullglob
start_files=("$output_rootfs"/boot/start*.elf)
fixup_files=("$output_rootfs"/boot/fixup*.dat)
shopt -u nullglob
if (( ${#start_files[@]} == 0 || ${#fixup_files[@]} == 0 )); then
    printf 'ERROR: Raspberry Pi boot firmware is incomplete.\n' >&2
    exit 1
fi

cmp -s \
    "$repo_root/image/shared/boot/config-uconsole-cm4.txt" \
    "$output_rootfs/boot/config.txt"
cmp -s \
    "$repo_root/image/shared/rootfs/sysctl-uconsole.conf" \
    "$output_rootfs/etc/sysctl.d/50-uconsole-console.conf"
cmp -s \
    "$repo_root/image/shared/rootfs/uconsole-brightness-keys" \
    "$output_rootfs/usr/lib/uconsole/uconsole-brightness-keys"

runlevel_hash_after="$(
    find "$output_rootfs/etc/runlevels" -type l -printf '%P -> %l\n' |
        sort |
        sha256sum |
        awk '{print $1}'
)"
if [[ "$runlevel_hash_before" != "$runlevel_hash_after" ]]; then
    printf 'ERROR: OpenRC runlevel state changed during hardware/kernel integration.\n' >&2
    exit 1
fi

if [[ "$(readlink "$output_rootfs/usr/bin/init")" != "openrc-init" ]]; then
    printf 'ERROR: OpenRC init target changed during rootfs integration.\n' >&2
    exit 1
fi

if (( archive_owned )); then
    printf 'Pinned ARMtix rootfs was downloaded only into the disposable build workspace.\n'
fi

printf 'PASS: Artix/OpenRC kernel/hardware-integrated rootfs prepared.\n'

#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Artix/OpenRC Bluetooth configurator must run as root in the disposable build container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 2 ]]; then
    printf 'usage: %s ROOTFS BLUETOOTH_PACKAGE_DIR\n' "$0" >&2
    exit 2
fi

rootfs="$1"
package_dir="$2"

if [[ -z "$rootfs" || "$rootfs" == "/" || ! -d "$rootfs" ]]; then
    printf 'ERROR: refusing unsafe or missing ROOTFS: %q\n' "$rootfs" >&2
    exit 1
fi
if [[ ! -d "$package_dir" ]]; then
    printf 'ERROR: Bluetooth package directory does not exist: %s\n' "$package_dir" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/bluetooth.lock"

required_commands=(awk bsdtar cmp diff find grep pacman readlink sort stat)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing build-container commands: %s\n' "${missing[*]}" >&2
    exit 1
fi

if [[ "$(readlink "$rootfs/usr/bin/init")" != "openrc-init" ]]; then
    printf 'ERROR: target rootfs does not use the expected OpenRC init target.\n' >&2
    exit 1
fi

pacman_target() {
    pacman \
        --sysroot "$rootfs" \
        --arch aarch64 \
        --disable-sandbox-filesystem \
        "$@"
}

pacman_target -Q linux-uconsole >/dev/null
pacman_target -Q dbus >/dev/null
pacman_target -Q dbus-openrc >/dev/null

if [[ ! -L "$rootfs/etc/runlevels/default/dbus" ||
      "$(readlink "$rootfs/etc/runlevels/default/dbus")" != "/etc/init.d/dbus" ]]; then
    printf 'ERROR: dbus is not enabled as expected in the default runlevel.\n' >&2
    exit 1
fi
if [[ -e "$rootfs/etc/runlevels/default/$BLUETOOTH_SERVICE" ||
      -L "$rootfs/etc/runlevels/default/$BLUETOOTH_SERVICE" ]]; then
    printf 'ERROR: Bluetooth service is already enabled before this checkpoint.\n' >&2
    exit 1
fi

for package_name in \
    "$BLUEZ_PKGNAME" \
    "$BLUEZ_UTILS_PKGNAME" \
    "$BLUEZ_OPENRC_PKGNAME"
do
    if pacman_target -Q "$package_name" >/dev/null 2>&1; then
        printf 'ERROR: Bluetooth top-level package is already installed before this checkpoint: %s\n' \
            "$package_name" >&2
        exit 1
    fi
done

pkginfo_value() {
    local package_file="$1"
    local key="$2"
    bsdtar -xOf "$package_file" .PKGINFO |
        awk -F ' = ' -v key="$key" '$1 == key { print $2; exit }'
}

mapfile -d '' package_files < <(
    find "$package_dir" -maxdepth 1 -type f \
        -name '*.pkg.tar.*' ! -name '*.sig' -print0 | sort -z
)
if (( ${#package_files[@]} == 0 )); then
    printf 'ERROR: Bluetooth package directory contains no package payloads: %s\n' "$package_dir" >&2
    exit 1
fi

declare -A package_versions=()
declare -A package_arches=()
declare -A package_paths=()
for package_file in "${package_files[@]}"; do
    pkgname="$(pkginfo_value "$package_file" pkgname)"
    pkgver="$(pkginfo_value "$package_file" pkgver)"
    pkgarch="$(pkginfo_value "$package_file" arch)"

    if [[ -z "$pkgname" || -z "$pkgver" || -z "$pkgarch" ]]; then
        printf 'ERROR: could not read package identity: %s\n' "$package_file" >&2
        exit 1
    fi
    if [[ "$pkgarch" != "aarch64" && "$pkgarch" != "any" ]]; then
        printf 'ERROR: Bluetooth package has incompatible architecture: %s (%s)\n' \
            "$package_file" "$pkgarch" >&2
        exit 1
    fi
    if [[ -n "${package_paths[$pkgname]:-}" ]]; then
        printf 'ERROR: duplicate package name in Bluetooth package directory: %s\n' "$pkgname" >&2
        exit 1
    fi

    package_versions["$pkgname"]="$pkgver"
    package_arches["$pkgname"]="$pkgarch"
    package_paths["$pkgname"]="$package_file"
done

verify_locked_package() {
    local name="$1"
    local version="$2"
    local arch="$3"

    if [[ -z "${package_paths[$name]:-}" ]]; then
        printf 'ERROR: required Bluetooth package is missing: %s %s\n' "$name" "$version" >&2
        exit 1
    fi
    if [[ "${package_versions[$name]}" != "$version" || "${package_arches[$name]}" != "$arch" ]]; then
        printf 'ERROR: Bluetooth package identity mismatch for %s.\n' "$name" >&2
        printf 'expected: %s %s\n' "$version" "$arch" >&2
        printf 'got:      %s %s\n' "${package_versions[$name]}" "${package_arches[$name]}" >&2
        exit 1
    fi
}

verify_locked_package "$BLUEZ_PKGNAME" "$BLUEZ_PKGVER" "$BLUEZ_PKGARCH"
verify_locked_package "$BLUEZ_UTILS_PKGNAME" "$BLUEZ_UTILS_PKGVER" "$BLUEZ_UTILS_PKGARCH"
verify_locked_package "$BLUEZ_OPENRC_PKGNAME" "$BLUEZ_OPENRC_PKGVER" "$BLUEZ_OPENRC_PKGARCH"

workdir="$(mktemp -d /tmp/uconsole-artix-bluetooth.XXXXXX)"
system_hooks=""
system_hooks_saved=""
system_hooks_updated=""
custom_hooks=""
custom_hooks_saved=""
custom_hooks_updated=""
target_ldconfig=""
target_ldconfig_mode=""
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
    rm -rf "$workdir"
}
trap cleanup EXIT HUP INT TERM

find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$workdir/runlevels.before"

system_hooks="$rootfs/usr/share/libalpm/hooks"
system_hooks_saved="$rootfs/usr/share/libalpm/hooks.uconsole-bluetooth-saved"
system_hooks_updated="$rootfs/usr/share/libalpm/hooks.uconsole-bluetooth-updated"
custom_hooks="$rootfs/etc/pacman.d/hooks"
custom_hooks_saved="$rootfs/etc/pacman.d/hooks.uconsole-bluetooth-saved"
custom_hooks_updated="$rootfs/etc/pacman.d/hooks.uconsole-bluetooth-updated"

for path in \
    "$system_hooks_saved" "$system_hooks_updated" \
    "$custom_hooks_saved" "$custom_hooks_updated"
do
    if [[ -e "$path" ]]; then
        printf 'ERROR: unexpected Bluetooth hook-save path already exists: %s\n' "$path" >&2
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

target_ldconfig="$rootfs/usr/bin/ldconfig"
if [[ ! -x "$target_ldconfig" ]]; then
    printf 'ERROR: expected executable target ldconfig missing.\n' >&2
    exit 1
fi
target_ldconfig_mode="$(stat -Lc '%a' "$target_ldconfig")"
chmod a-x "$target_ldconfig"

printf 'Installing Artix/OpenRC Bluetooth package set...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --needed \
    --asdeps \
    -U \
    "${package_files[@]}"

pacman_target -D --asexplicit \
    "$BLUEZ_PKGNAME" \
    "$BLUEZ_UTILS_PKGNAME" \
    "$BLUEZ_OPENRC_PKGNAME"

restore_hooks
restore_target_ldconfig

printf 'Applying Artix/OpenRC Bluetooth service policy...\n'
test -x "$rootfs/usr/lib/bluetooth/bluetoothd"
test -x "$rootfs/usr/bin/bluetoothctl"
test -x "$rootfs/usr/bin/btmgmt"
test -x "$rootfs/etc/init.d/$BLUETOOTH_SERVICE"

ln -s "/etc/init.d/$BLUETOOTH_SERVICE" \
    "$rootfs/etc/runlevels/default/$BLUETOOTH_SERVICE"

printf 'Validating Artix/OpenRC Bluetooth integration...\n'
pacman_target -Dk
pacman_target -Q "$BLUEZ_PKGNAME" |
    grep -Fxq "$BLUEZ_PKGNAME $BLUEZ_PKGVER"
pacman_target -Q "$BLUEZ_UTILS_PKGNAME" |
    grep -Fxq "$BLUEZ_UTILS_PKGNAME $BLUEZ_UTILS_PKGVER"
pacman_target -Q "$BLUEZ_OPENRC_PKGNAME" |
    grep -Fxq "$BLUEZ_OPENRC_PKGNAME $BLUEZ_OPENRC_PKGVER"

if [[ ! -L "$rootfs/etc/runlevels/default/$BLUETOOTH_SERVICE" ||
      "$(readlink "$rootfs/etc/runlevels/default/$BLUETOOTH_SERVICE")" != "/etc/init.d/$BLUETOOTH_SERVICE" ]]; then
    printf 'ERROR: Bluetooth service is not enabled correctly in the default runlevel.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/default/dbus" ||
      "$(readlink "$rootfs/etc/runlevels/default/dbus")" != "/etc/init.d/dbus" ]]; then
    printf 'ERROR: dbus default-runlevel state changed unexpectedly.\n' >&2
    exit 1
fi

cp "$workdir/runlevels.before" "$workdir/runlevels.expected"
printf 'default/%s -> /etc/init.d/%s\n' \
    "$BLUETOOTH_SERVICE" "$BLUETOOTH_SERVICE" >> "$workdir/runlevels.expected"
sort -o "$workdir/runlevels.expected" "$workdir/runlevels.expected"
find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$workdir/runlevels.after"

if ! cmp -s "$workdir/runlevels.expected" "$workdir/runlevels.after"; then
    printf 'ERROR: OpenRC runlevel changes exceed the intended Bluetooth service enablement.\n' >&2
    diff -u "$workdir/runlevels.expected" "$workdir/runlevels.after" >&2 || true
    exit 1
fi

if [[ "$(readlink "$rootfs/usr/bin/init")" != "openrc-init" ]]; then
    printf 'ERROR: OpenRC init target changed during Bluetooth integration.\n' >&2
    exit 1
fi

printf 'PASS: Artix/OpenRC Bluetooth policy integrated.\n'

#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Artix/OpenRC networking configurator must run as root in the disposable build container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 2 ]]; then
    printf 'usage: %s ROOTFS NETWORK_PACKAGE_DIR\n' "$0" >&2
    exit 2
fi

rootfs="$1"
package_dir="$2"

if [[ -z "$rootfs" || "$rootfs" == "/" || ! -d "$rootfs" ]]; then
    printf 'ERROR: refusing unsafe or missing ROOTFS: %q\n' "$rootfs" >&2
    exit 1
fi
if [[ ! -d "$package_dir" ]]; then
    printf 'ERROR: networking package directory does not exist: %s\n' "$package_dir" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/networking.lock"

required_commands=(awk bsdtar cmp find grep install pacman readlink sha256sum sort stat)
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
pacman_target -Q dhcpcd >/dev/null
pacman_target -Q dhcpcd-openrc >/dev/null
pacman_target -Q wpa_supplicant >/dev/null
pacman_target -Q wpa_supplicant-openrc >/dev/null
pacman_target -Q dbus >/dev/null
pacman_target -Q dbus-openrc >/dev/null

if [[ ! -L "$rootfs/etc/runlevels/default/dhcpcd" ||
      "$(readlink "$rootfs/etc/runlevels/default/dhcpcd")" != "/etc/init.d/dhcpcd" ]]; then
    printf 'ERROR: pinned ARMtix baseline no longer has dhcpcd enabled in the default runlevel.\n' >&2
    exit 1
fi
if [[ -e "$rootfs/etc/runlevels/default/NetworkManager" ||
      -L "$rootfs/etc/runlevels/default/NetworkManager" ]]; then
    printf 'ERROR: NetworkManager is already enabled before this networking checkpoint.\n' >&2
    exit 1
fi
if [[ -e "$rootfs/etc/runlevels/default/wpa_supplicant" ||
      -L "$rootfs/etc/runlevels/default/wpa_supplicant" ]]; then
    printf 'ERROR: standalone wpa_supplicant is unexpectedly enabled in the default runlevel.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/default/dbus" ||
      "$(readlink "$rootfs/etc/runlevels/default/dbus")" != "/etc/init.d/dbus" ]]; then
    printf 'ERROR: dbus is not enabled as expected in the default runlevel.\n' >&2
    exit 1
fi
if [[ ! -f "$rootfs/etc/resolv.conf" || -L "$rootfs/etc/resolv.conf" ]]; then
    printf 'ERROR: expected the pinned ARMtix /etc/resolv.conf to be a regular file.\n' >&2
    exit 1
fi

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
    printf 'ERROR: networking package directory contains no package payloads: %s\n' "$package_dir" >&2
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
        printf 'ERROR: networking package has incompatible architecture: %s (%s)\n' \
            "$package_file" "$pkgarch" >&2
        exit 1
    fi
    if [[ -n "${package_paths[$pkgname]:-}" ]]; then
        printf 'ERROR: duplicate package name in networking package directory: %s\n' "$pkgname" >&2
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
        printf 'ERROR: required networking package is missing: %s %s\n' "$name" "$version" >&2
        exit 1
    fi
    if [[ "${package_versions[$name]}" != "$version" || "${package_arches[$name]}" != "$arch" ]]; then
        printf 'ERROR: networking package identity mismatch for %s.\n' "$name" >&2
        printf 'expected: %s %s\n' "$version" "$arch" >&2
        printf 'got:      %s %s\n' "${package_versions[$name]}" "${package_arches[$name]}" >&2
        exit 1
    fi
}

verify_locked_package \
    "$NETWORKMANAGER_PKGNAME" \
    "$NETWORKMANAGER_PKGVER" \
    "$NETWORKMANAGER_PKGARCH"
verify_locked_package \
    "$NETWORKMANAGER_OPENRC_PKGNAME" \
    "$NETWORKMANAGER_OPENRC_PKGVER" \
    "$NETWORKMANAGER_OPENRC_PKGARCH"

workdir="$(mktemp -d /tmp/uconsole-artix-networking.XXXXXX)"
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
system_hooks_saved="$rootfs/usr/share/libalpm/hooks.uconsole-networking-saved"
system_hooks_updated="$rootfs/usr/share/libalpm/hooks.uconsole-networking-updated"
custom_hooks="$rootfs/etc/pacman.d/hooks"
custom_hooks_saved="$rootfs/etc/pacman.d/hooks.uconsole-networking-saved"
custom_hooks_updated="$rootfs/etc/pacman.d/hooks.uconsole-networking-updated"

for path in \
    "$system_hooks_saved" "$system_hooks_updated" \
    "$custom_hooks_saved" "$custom_hooks_updated"
 do
    if [[ -e "$path" ]]; then
        printf 'ERROR: unexpected networking hook-save path already exists: %s\n' "$path" >&2
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

printf 'Installing Artix/OpenRC NetworkManager package set...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --needed \
    --asdeps \
    -U \
    "${package_files[@]}"

pacman_target -D --asexplicit \
    "$NETWORKMANAGER_PKGNAME" \
    "$NETWORKMANAGER_OPENRC_PKGNAME"

restore_hooks
restore_target_ldconfig

printf 'Applying Artix/OpenRC networking policy...\n'
test -x "$rootfs/usr/bin/NetworkManager"
test -x "$rootfs/usr/bin/nmcli"
test -x "$rootfs/usr/bin/nmtui"
test -x "$rootfs/etc/init.d/$NETWORKMANAGER_SERVICE"

rm -f "$rootfs/etc/runlevels/default/dhcpcd"
ln -s "/etc/init.d/$NETWORKMANAGER_SERVICE" \
    "$rootfs/etc/runlevels/default/$NETWORKMANAGER_SERVICE"

install -Dm644 \
    "$repo_root/image/artix-openrc/rootfs/NetworkManager-uconsole.conf" \
    "$rootfs/etc/NetworkManager/conf.d/10-uconsole-dns.conf"

printf 'Validating Artix/OpenRC networking integration...\n'
pacman_target -Dk
pacman_target -Q "$NETWORKMANAGER_PKGNAME" |
    grep -Fxq "$NETWORKMANAGER_PKGNAME $NETWORKMANAGER_PKGVER"
pacman_target -Q "$NETWORKMANAGER_OPENRC_PKGNAME" |
    grep -Fxq "$NETWORKMANAGER_OPENRC_PKGNAME $NETWORKMANAGER_OPENRC_PKGVER"

# We intentionally disable only the dhcpcd service. Keeping the upstream package
# avoids unrelated package churn and remains compatible with NetworkManager's
# optional external-DHCP-client support.
pacman_target -Q dhcpcd >/dev/null
pacman_target -Q dhcpcd-openrc >/dev/null
pacman_target -Q wpa_supplicant >/dev/null
pacman_target -Q wpa_supplicant-openrc >/dev/null

if [[ -e "$rootfs/etc/runlevels/default/dhcpcd" ||
      -L "$rootfs/etc/runlevels/default/dhcpcd" ]]; then
    printf 'ERROR: dhcpcd remains enabled in the default runlevel.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/default/$NETWORKMANAGER_SERVICE" ||
      "$(readlink "$rootfs/etc/runlevels/default/$NETWORKMANAGER_SERVICE")" != "/etc/init.d/$NETWORKMANAGER_SERVICE" ]]; then
    printf 'ERROR: NetworkManager is not enabled correctly in the default runlevel.\n' >&2
    exit 1
fi
if [[ -e "$rootfs/etc/runlevels/default/wpa_supplicant" ||
      -L "$rootfs/etc/runlevels/default/wpa_supplicant" ]]; then
    printf 'ERROR: standalone wpa_supplicant service became enabled unexpectedly.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/default/dbus" ||
      "$(readlink "$rootfs/etc/runlevels/default/dbus")" != "/etc/init.d/dbus" ]]; then
    printf 'ERROR: dbus default-runlevel state changed unexpectedly.\n' >&2
    exit 1
fi

cmp -s \
    "$repo_root/image/artix-openrc/rootfs/NetworkManager-uconsole.conf" \
    "$rootfs/etc/NetworkManager/conf.d/10-uconsole-dns.conf"
if [[ ! -f "$rootfs/etc/resolv.conf" || -L "$rootfs/etc/resolv.conf" ]]; then
    printf 'ERROR: /etc/resolv.conf is no longer a regular file for NetworkManager rc-manager=file.\n' >&2
    exit 1
fi

grep -Fvx 'default/dhcpcd -> /etc/init.d/dhcpcd' \
    "$workdir/runlevels.before" > "$workdir/runlevels.expected"
printf 'default/%s -> /etc/init.d/%s\n' \
    "$NETWORKMANAGER_SERVICE" "$NETWORKMANAGER_SERVICE" >> "$workdir/runlevels.expected"
sort -o "$workdir/runlevels.expected" "$workdir/runlevels.expected"
find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$workdir/runlevels.after"

if ! cmp -s "$workdir/runlevels.expected" "$workdir/runlevels.after"; then
    printf 'ERROR: OpenRC runlevel changes exceed the intended dhcpcd -> NetworkManager handoff.\n' >&2
    diff -u "$workdir/runlevels.expected" "$workdir/runlevels.after" >&2 || true
    exit 1
fi

if [[ "$(readlink "$rootfs/usr/bin/init")" != "openrc-init" ]]; then
    printf 'ERROR: OpenRC init target changed during networking integration.\n' >&2
    exit 1
fi

printf 'PASS: Artix/OpenRC NetworkManager networking policy integrated.\n'

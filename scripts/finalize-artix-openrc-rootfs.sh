#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Artix/OpenRC rootfs finalizer must run as root in the disposable build container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 1 ]]; then
    printf 'usage: %s ROOTFS\n' "$0" >&2
    exit 2
fi

rootfs="$1"
if [[ -z "$rootfs" || "$rootfs" == "/" || ! -d "$rootfs" ]]; then
    printf 'ERROR: refusing unsafe or missing ROOTFS: %q\n' "$rootfs" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/networking.lock"
# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/bluetooth.lock"
# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/runtime.lock"

required_commands=(cmp diff find grep install mktemp pacman readlink rm sort)
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

require_package_version() {
    local package_name="$1"
    local package_version="$2"
    pacman_target -Q "$package_name" |
        grep -Fxq "$package_name $package_version" || {
            printf 'ERROR: final Artix rootfs package identity mismatch: %s %s\n' \
                "$package_name" "$package_version" >&2
            exit 1
        }
}

require_link() {
    local path="$1"
    local target="$2"
    if [[ ! -L "$path" || "$(readlink "$path")" != "$target" ]]; then
        printf 'ERROR: required OpenRC runlevel link mismatch: %s -> %s\n' \
            "$path" "$target" >&2
        exit 1
    fi
}

require_absent_link() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
        printf 'ERROR: OpenRC service must remain disabled: %s\n' "$path" >&2
        exit 1
    fi
}

printf 'Checking completed Artix/OpenRC integration before final image identity...\n'
pacman_target -Dk
require_package_version "$NETWORKMANAGER_PKGNAME" "$NETWORKMANAGER_PKGVER"
require_package_version "$NETWORKMANAGER_OPENRC_PKGNAME" "$NETWORKMANAGER_OPENRC_PKGVER"
require_package_version "$BLUEZ_PKGNAME" "$BLUEZ_PKGVER"
require_package_version "$BLUEZ_UTILS_PKGNAME" "$BLUEZ_UTILS_PKGVER"
require_package_version "$BLUEZ_OPENRC_PKGNAME" "$BLUEZ_OPENRC_PKGVER"
require_package_version "$EVTEST_PKGNAME" "$EVTEST_PKGVER"
require_package_version "$CHRONY_PKGNAME" "$CHRONY_PKGVER"
require_package_version "$CHRONY_OPENRC_PKGNAME" "$CHRONY_OPENRC_PKGVER"

for package_name in elogind elogind-openrc dbus dbus-openrc linux-uconsole; do
    if ! pacman_target -Q "$package_name" >/dev/null 2>&1; then
        printf 'ERROR: required final Artix package is not installed: %s\n' \
            "$package_name" >&2
        exit 1
    fi
done

require_link \
    "$rootfs/etc/runlevels/default/$NETWORKMANAGER_SERVICE" \
    "/etc/init.d/$NETWORKMANAGER_SERVICE"
require_absent_link "$rootfs/etc/runlevels/default/dhcpcd"
require_absent_link "$rootfs/etc/runlevels/default/wpa_supplicant"
require_link \
    "$rootfs/etc/runlevels/default/$BLUETOOTH_SERVICE" \
    "/etc/init.d/$BLUETOOTH_SERVICE"
require_link "$rootfs/etc/runlevels/default/dbus" "/etc/init.d/dbus"
require_link "$rootfs/etc/runlevels/boot/elogind" "/etc/init.d/elogind"
require_link "$rootfs/etc/runlevels/boot/esysusers" "/etc/init.d/esysusers"
require_link "$rootfs/etc/runlevels/boot/etmpfiles-setup" "/etc/init.d/etmpfiles-setup"
require_absent_link "$rootfs/etc/runlevels/boot/hwclock"
require_link "$rootfs/etc/runlevels/boot/swclock" "/etc/init.d/swclock"
require_link \
    "$rootfs/etc/runlevels/default/$CHRONY_SERVICE" \
    "/etc/init.d/$CHRONY_SERVICE"
require_link \
    "$rootfs/etc/runlevels/default/$BRIGHTNESS_SERVICE" \
    "/etc/init.d/$BRIGHTNESS_SERVICE"

cmp -s \
    "$repo_root/image/artix-openrc/rootfs/NetworkManager-uconsole.conf" \
    "$rootfs/etc/NetworkManager/conf.d/10-uconsole-dns.conf"
cmp -s \
    "$repo_root/image/artix-openrc/rootfs/elogind-uconsole-power.conf" \
    "$rootfs/etc/elogind/logind.conf.d/99-uconsole-power.conf"
cmp -s \
    "$repo_root/image/shared/boot/config-uconsole-cm4.txt" \
    "$rootfs/boot/config.txt"
cmp -s \
    "$repo_root/image/shared/rootfs/sysctl-uconsole.conf" \
    "$rootfs/etc/sysctl.d/50-uconsole-console.conf"
cmp -s \
    "$repo_root/image/shared/rootfs/uconsole-brightness-keys" \
    "$rootfs/usr/lib/uconsole/uconsole-brightness-keys"
cmp -s \
    "$repo_root/image/artix-openrc/rootfs/uconsole-brightness-keys.initd" \
    "$rootfs/etc/init.d/$BRIGHTNESS_SERVICE"
cmp -s \
    "$repo_root/image/artix-openrc/rootfs/chrony-uconsole.conf" \
    "$rootfs/etc/chrony.conf"
grep -Fxq 'rc_need="!net"' "$rootfs/etc/conf.d/$CHRONY_SERVICE"
grep -Fxq 'FAST_STARTUP="yes"' "$rootfs/etc/conf.d/$CHRONY_SERVICE"
test -f "$rootfs/usr/lib/sysusers.d/chrony.conf"
test -f "$rootfs/usr/lib/tmpfiles.d/chrony.conf"
test -x "$rootfs/usr/bin/evtest"
test -x "$rootfs/usr/bin/chronyd"
test -x "$rootfs/etc/init.d/$CHRONY_SERVICE"

if [[ -L "$rootfs/etc/resolv.conf" || ! -f "$rootfs/etc/resolv.conf" ]]; then
    printf 'ERROR: final Artix resolv.conf must be a regular file for NetworkManager rc-manager=file.\n' >&2
    exit 1
fi

runlevel_before="$(mktemp)"
runlevel_after="$(mktemp)"
cleanup() {
    rm -f "$runlevel_before" "$runlevel_after"
}
trap cleanup EXIT HUP INT TERM

find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$runlevel_before"

printf 'Installing final Artix/OpenRC boot and filesystem identity...\n'
install -Dm0644 \
    "$repo_root/image/artix-openrc/boot/cmdline-uconsole-cm4.txt" \
    "$rootfs/boot/cmdline.txt"
install -Dm0644 \
    "$repo_root/image/artix-openrc/rootfs/fstab-uconsole-cm4" \
    "$rootfs/etc/fstab"

printf 'Validating finalized Artix/OpenRC rootfs...\n'
cmp -s \
    "$repo_root/image/artix-openrc/boot/cmdline-uconsole-cm4.txt" \
    "$rootfs/boot/cmdline.txt"
cmp -s \
    "$repo_root/image/artix-openrc/rootfs/fstab-uconsole-cm4" \
    "$rootfs/etc/fstab"
grep -Fxq 'HandlePowerKey=ignore' \
    "$rootfs/etc/elogind/logind.conf.d/99-uconsole-power.conf"
grep -Fxq 'dns=default' \
    "$rootfs/etc/NetworkManager/conf.d/10-uconsole-dns.conf"
grep -Fxq 'rc-manager=file' \
    "$rootfs/etc/NetworkManager/conf.d/10-uconsole-dns.conf"

find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$runlevel_after"
if ! cmp -s "$runlevel_before" "$runlevel_after"; then
    printf 'ERROR: OpenRC runlevel state changed during final image-identity installation.\n' >&2
    diff -u "$runlevel_before" "$runlevel_after" >&2 || true
    exit 1
fi

if find "$rootfs/etc/runlevels" -type l -printf '%l\n' |
    grep -Ev '^/etc/init\.d/' |
    grep -q .; then
    printf 'ERROR: non-OpenRC runlevel target found in finalized Artix rootfs.\n' >&2
    exit 1
fi

printf 'PASS: Artix/OpenRC rootfs finalized for deterministic image assembly.\n'

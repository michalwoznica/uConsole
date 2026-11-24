#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Artix/OpenRC elogind configurator must run as root in the disposable build container.\n' >&2
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

required_commands=(cmp diff find grep install pacman readlink sort)
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

for package_name in elogind elogind-openrc dbus dbus-openrc; do
    if ! pacman_target -Q "$package_name" >/dev/null 2>&1; then
        printf 'ERROR: required package is not installed in the pinned Artix rootfs: %s\n' \
            "$package_name" >&2
        exit 1
    fi
done

if [[ ! -x "$rootfs/etc/init.d/elogind" ]]; then
    printf 'ERROR: expected OpenRC elogind init script is missing or not executable.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/boot/elogind" ||
      "$(readlink "$rootfs/etc/runlevels/boot/elogind")" != "/etc/init.d/elogind" ]]; then
    printf 'ERROR: elogind is not enabled through /etc/init.d/elogind in the boot runlevel.\n' >&2
    exit 1
fi
if [[ ! -x "$rootfs/etc/init.d/dbus" ]]; then
    printf 'ERROR: expected OpenRC dbus init script is missing or not executable.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/default/dbus" ||
      "$(readlink "$rootfs/etc/runlevels/default/dbus")" != "/etc/init.d/dbus" ]]; then
    printf 'ERROR: dbus is not enabled through /etc/init.d/dbus in the default runlevel.\n' >&2
    exit 1
fi

source_policy="$repo_root/image/artix-openrc/rootfs/elogind-uconsole-power.conf"
target_policy="$rootfs/etc/elogind/logind.conf.d/99-uconsole-power.conf"

if [[ ! -f "$source_policy" ]]; then
    printf 'ERROR: repository elogind power policy is missing: %s\n' "$source_policy" >&2
    exit 1
fi
if [[ -e "$target_policy" || -L "$target_policy" ]]; then
    printf 'ERROR: uConsole elogind power policy already exists before this checkpoint: %s\n' \
        "$target_policy" >&2
    exit 1
fi

workdir="$(mktemp -d /tmp/uconsole-artix-elogind.XXXXXX)"
cleanup() {
    rm -rf "$workdir"
}
trap cleanup EXIT HUP INT TERM

find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$workdir/runlevels.before"

printf 'Applying Artix/OpenRC elogind power-button policy...\n'
install -Dm0644 "$source_policy" "$target_policy"

printf 'Validating Artix/OpenRC elogind integration...\n'
pacman_target -Dk
cmp -s "$source_policy" "$target_policy"
grep -Fxq '[Login]' "$target_policy"
grep -Fxq 'HandlePowerKey=ignore' "$target_policy"

if [[ ! -L "$rootfs/etc/runlevels/boot/elogind" ||
      "$(readlink "$rootfs/etc/runlevels/boot/elogind")" != "/etc/init.d/elogind" ]]; then
    printf 'ERROR: elogind OpenRC boot-runlevel state changed unexpectedly.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/default/dbus" ||
      "$(readlink "$rootfs/etc/runlevels/default/dbus")" != "/etc/init.d/dbus" ]]; then
    printf 'ERROR: dbus OpenRC default-runlevel state changed unexpectedly.\n' >&2
    exit 1
fi

find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$workdir/runlevels.after"
if ! cmp -s "$workdir/runlevels.before" "$workdir/runlevels.after"; then
    printf 'ERROR: OpenRC runlevel state changed during elogind policy integration.\n' >&2
    diff -u "$workdir/runlevels.before" "$workdir/runlevels.after" >&2 || true
    exit 1
fi

if [[ "$(readlink "$rootfs/usr/bin/init")" != "openrc-init" ]]; then
    printf 'ERROR: OpenRC init target changed during elogind policy integration.\n' >&2
    exit 1
fi

printf 'PASS: Artix/OpenRC elogind power-button policy integrated.\n'

#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Artix/OpenRC runtime configurator must run as root in the disposable build container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 2 ]]; then
    printf 'usage: %s ROOTFS RUNTIME_PACKAGE_DIR\n' "$0" >&2
    exit 2
fi

rootfs="$1"
package_dir="$2"

if [[ -z "$rootfs" || "$rootfs" == "/" || ! -d "$rootfs" ]]; then
    printf 'ERROR: refusing unsafe or missing ROOTFS: %q\n' "$rootfs" >&2
    exit 1
fi
if [[ ! -d "$package_dir" ]]; then
    printf 'ERROR: runtime package directory does not exist: %s\n' "$package_dir" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$repo_root/image/artix-openrc/runtime.lock"

required_commands=(awk bsdtar cat chmod cmp cp diff find grep install ln mkdir mktemp mv pacman readlink rm sort stat tail)
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

# This layer is intentionally applied after networking, Bluetooth and elogind.
for package_name in linux-uconsole networkmanager networkmanager-openrc bluez bluez-utils bluez-openrc elogind elogind-openrc; do
    if ! pacman_target -Q "$package_name" >/dev/null 2>&1; then
        printf 'ERROR: required earlier Artix integration package is missing: %s\n' "$package_name" >&2
        exit 1
    fi
done

# The pinned ARMtix image ships its stock NTP implementation. Chrony is the
# selected uConsole time-sync implementation, so require the known source state
# before replacing it rather than forcing pacman through an init-timed conflict.
for package_name in "$REPLACED_NTP_PKGNAME" "$REPLACED_NTP_OPENRC_PKGNAME"; do
    if ! pacman_target -Q "$package_name" >/dev/null 2>&1; then
        printf 'ERROR: pinned ARMtix stock time-sync package is missing before replacement: %s\n' \
            "$package_name" >&2
        exit 1
    fi
done

require_link() {
    local path="$1"
    local target="$2"
    if [[ ! -L "$path" || "$(readlink "$path")" != "$target" ]]; then
        printf 'ERROR: required OpenRC runlevel link mismatch: %s -> %s\n' "$path" "$target" >&2
        exit 1
    fi
}

require_absent_link() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
        printf 'ERROR: OpenRC service is unexpectedly enabled before runtime integration: %s\n' "$path" >&2
        exit 1
    fi
}

require_link "$rootfs/etc/runlevels/default/NetworkManager" "/etc/init.d/NetworkManager"
require_link "$rootfs/etc/runlevels/default/bluetoothd" "/etc/init.d/bluetoothd"
require_link "$rootfs/etc/runlevels/default/dbus" "/etc/init.d/dbus"
require_link "$rootfs/etc/runlevels/boot/elogind" "/etc/init.d/elogind"
require_link "$rootfs/etc/runlevels/boot/hwclock" "/etc/init.d/hwclock"
require_absent_link "$rootfs/etc/runlevels/boot/swclock"
require_absent_link "$rootfs/etc/runlevels/default/$CHRONY_SERVICE"
require_absent_link "$rootfs/etc/runlevels/default/$BRIGHTNESS_SERVICE"

if [[ ! -x "$rootfs/etc/init.d/swclock" ]]; then
    printf 'ERROR: pinned ARMtix rootfs does not provide executable /etc/init.d/swclock.\n' >&2
    exit 1
fi
if [[ ! -x "$rootfs/usr/lib/uconsole/uconsole-brightness-keys" ]]; then
    printf 'ERROR: shared uConsole brightness-key handler is missing from target rootfs.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/boot/esysusers" ||
      "$(readlink "$rootfs/etc/runlevels/boot/esysusers")" != "/etc/init.d/esysusers" ]]; then
    printf 'ERROR: pinned ARMtix rootfs does not enable esysusers in the boot runlevel.\n' >&2
    exit 1
fi
if [[ ! -L "$rootfs/etc/runlevels/boot/etmpfiles-setup" ||
      "$(readlink "$rootfs/etc/runlevels/boot/etmpfiles-setup")" != "/etc/init.d/etmpfiles-setup" ]]; then
    printf 'ERROR: pinned ARMtix rootfs does not enable etmpfiles-setup in the boot runlevel.\n' >&2
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
    printf 'ERROR: runtime package directory contains no package payloads: %s\n' "$package_dir" >&2
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
        printf 'ERROR: runtime package has incompatible architecture: %s (%s)\n' \
            "$package_file" "$pkgarch" >&2
        exit 1
    fi
    if [[ -n "${package_paths[$pkgname]:-}" ]]; then
        printf 'ERROR: duplicate package name in runtime package directory: %s\n' "$pkgname" >&2
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
        printf 'ERROR: required runtime package is missing: %s %s\n' "$name" "$version" >&2
        exit 1
    fi
    if [[ "${package_versions[$name]}" != "$version" || "${package_arches[$name]}" != "$arch" ]]; then
        printf 'ERROR: runtime package identity mismatch for %s.\n' "$name" >&2
        printf 'expected: %s %s\n' "$version" "$arch" >&2
        printf 'got:      %s %s\n' "${package_versions[$name]}" "${package_arches[$name]}" >&2
        exit 1
    fi
}

verify_locked_package "$EVTEST_PKGNAME" "$EVTEST_PKGVER" "$EVTEST_PKGARCH"
verify_locked_package "$CHRONY_PKGNAME" "$CHRONY_PKGVER" "$CHRONY_PKGARCH"
verify_locked_package "$CHRONY_OPENRC_PKGNAME" "$CHRONY_OPENRC_PKGVER" "$CHRONY_OPENRC_PKGARCH"

# The pinned ARMtix rootfs has been inspected directly. Its stock OpenRC NTP
# layer consists of exactly these service/configuration names, and none of the
# services is enabled in any runlevel. Assert that known source state before
# replacing the stock ntp + ntp-openrc packages with chrony.
read -r -a stock_ntp_services <<< "$REPLACED_NTP_SERVICE_NAMES"
for service_name in "${stock_ntp_services[@]}"; do
    if [[ ! -f "$rootfs/etc/init.d/$service_name" ]]; then
        printf 'ERROR: pinned ARMtix stock NTP init script is missing: /etc/init.d/%s\n' \
            "$service_name" >&2
        exit 1
    fi
    if [[ ! -f "$rootfs/etc/conf.d/$service_name" ]]; then
        printf 'ERROR: pinned ARMtix stock NTP config is missing: /etc/conf.d/%s\n' \
            "$service_name" >&2
        exit 1
    fi
    if find "$rootfs/etc/runlevels" -type l \
        -lname "/etc/init.d/$service_name" -print -quit | grep -q .; then
        printf 'ERROR: pinned ARMtix stock NTP service is unexpectedly enabled: %s\n' \
            "$service_name" >&2
        exit 1
    fi
done

workdir="$(mktemp -d /tmp/uconsole-artix-runtime.XXXXXX)"
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
system_hooks_saved="$rootfs/usr/share/libalpm/hooks.uconsole-runtime-saved"
system_hooks_updated="$rootfs/usr/share/libalpm/hooks.uconsole-runtime-updated"
custom_hooks="$rootfs/etc/pacman.d/hooks"
custom_hooks_saved="$rootfs/etc/pacman.d/hooks.uconsole-runtime-saved"
custom_hooks_updated="$rootfs/etc/pacman.d/hooks.uconsole-runtime-updated"

for path in \
    "$system_hooks_saved" "$system_hooks_updated" \
    "$custom_hooks_saved" "$custom_hooks_updated"
do
    if [[ -e "$path" ]]; then
        printf 'ERROR: unexpected runtime hook-save path already exists: %s\n' "$path" >&2
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

printf 'Replacing stock ARMtix NTP implementation with chrony...\n'
# Removing the old init-timed provider and installing the new provider are two
# offline transactions, so ignore dependencies only for this temporary gap. The
# completed runtime integration re-validates the target package database.
pacman_target \
    --noconfirm \
    --noscriptlet \
    --nosave \
    -Rdd \
    "$REPLACED_NTP_OPENRC_PKGNAME" \
    "$REPLACED_NTP_PKGNAME"

printf 'Installing Artix/OpenRC runtime package set...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --needed \
    --asdeps \
    -U \
    "${package_files[@]}"

pacman_target -D --asexplicit \
    "$EVTEST_PKGNAME" \
    "$CHRONY_PKGNAME" \
    "$CHRONY_OPENRC_PKGNAME"

restore_hooks
restore_target_ldconfig

printf 'Applying Artix/OpenRC brightness and RTC-less clock policy...\n'
test -x "$rootfs/usr/bin/evtest"
test -x "$rootfs/usr/bin/chronyd"
test -x "$rootfs/etc/init.d/$CHRONY_SERVICE"

install -Dm0755 \
    "$repo_root/image/artix-openrc/rootfs/uconsole-brightness-keys.initd" \
    "$rootfs/etc/init.d/$BRIGHTNESS_SERVICE"
install -Dm0644 \
    "$repo_root/image/artix-openrc/rootfs/chrony-uconsole.conf" \
    "$rootfs/etc/chrony.conf"

chrony_openrc_conf="$rootfs/etc/conf.d/$CHRONY_SERVICE"
if [[ ! -f "$chrony_openrc_conf" ]]; then
    printf 'ERROR: chrony-openrc did not provide /etc/conf.d/%s.\n' "$CHRONY_SERVICE" >&2
    exit 1
fi

# chrony-openrc already ships defaults such as FAST_STARTUP=yes.  Normalize
# the two uConsole-owned assignments rather than appending duplicate shell
# variables whose effective value would depend on file order.
awk '
    !/^[[:space:]]*rc_need[[:space:]]*=/ &&
    !/^[[:space:]]*FAST_STARTUP[[:space:]]*=/
' "$chrony_openrc_conf" > "$workdir/chrony-openrc.conf"
cat "$workdir/chrony-openrc.conf" > "$chrony_openrc_conf"
printf '\n' >> "$chrony_openrc_conf"
cat "$repo_root/image/artix-openrc/rootfs/chrony-uconsole-openrc.conf" >> \
    "$chrony_openrc_conf"

rm -f "$rootfs/etc/runlevels/boot/hwclock"
ln -s /etc/init.d/swclock "$rootfs/etc/runlevels/boot/swclock"
ln -s "/etc/init.d/$CHRONY_SERVICE" "$rootfs/etc/runlevels/default/$CHRONY_SERVICE"
ln -s "/etc/init.d/$BRIGHTNESS_SERVICE" "$rootfs/etc/runlevels/default/$BRIGHTNESS_SERVICE"

printf 'Validating Artix/OpenRC runtime integration...\n'
pacman_target -Dk
pacman_target -Q "$EVTEST_PKGNAME" |
    grep -Fxq "$EVTEST_PKGNAME $EVTEST_PKGVER"
pacman_target -Q "$CHRONY_PKGNAME" |
    grep -Fxq "$CHRONY_PKGNAME $CHRONY_PKGVER"
pacman_target -Q "$CHRONY_OPENRC_PKGNAME" |
    grep -Fxq "$CHRONY_OPENRC_PKGNAME $CHRONY_OPENRC_PKGVER"

for package_name in "$REPLACED_NTP_PKGNAME" "$REPLACED_NTP_OPENRC_PKGNAME"; do
    if pacman_target -Q "$package_name" >/dev/null 2>&1; then
        printf 'ERROR: replaced ARMtix time-sync package remains installed: %s\n' \
            "$package_name" >&2
        exit 1
    fi
done
for service_name in "${stock_ntp_services[@]}"; do
    if [[ -e "$rootfs/etc/init.d/$service_name" || -L "$rootfs/etc/init.d/$service_name" ]]; then
        printf 'ERROR: replaced ARMtix time-sync init script remains: /etc/init.d/%s\n' \
            "$service_name" >&2
        exit 1
    fi
    if [[ -e "$rootfs/etc/conf.d/$service_name" || -L "$rootfs/etc/conf.d/$service_name" ]]; then
        printf 'ERROR: replaced ARMtix time-sync config remains: /etc/conf.d/%s\n' \
            "$service_name" >&2
        exit 1
    fi
done

cmp -s \
    "$repo_root/image/artix-openrc/rootfs/uconsole-brightness-keys.initd" \
    "$rootfs/etc/init.d/$BRIGHTNESS_SERVICE"
cmp -s \
    "$repo_root/image/artix-openrc/rootfs/chrony-uconsole.conf" \
    "$rootfs/etc/chrony.conf"
grep -Fxq 'rc_need="!net"' "$chrony_openrc_conf"
grep -Fxq 'FAST_STARTUP="yes"' "$chrony_openrc_conf"
if [[ "$(awk '/^[[:space:]]*rc_need[[:space:]]*=/{n++} END{print n+0}' "$chrony_openrc_conf")" -ne 1 ||
      "$(awk '/^[[:space:]]*FAST_STARTUP[[:space:]]*=/{n++} END{print n+0}' "$chrony_openrc_conf")" -ne 1 ]]; then
    printf 'ERROR: uConsole chrony OpenRC service overrides are not uniquely installed.\n' >&2
    exit 1
fi
if [[ ! -f "$rootfs/usr/lib/sysusers.d/chrony.conf" ||
      ! -f "$rootfs/usr/lib/tmpfiles.d/chrony.conf" ]]; then
    printf 'ERROR: chrony package is missing sysusers/tmpfiles integration required before chronyd starts.\n' >&2
    exit 1
fi

if [[ -e "$rootfs/etc/runlevels/boot/hwclock" || -L "$rootfs/etc/runlevels/boot/hwclock" ]]; then
    printf 'ERROR: hwclock remains enabled despite the physically validated absence of an RTC.\n' >&2
    exit 1
fi
require_link "$rootfs/etc/runlevels/boot/swclock" "/etc/init.d/swclock"
require_link "$rootfs/etc/runlevels/default/$CHRONY_SERVICE" "/etc/init.d/$CHRONY_SERVICE"
require_link "$rootfs/etc/runlevels/default/$BRIGHTNESS_SERVICE" "/etc/init.d/$BRIGHTNESS_SERVICE"

# The earlier service integrations must remain intact.
require_link "$rootfs/etc/runlevels/default/NetworkManager" "/etc/init.d/NetworkManager"
require_link "$rootfs/etc/runlevels/default/bluetoothd" "/etc/init.d/bluetoothd"
require_link "$rootfs/etc/runlevels/default/dbus" "/etc/init.d/dbus"
require_link "$rootfs/etc/runlevels/boot/elogind" "/etc/init.d/elogind"
require_link "$rootfs/etc/runlevels/boot/esysusers" "/etc/init.d/esysusers"
require_link "$rootfs/etc/runlevels/boot/etmpfiles-setup" "/etc/init.d/etmpfiles-setup"

# Prove the runlevel delta is exactly the intended runtime policy. The pinned
# source has no NTP service enabled, so the only removals/additions are hwclock
# -> swclock plus chrony and the brightness-key service.
grep -Fvx 'boot/hwclock -> /etc/init.d/hwclock' \
    "$workdir/runlevels.before" > "$workdir/runlevels.expected" || true
printf 'boot/swclock -> /etc/init.d/swclock\n' >> "$workdir/runlevels.expected"
printf 'default/%s -> /etc/init.d/%s\n' \
    "$CHRONY_SERVICE" "$CHRONY_SERVICE" >> "$workdir/runlevels.expected"
printf 'default/%s -> /etc/init.d/%s\n' \
    "$BRIGHTNESS_SERVICE" "$BRIGHTNESS_SERVICE" >> "$workdir/runlevels.expected"
sort -o "$workdir/runlevels.expected" "$workdir/runlevels.expected"
find "$rootfs/etc/runlevels" -type l -printf '%P -> %l\n' | sort > "$workdir/runlevels.after"

if ! cmp -s "$workdir/runlevels.expected" "$workdir/runlevels.after"; then
    printf 'ERROR: OpenRC runlevel changes exceed the intended runtime-service policy.\n' >&2
    diff -u "$workdir/runlevels.expected" "$workdir/runlevels.after" >&2 || true
    exit 1
fi

if find "$rootfs/etc/runlevels" -type l -printf '%l\n' |
    grep -Ev '^/etc/init\.d/' |
    grep -q .; then
    printf 'ERROR: non-OpenRC runlevel target introduced during runtime integration.\n' >&2
    exit 1
fi

if [[ "$(readlink "$rootfs/usr/bin/init")" != "openrc-init" ]]; then
    printf 'ERROR: OpenRC init target changed during runtime integration.\n' >&2
    exit 1
fi

printf 'PASS: Artix/OpenRC brightness and RTC-less clock policy integrated.\n'

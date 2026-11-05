#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-}"

if [[ -z "$destination" ]]; then
    printf 'usage: %s DESTINATION\n' "$0" >&2
    exit 2
fi

rm -rf "$destination"
mkdir -p "$destination"

package_meta="$repo_root/image/archlinuxarm/packages/linux-uconsole"

install -m644 "$package_meta/PKGBUILD" "$destination/PKGBUILD"
install -m644 "$package_meta/linux-uconsole.preset" \
    "$destination/linux-uconsole.preset"
install -m644 "$package_meta/README.md" "$destination/README.md"

install -m644 "$repo_root/kernel/config/uconsole-cm4.config" \
    "$destination/uconsole-cm4.config"
install -m644 "$repo_root/kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts" \
    "$destination/clockworkpi-uconsole-cm4-overlay.dts"
install -m644 "$repo_root/kernel/drivers/uconsole-amp-switch.c" \
    "$destination/uconsole-amp-switch.c"

for patch_file in "$repo_root"/kernel/patches/000[1-5]-*.patch; do
    install -m644 "$patch_file" "$destination/$(basename "$patch_file")"
done

printf 'Staged linux-uconsole package workspace: %s\n' "$destination"

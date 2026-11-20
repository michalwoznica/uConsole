#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'ERROR: Stage 10 rootfs builder must run as root in the disposable Arch container.\n' >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$#" -ne 2 ]]; then
    printf 'usage: %s OUTPUT_ROOTFS OUTPUT_PACKAGE_DIR\n' "$0" >&2
    exit 2
fi

output_rootfs="$1"
output_package_dir="$2"

# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/rootfs.lock"

kernel_release="6.18.60-1-uconsole"
jobs="${JOBS:-$(nproc)}"
package_list="$repo_root/image/archlinuxarm/rootfs/uconsole-base-packages.txt"
mapfile -t image_packages < "$package_list"

if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: JOBS must be a positive integer, got: %s\n' "$jobs" >&2
    exit 1
fi

workdir="$(mktemp -d)"
chmod 0755 "$workdir"

target_ldconfig=""
target_ldconfig_mode=""

restore_target_ldconfig() {
    if [[ -n "$target_ldconfig" && -n "$target_ldconfig_mode" && -e "$target_ldconfig" ]]; then
        chmod "$target_ldconfig_mode" "$target_ldconfig" 2>/dev/null || true
        target_ldconfig_mode=""
    fi
}

cleanup() {
    restore_target_ldconfig
    chmod -R u+rwX "$workdir" 2>/dev/null || true
    rm -rf "$workdir"
}
trap cleanup EXIT

archive="$workdir/$ROOTFS_FILENAME"
md5_file="$archive$ROOTFS_MD5_SUFFIX"
sig_file="$archive$ROOTFS_SIGNATURE_SUFFIX"
keyring_source="$workdir/archlinuxarm-source.gpg"
keyring="$workdir/archlinuxarm-binary.gpg"
package_stage="$workdir/linux-uconsole-package"
build_home="$workdir/build-home"
target_gpgdir="$output_rootfs/etc/pacman.d/gnupg"
host_keyring_dir="/usr/share/pacman/keyrings"
target_keyring_dir="$output_rootfs/usr/share/pacman/keyrings"

download_from_base() {
    local base_url="$1"
    local name="$2"
    local output="$3"

    curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 \
        "${base_url}/${name}" \
        --output "$output"
}

download_versioned_input() {
    local name="$1"
    local output="$2"

    if download_from_base "$ROOTFS_PRIMARY_BASE_URL" "$name" "$output"; then
        return 0
    fi

    printf 'Primary mirror failed for %s; trying fallback mirror.\n' "$name" >&2
    download_from_base "$ROOTFS_FALLBACK_BASE_URL" "$name" "$output"
}

printf 'Checking Stage 10 authenticated-rootfs policy...\n'

case "$ROOTFS_FILENAME" in
    *-latest*)
        printf 'ERROR: Stage 10 rootfs input must be versioned, not -latest.\n' >&2
        exit 1
        ;;
esac

rm -rf "$output_rootfs" "$output_package_dir"
mkdir -p "$output_rootfs" "$output_package_dir"

printf 'Fetching pinned Arch Linux ARM rootfs...\n'
download_versioned_input "$ROOTFS_FILENAME" "$archive"
download_versioned_input \
    "${ROOTFS_FILENAME}${ROOTFS_MD5_SUFFIX}" \
    "$md5_file"
download_versioned_input \
    "${ROOTFS_FILENAME}${ROOTFS_SIGNATURE_SUFFIX}" \
    "$sig_file"

actual_size="$(stat -c '%s' "$archive")"
if [[ "$actual_size" != "$ROOTFS_EXPECTED_SIZE" ]]; then
    printf 'ERROR: rootfs size mismatch: got %s expected %s\n' \
        "$actual_size" "$ROOTFS_EXPECTED_SIZE" >&2
    exit 1
fi

published_md5="$(awk 'NF {print $1; exit}' "$md5_file")"
actual_md5="$(md5sum "$archive" | awk '{print $1}')"
if [[ "${actual_md5,,}" != "${published_md5,,}" ]]; then
    printf 'ERROR: rootfs MD5 mismatch.\n' >&2
    exit 1
fi

actual_sha256="$(sha256sum "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$ROOTFS_SHA256" ]]; then
    printf 'ERROR: rootfs SHA-256 mismatch: got %s expected %s\n' \
        "$actual_sha256" "$ROOTFS_SHA256" >&2
    exit 1
fi

keyring_member="$(
    bsdtar -tf "$archive" |
        grep -E '(^|^\./)usr/share/pacman/keyrings/archlinuxarm\.gpg$' |
        head -n 1
)"
if [[ -z "$keyring_member" ]]; then
    printf 'ERROR: Arch Linux ARM keyring not found in rootfs archive.\n' >&2
    exit 1
fi

bsdtar -xOf "$archive" "$keyring_member" > "$keyring_source"
test -s "$keyring_source"

if grep -aqm1 '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$keyring_source"; then
    gpg \
        --batch \
        --yes \
        --dearmor \
        --output "$keyring" \
        "$keyring_source"
else
    cp "$keyring_source" "$keyring"
fi

gpgv_status="$workdir/gpgv-status.txt"
gpgv_log="$workdir/gpgv-log.txt"

if ! gpgv \
    --status-fd=1 \
    --keyring "$keyring" \
    "$sig_file" "$archive" \
    >"$gpgv_status" \
    2>"$gpgv_log"; then
    printf 'ERROR: detached rootfs signature verification failed.\n' >&2
    cat "$gpgv_status" >&2 || true
    cat "$gpgv_log" >&2 || true
    exit 1
fi

if ! awk \
    -v expected="$ROOTFS_SIGNING_FINGERPRINT" \
    '$1 == "[GNUPG:]" && $2 == "VALIDSIG" &&
     ($3 == expected || $12 == expected) { found = 1 }
     END { exit(found ? 0 : 1) }' \
    "$gpgv_status"; then
    printf 'ERROR: rootfs signature identity mismatch.\n' >&2
    cat "$gpgv_status" >&2
    exit 1
fi

printf 'Extracting authenticated rootfs...\n'
bsdtar -xpf "$archive" -C "$output_rootfs"

printf 'Preparing temporary target pacman keyring for Arch Linux ARM package verification...\n'
for keyring_file in \
    archlinuxarm.gpg \
    archlinuxarm-trusted \
    archlinuxarm-revoked
do
    if [[ ! -f "$target_keyring_dir/$keyring_file" ]]; then
        printf 'ERROR: target keyring file missing: %s\n' "$keyring_file" >&2
        exit 1
    fi
    install -Dm644 \
        "$target_keyring_dir/$keyring_file" \
        "$host_keyring_dir/$keyring_file"
done

# pacman --sysroot operates from inside the target root. Initialize the
# temporary verification keyring at the target's normal GPGDir so package
# signature checks use a writable, visible keyring during image composition.
rm -rf "$target_gpgdir"
install -d -m700 "$target_gpgdir"
pacman-key --gpgdir "$target_gpgdir" --init
pacman-key --gpgdir "$target_gpgdir" --populate archlinux archlinuxarm
test -s "$target_gpgdir/pubring.gpg"
test -s "$target_gpgdir/trustdb.gpg"

pacman_target() {
    # This pacman process runs inside the disposable x86_64 build container,
    # not under the target uConsole kernel. Do not depend on the build host's
    # Landlock/container policy while composing a foreign-architecture sysroot;
    # disable only that build-time filesystem restriction. The generated target
    # /etc/pacman.conf is unchanged and retains normal sandboxing.
    pacman \
        --sysroot "$output_rootfs" \
        --arch aarch64 \
        --disable-sandbox-filesystem \
        "$@"
}

printf 'Checking stock package state...\n'
for pkg in \
    linux-aarch64 \
    uboot-raspberrypi \
    firmware-raspberrypi \
    raspberrypi-bootloader \
    mkinitcpio
do
    pacman_target -Q "$pkg" >/dev/null
done

prebuilt_kernel_package="${UCONSOLE_PREBUILT_KERNEL_PACKAGE:-}"

if [[ -n "$prebuilt_kernel_package" ]]; then
    printf 'Using prebuilt linux-uconsole package: %s\n' \
        "$(basename "$prebuilt_kernel_package")"
    if [[ ! -s "$prebuilt_kernel_package" ]]; then
        printf 'ERROR: prebuilt linux-uconsole package is missing or empty: %s\n' \
            "$prebuilt_kernel_package" >&2
        exit 1
    fi
    cp -a "$prebuilt_kernel_package" "$output_package_dir/"
else
    printf 'Staging linux-uconsole package workspace...\n'
    bash "$repo_root/scripts/stage-arch-kernel-package.sh" "$package_stage"
    mkdir -p "$build_home"

    if ! id -u uconsole-build >/dev/null 2>&1; then
        useradd \
            --no-create-home \
            --home-dir "$build_home" \
            --shell /bin/bash \
            uconsole-build
    fi

    chown -R uconsole-build:uconsole-build \
        "$package_stage" "$output_package_dir" "$build_home"

    printf 'Cross-building real aarch64 linux-uconsole package with makepkg (-j%s)...\n' "$jobs"
    runuser -u uconsole-build -- \
        env \
            HOME="$build_home" \
            CARCH=aarch64 \
            ARCH=arm64 \
            CROSS_COMPILE=aarch64-linux-gnu- \
            MAKEFLAGS="-j${jobs}" \
            PKGDEST="$output_package_dir" \
            makepkg \
                --ignorearch \
                --nodeps \
                --cleanbuild \
                --force \
                --noconfirm \
                --nocheck \
                --dir "$package_stage"
fi

mapfile -t package_files < <(
    find "$output_package_dir" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' \
        ! -name '*.sig' \
        | sort
)

if [[ "${#package_files[@]}" -ne 1 ]]; then
    printf 'ERROR: expected exactly one linux-uconsole aarch64 package, got %s.\n' \
        "${#package_files[@]}" >&2
    printf '%s\n' "${package_files[@]:-}" >&2
    exit 1
fi

package_file="${package_files[0]}"
printf 'Built package: %s\n' "$(basename "$package_file")"

pkginfo="$workdir/PKGINFO"
bsdtar -xOf "$package_file" .PKGINFO > "$pkginfo"
grep -Fxq 'pkgname = linux-uconsole' "$pkginfo"
grep -Fxq 'pkgver = 6.18.60-1' "$pkginfo"
grep -Fxq 'arch = aarch64' "$pkginfo"
grep -Fxq 'conflict = linux-aarch64' "$pkginfo"
grep -Fxq 'conflict = uboot-raspberrypi' "$pkginfo"

printf 'Preparing cross-architecture pacman transaction...\n'
system_hooks="$output_rootfs/usr/share/libalpm/hooks"
system_hooks_saved="$output_rootfs/usr/share/libalpm/hooks.stage10-saved"
system_hooks_updated="$output_rootfs/usr/share/libalpm/hooks.stage10-updated"
custom_hooks="$output_rootfs/etc/pacman.d/hooks"
custom_hooks_saved="$output_rootfs/etc/pacman.d/hooks.stage10-saved"

if [[ -e "$system_hooks_saved" || -e "$system_hooks_updated" || -e "$custom_hooks_saved" ]]; then
    printf 'ERROR: unexpected Stage 10 hook-save path already exists.\n' >&2
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

target_ldconfig="$output_rootfs/usr/bin/ldconfig"
if [[ ! -x "$target_ldconfig" ]]; then
    printf 'ERROR: expected executable target ldconfig missing.\n' >&2
    exit 1
fi
target_ldconfig_mode="$(stat -Lc '%a' "$target_ldconfig")"
chmod a-x "$target_ldconfig"

printf 'Updating Arch userspace and installing uConsole console/validation tools...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --needed \
    --ignore linux-aarch64,uboot-raspberrypi \
    -Syu \
    "${image_packages[@]}"

# Keep hooks installed by the updated packages, but prevent them from running
# during the following foreign-architecture kernel replacement transaction.
mv "$system_hooks" "$system_hooks_updated"
mkdir -p "$system_hooks"

printf 'Replacing stock kernel/U-Boot with linux-uconsole...\n'
pacman_target \
    --noconfirm \
    --noscriptlet \
    --nosave \
    -Rdd \
    linux-aarch64 \
    uboot-raspberrypi

pacman_target \
    --noconfirm \
    --noscriptlet \
    --asexplicit \
    -U "$package_file"

restore_target_ldconfig

rm -rf "$system_hooks"
mv "$system_hooks_updated" "$system_hooks"
if [[ -d "$system_hooks_saved" ]]; then
    cp -an "$system_hooks_saved/." "$system_hooks/"
    rm -rf "$system_hooks_saved"
fi

rm -rf "$custom_hooks"
if [[ -d "$custom_hooks_saved" ]]; then
    mv "$custom_hooks_saved" "$custom_hooks"
fi

printf 'Generating target kernel module dependency metadata...\n'
if ! command -v depmod >/dev/null 2>&1; then
    printf 'ERROR: host depmod is required to prepare the target module tree.\n' >&2
    exit 1
fi

depmod \
    -b "$output_rootfs" \
    "$kernel_release"

printf 'Installing final Stage 9C boot/root policy into rootfs tree...\n'
install -Dm644 \
    "$repo_root/image/archlinuxarm/boot/config-uconsole-cm4.txt" \
    "$output_rootfs/boot/config.txt"
install -Dm644 \
    "$repo_root/image/archlinuxarm/boot/cmdline-uconsole-cm4.txt" \
    "$output_rootfs/boot/cmdline.txt"
install -Dm644 \
    "$repo_root/image/archlinuxarm/rootfs/fstab-uconsole-cm4" \
    "$output_rootfs/etc/fstab"

printf 'Configuring console-first userspace defaults...\n'
install -Dm644 \
    "$repo_root/image/archlinuxarm/rootfs/NetworkManager-uconsole.conf" \
    "$output_rootfs/etc/NetworkManager/conf.d/10-uconsole.conf"
install -Dm644 \
    "$repo_root/image/archlinuxarm/rootfs/sysctl-uconsole.conf" \
    "$output_rootfs/etc/sysctl.d/50-uconsole-console.conf"
install -Dm644 \
    "$repo_root/image/archlinuxarm/rootfs/uconsole-pacman-keyring-init.service" \
    "$output_rootfs/usr/lib/systemd/system/uconsole-pacman-keyring-init.service"

ln -sfn ../run/systemd/resolve/stub-resolv.conf \
    "$output_rootfs/etc/resolv.conf"

systemctl --root="$output_rootfs" disable \
    systemd-networkd.service \
    systemd-networkd-wait-online.service \
    systemd-network-generator.service \
    systemd-networkd.socket \
    systemd-networkd-varlink.socket \
    systemd-networkd-varlink-metrics.socket \
    systemd-networkd-resolve-hook.socket >/dev/null

systemctl --root="$output_rootfs" enable \
    NetworkManager.service \
    systemd-resolved.service \
    bluetooth.service \
    uconsole-pacman-keyring-init.service >/dev/null

printf 'Validating integrated Stage 10 rootfs tree...\n'
pacman_target -Q linux-uconsole |
    grep -Fxq 'linux-uconsole 6.18.60-1'

if pacman_target -Q linux-aarch64 >/dev/null 2>&1; then
    printf 'ERROR: linux-aarch64 still installed.\n' >&2
    exit 1
fi

if pacman_target -Q uboot-raspberrypi >/dev/null 2>&1; then
    printf 'ERROR: uboot-raspberrypi still installed.\n' >&2
    exit 1
fi

for retained in \
    firmware-raspberrypi \
    raspberrypi-bootloader \
    mkinitcpio \
    linux-firmware
do
    pacman_target -Q "$retained" >/dev/null
done

for pkg in "${image_packages[@]}"; do
    pacman_target -Q "$pkg" >/dev/null
done

[[ "$(readlink "$output_rootfs/etc/resolv.conf")" == "../run/systemd/resolve/stub-resolv.conf" ]]
systemctl --root="$output_rootfs" is-enabled NetworkManager.service | grep -Fxq enabled
systemctl --root="$output_rootfs" is-enabled systemd-resolved.service | grep -Fxq enabled
systemctl --root="$output_rootfs" is-enabled bluetooth.service | grep -Fxq enabled
systemctl --root="$output_rootfs" is-enabled uconsole-pacman-keyring-init.service | grep -Fxq enabled
[[ "$(systemctl --root="$output_rootfs" is-enabled systemd-networkd.service 2>/dev/null || true)" == "disabled" ]]

pacman_target -Dk
pacman_target -Qk linux-uconsole

# The build-time keyring contains a generated private local signing key.
# Do not ship it. First boot creates a unique pacman keyring for the device.
rm -rf "$target_gpgdir"
test ! -e "$target_gpgdir"

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
    modules.symbols.bin
do
    test -e "$module_dir/$generated"
done
test -e "$module_dir/modules.devname"

panel_modinfo="$workdir/panel-cwu50.modinfo"
backlight_modinfo="$workdir/ocp8178-bl.modinfo"

modinfo \
    -b "$output_rootfs" \
    -k "$kernel_release" \
    panel_cwu50 > "$panel_modinfo"
modinfo \
    -b "$output_rootfs" \
    -k "$kernel_release" \
    ocp8178_bl > "$backlight_modinfo"

grep -Eq '^name:[[:space:]]+panel_cwu50$' "$panel_modinfo"
grep -Eq '^alias:[[:space:]]+of:N\*T\*Ccw,cwu50$' "$panel_modinfo"
grep -Eq '^name:[[:space:]]+ocp8178_bl$' "$backlight_modinfo"
grep -Eq '^alias:[[:space:]]+of:N\*T\*Cocp8178-backlight$' "$backlight_modinfo"

cmp -s \
    "$repo_root/image/archlinuxarm/boot/config-uconsole-cm4.txt" \
    "$output_rootfs/boot/config.txt"
cmp -s \
    "$repo_root/image/archlinuxarm/boot/cmdline-uconsole-cm4.txt" \
    "$output_rootfs/boot/cmdline.txt"
cmp -s \
    "$repo_root/image/archlinuxarm/rootfs/fstab-uconsole-cm4" \
    "$output_rootfs/etc/fstab"

mapfile -t linux_uconsole_file_dbs < <(
    find "$output_rootfs/var/lib/pacman/local" \
        -mindepth 2 \
        -maxdepth 2 \
        -type f \
        -name files \
        -path '*/linux-uconsole-*/files' \
        -print |
        sort
)

if [[ "${#linux_uconsole_file_dbs[@]}" -ne 1 ]]; then
    printf 'ERROR: expected exactly one installed linux-uconsole files database.\n' >&2
    exit 1
fi

grep -Fxq 'boot/kernel8.img' "${linux_uconsole_file_dbs[0]}"

if [[ -e "$output_rootfs/boot/boot.scr" || -e "$output_rootfs/boot/boot.txt" ]]; then
    printf 'ERROR: U-Boot boot-script residue remains.\n' >&2
    exit 1
fi

printf 'Cleaning temporary package build tree to reduce runner disk usage...\n'
rm -rf "$package_stage"
rm -f "$archive" "$md5_file" "$sig_file" "$keyring_source" "$keyring"

printf 'PASS: Stage 10 integrated rootfs tree prepared.\n'

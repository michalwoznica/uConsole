#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/rootfs.lock"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

archive="$workdir/$ROOTFS_FILENAME"
md5_file="$archive$ROOTFS_MD5_SUFFIX"
sig_file="$archive$ROOTFS_SIGNATURE_SUFFIX"
rootfs="$workdir/rootfs"
keyring="$workdir/archlinuxarm.gpg"

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

printf 'Checking Stage 9A rootfs lock policy...\n'

case "$ROOTFS_FILENAME" in
    *-latest*)
        printf 'ERROR: Stage 9A rootfs input must be versioned, not -latest.\n' >&2
        exit 1
        ;;
esac

[[ "$ROOTFS_RELEASE" =~ ^[0-9]{4}\.[0-9]{2}$ ]]
[[ "$ROOTFS_EXPECTED_SIZE" =~ ^[1-9][0-9]*$ ]]
[[ "$ROOTFS_SIGNING_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]]

printf 'Fetching pinned Arch Linux ARM rootfs %s...\n' "$ROOTFS_RELEASE"
download_versioned_input "$ROOTFS_FILENAME" "$archive"
download_versioned_input \
    "${ROOTFS_FILENAME}${ROOTFS_MD5_SUFFIX}" \
    "$md5_file"
download_versioned_input \
    "${ROOTFS_FILENAME}${ROOTFS_SIGNATURE_SUFFIX}" \
    "$sig_file"

printf 'Checking exact archive size...\n'
actual_size="$(stat -c '%s' "$archive")"
if [[ "$actual_size" != "$ROOTFS_EXPECTED_SIZE" ]]; then
    printf 'ERROR: rootfs size mismatch: got %s expected %s\n' \
        "$actual_size" "$ROOTFS_EXPECTED_SIZE" >&2
    exit 1
fi

printf 'Checking published MD5...\n'
published_md5="$(awk 'NF {print $1; exit}' "$md5_file")"
if ! [[ "$published_md5" =~ ^[0-9a-fA-F]{32}$ ]]; then
    printf 'ERROR: malformed published MD5 file.\n' >&2
    cat "$md5_file" >&2
    exit 1
fi

actual_md5="$(md5sum "$archive" | awk '{print $1}')"
if [[ "${actual_md5,,}" != "${published_md5,,}" ]]; then
    printf 'ERROR: rootfs MD5 mismatch.\n' >&2
    exit 1
fi

printf 'Locating Arch Linux ARM keyring inside the signed archive...\n'
keyring_member="$(
    bsdtar -tf "$archive" |
        grep -E '(^|^\./)usr/share/pacman/keyrings/archlinuxarm\.gpg$' |
        head -n 1
)"

if [[ -z "$keyring_member" ]]; then
    printf 'ERROR: Arch Linux ARM keyring not found in rootfs archive.\n' >&2
    exit 1
fi

bsdtar -xOf "$archive" "$keyring_member" > "$keyring"
test -s "$keyring"

printf 'Checking extracted keyring for official signing fingerprint...\n'
keyring_fingerprints="$(
    gpg \
        --batch \
        --no-default-keyring \
        --keyring "$keyring" \
        --with-colons \
        --list-keys 2>/dev/null |
        awk -F: '$1 == "fpr" { print $10 }'
)"

if ! grep -Fxq "$ROOTFS_SIGNING_FINGERPRINT" <<< "$keyring_fingerprints"; then
    printf 'ERROR: official Arch Linux ARM signing fingerprint not present.\n' >&2
    printf 'Fingerprints present in extracted keyring:\n' >&2
    printf '%s\n' "$keyring_fingerprints" >&2
    exit 1
fi

printf 'Verifying detached Arch Linux ARM rootfs signature...\n'
gpgv_status="$workdir/gpgv-status.txt"
if ! gpgv \
    --status-fd=1 \
    --keyring "$keyring" \
    "$sig_file" "$archive" \
    >"$gpgv_status"; then
    printf 'ERROR: detached rootfs signature verification failed.\n' >&2
    cat "$gpgv_status" >&2
    exit 1
fi

validsig_fingerprint="$(
    awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3; exit }' \
        "$gpgv_status"
)"

if [[ "$validsig_fingerprint" != "$ROOTFS_SIGNING_FINGERPRINT" ]]; then
    printf 'ERROR: rootfs signature used unexpected key: %s\n' \
        "${validsig_fingerprint:-<none>}" >&2
    cat "$gpgv_status" >&2
    exit 1
fi

printf 'Signature validated by expected fingerprint: %s\n' \
    "$validsig_fingerprint"

printf 'Recording stronger local digest for diagnostics...\n'
sha256sum "$archive"

printf 'Extracting authenticated rootfs for structural audit...\n'
mkdir -p "$rootfs"
bsdtar -xpf "$archive" -C "$rootfs"

required_paths=(
    usr/bin/pacman
    usr/bin/systemctl
    etc/pacman.conf
    etc/os-release
    usr/share/pacman/keyrings/archlinuxarm.gpg
    var/lib/pacman/local
    boot
)

for relative_path in "${required_paths[@]}"; do
    if [[ ! -e "$rootfs/$relative_path" ]]; then
        printf 'ERROR: expected rootfs path missing: /%s\n' \
            "$relative_path" >&2
        exit 1
    fi
done

printf 'Reading package inventory directly from pacman local database...\n'
inventory="$workdir/package-inventory.txt"
: > "$inventory"

for desc in "$rootfs"/var/lib/pacman/local/*/desc; do
    [[ -f "$desc" ]] || continue
    awk '
        $0 == "%NAME%" {
            if (getline > 0) {
                print
            }
            exit
        }
    ' "$desc" >> "$inventory"
done

sort -u -o "$inventory" "$inventory"

for required_package in pacman archlinuxarm-keyring; do
    if ! grep -qx "$required_package" "$inventory"; then
        printf 'ERROR: expected base package missing: %s\n' \
            "$required_package" >&2
        exit 1
    fi
done

printf '\n=== STAGE 9B STOCK KERNEL/BOOT PACKAGE INVENTORY ===\n'
grep -E \
    '^(linux($|-)|uboot-raspberrypi$|raspberrypi-bootloader$|firmware-raspberrypi$|mkinitcpio$)' \
    "$inventory" || true
printf '=== END INVENTORY ===\n\n'

printf 'Boot directory top-level entries:\n'
find "$rootfs/boot" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort

printf 'PASS: Stage 9A pinned rootfs provenance and structure validated.\n'

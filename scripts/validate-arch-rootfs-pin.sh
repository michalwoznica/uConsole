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
keyring_source="$workdir/archlinuxarm-source.gpg"
keyring="$workdir/archlinuxarm-binary.gpg"

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

bsdtar -xOf "$archive" "$keyring_member" > "$keyring_source"
test -s "$keyring_source"

printf 'Normalizing extracted Arch Linux ARM keyring for gpgv...\n'
if grep -aqm1 '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$keyring_source"; then
    printf 'Detected ASCII-armored keyring; converting to binary OpenPGP packets.\n'
    gpg \
        --batch \
        --yes \
        --dearmor \
        --output "$keyring" \
        "$keyring_source"
else
    printf 'Detected binary keyring; using it unchanged.\n'
    cp "$keyring_source" "$keyring"
fi

test -s "$keyring"

printf 'Verifying detached Arch Linux ARM rootfs signature...\n'
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
     ($3 == expected || $12 == expected) {
         found = 1
     }
     END {
         exit(found ? 0 : 1)
     }' \
    "$gpgv_status"; then
    printf 'ERROR: valid rootfs signature was not made by the expected Arch Linux ARM key.\n' >&2
    printf 'Expected primary/signing fingerprint: %s\n' \
        "$ROOTFS_SIGNING_FINGERPRINT" >&2
    cat "$gpgv_status" >&2
    cat "$gpgv_log" >&2 || true
    exit 1
fi

validsig_summary="$(
    awk \
        '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {
            signer = $3
            primary = (NF >= 12 ? $12 : $3)
            printf "signer=%s primary=%s", signer, primary
            exit
        }' \
        "$gpgv_status"
)"

printf 'Signature validated against expected Arch Linux ARM identity: %s\n' \
    "$validsig_summary"

printf 'Recording stronger local digest for diagnostics...\n'
sha256sum "$archive"

printf 'Auditing authenticated rootfs archive structure without extraction...\n'
archive_index="$workdir/archive-index.txt"
bsdtar -tf "$archive" |
    sed -e 's#^\./##' -e 's#/$##' \
    > "$archive_index"

required_files=(
    usr/bin/pacman
    usr/bin/systemctl
    etc/pacman.conf
    etc/os-release
    usr/share/pacman/keyrings/archlinuxarm.gpg
)

for relative_path in "${required_files[@]}"; do
    if ! grep -Fxq "$relative_path" "$archive_index"; then
        printf 'ERROR: expected rootfs file missing from archive: /%s\n' \
            "$relative_path" >&2
        exit 1
    fi
done

for required_tree in var/lib/pacman/local boot; do
    if ! grep -qE "^${required_tree}(/|$)" "$archive_index"; then
        printf 'ERROR: expected rootfs tree missing from archive: /%s\n' \
            "$required_tree" >&2
        exit 1
    fi
done

printf 'Reading package inventory directly from archived pacman database...\n'
inventory="$workdir/package-inventory.txt"
: > "$inventory"

while IFS= read -r desc_member; do
    [[ -n "$desc_member" ]] || continue
    bsdtar -xOf "$archive" "$desc_member" |
        awk '
            $0 == "%NAME%" {
                if (getline > 0) {
                    print
                }
                exit
            }
        ' >> "$inventory"
done < <(
    bsdtar -tf "$archive" |
        grep -E '^(\./)?var/lib/pacman/local/[^/]+/desc$'
)

sort -u -o "$inventory" "$inventory"

if [[ ! -s "$inventory" ]]; then
    printf 'ERROR: pacman local package inventory is empty.\n' >&2
    exit 1
fi

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
sed -e 's#^\./##' "$archive_index" |
    awk '
        /^boot\/[^/]+\/?$/ {
            sub(/^boot\//, "")
            sub(/\/$/, "")
            if (length($0) > 0) {
                print
            }
        }
    ' |
    sort -u

printf 'PASS: Stage 9A pinned rootfs provenance and archive structure validated.\n'

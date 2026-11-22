#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"
# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/image-layout.lock"

cmdline_file="$repo_root/image/archlinuxarm/boot/cmdline-uconsole-cm4.txt"
config_file="$repo_root/image/shared/boot/config-uconsole-cm4.txt"
fstab_file="$repo_root/image/archlinuxarm/rootfs/fstab-uconsole-cm4"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

printf 'Checking Stage 9C deterministic image identity...\n'

[[ "$PARTITION_TABLE" == "dos" ]]
[[ "$DISK_IDENTIFIER_HEX" =~ ^0x[0-9a-fA-F]{8}$ ]]
[[ "$BOOT_PARTITION_NUMBER" == "1" ]]
[[ "$ROOT_PARTITION_NUMBER" == "2" ]]
[[ "$BOOT_FILESYSTEM" == "vfat" ]]
[[ "$ROOT_FILESYSTEM" == "ext4" ]]
[[ "$BOOT_MOUNTPOINT" == "/boot" ]]
[[ "$ROOT_MOUNTPOINT" == "/" ]]

disk_id="${DISK_IDENTIFIER_HEX#0x}"
disk_id="${disk_id,,}"

expected_boot_partuuid="${disk_id}-01"
expected_root_partuuid="${disk_id}-02"

if [[ "$BOOT_PARTUUID" != "$expected_boot_partuuid" ]]; then
    printf 'ERROR: BOOT_PARTUUID does not match DOS disk identifier/partition 1.\n' >&2
    exit 1
fi

if [[ "$ROOT_PARTUUID" != "$expected_root_partuuid" ]]; then
    printf 'ERROR: ROOT_PARTUUID does not match DOS disk identifier/partition 2.\n' >&2
    exit 1
fi

printf 'Checking final Raspberry Pi kernel command line...\n'

mapfile -t cmdline_lines < "$cmdline_file"
if [[ "${#cmdline_lines[@]}" -ne 1 ]]; then
    printf 'ERROR: Raspberry Pi cmdline must contain exactly one line.\n' >&2
    exit 1
fi

cmdline="${cmdline_lines[0]}"

expected_cmdline="8250.nr_uarts=1 console=tty1 root=PARTUUID=${ROOT_PARTUUID} rootfstype=ext4 rootwait rw loglevel=3"
if [[ "$cmdline" != "$expected_cmdline" ]]; then
    printf 'ERROR: cmdline does not match the Stage 9C boot contract.\n' >&2
    printf 'Expected: %s\n' "$expected_cmdline" >&2
    printf 'Actual:   %s\n' "$cmdline" >&2
    exit 1
fi

for forbidden in \
    'console=serial' \
    'console=ttyAMA' \
    'console=ttyS' \
    'root=/dev/' \
    'root=UUID=' \
    'root=LABEL=' \
    'quiet' \
    'splash' \
    'initrd='
do
    if [[ "$cmdline" == *"$forbidden"* ]]; then
        printf 'ERROR: forbidden Stage 9C cmdline token present: %s\n' \
            "$forbidden" >&2
        exit 1
    fi
done

printf 'Checking Raspberry Pi firmware boot policy...\n'

for required in \
    'arm_64bit=1' \
    'gpio=10=ip,np' \
    'otg_mode=1' \
    'dtparam=audio=on' \
    'dtoverlay=audremap,pins_12_13' \
    'dtoverlay=clockworkpi-uconsole-cm4' \
    'dtoverlay=vc4-kms-v3d-pi4,cma-384' \
    'kernel=kernel8.img'
do
    if ! grep -Fxq "$required" "$config_file"; then
        printf 'ERROR: required config.txt policy missing: %s\n' "$required" >&2
        exit 1
    fi
done

if grep -Eq '^[[:space:]]*(initramfs|auto_initramfs|enable_uart|cmdline)=' \
    "$config_file"; then
    printf 'ERROR: Stage 9C config.txt unexpectedly enables initramfs, UART console policy, or alternate cmdline.\n' >&2
    grep -En '^[[:space:]]*(initramfs|auto_initramfs|enable_uart|cmdline)=' \
        "$config_file" >&2 || true
    exit 1
fi

printf 'Checking reproducible fstab policy...\n'

if ! grep -Eq \
    "^PARTUUID=${ROOT_PARTUUID}[[:space:]]+/[[:space:]]+ext4[[:space:]]+defaults[[:space:]]+0[[:space:]]+1$" \
    "$fstab_file"; then
    printf 'ERROR: deterministic root fstab entry missing.\n' >&2
    exit 1
fi

if ! grep -Eq \
    "^PARTUUID=${BOOT_PARTUUID}[[:space:]]+/boot[[:space:]]+vfat[[:space:]]+defaults[[:space:]]+0[[:space:]]+2$" \
    "$fstab_file"; then
    printf 'ERROR: deterministic /boot fstab entry missing.\n' >&2
    exit 1
fi

if grep -Eq \
    '(^|[[:space:]])(/dev/(mmcblk|sd[a-z]|nvme)|UUID=|LABEL=)' \
    "$fstab_file"; then
    printf 'ERROR: unstable /dev, UUID=, or LABEL= addressing leaked into Stage 9C fstab.\n' >&2
    exit 1
fi

printf 'Checking exact pinned BCM2711 direct-root prerequisites...\n'

defconfig="$workdir/bcm2711_defconfig"
curl --fail --location --silent --show-error \
    "https://raw.githubusercontent.com/raspberrypi/linux/${RPI_LINUX_COMMIT}/arch/arm64/configs/bcm2711_defconfig" \
    --output "$defconfig"

required_builtin=(
    CONFIG_DEVTMPFS=y
    CONFIG_DEVTMPFS_MOUNT=y
    CONFIG_MMC=y
    CONFIG_MMC_SDHCI=y
    CONFIG_MMC_SDHCI_PLTFM=y
    CONFIG_MMC_SDHCI_IPROC=y
    CONFIG_MMC_BCM2835=y
    CONFIG_MMC_BCM2835_MMC=y
    CONFIG_EXT4_FS=y
    CONFIG_SERIAL_8250=y
    CONFIG_SERIAL_8250_BCM2835AUX=y
    CONFIG_BLK_DEV_INITRD=y
)

for setting in "${required_builtin[@]}"; do
    if ! grep -Fxq "$setting" "$defconfig"; then
        printf 'ERROR: pinned bcm2711_defconfig lacks required built-in setting: %s\n' \
            "$setting" >&2
        exit 1
    fi
done

if ! grep -Fxq 'CONFIG_SERIAL_8250_RUNTIME_UARTS=0' "$defconfig"; then
    printf 'ERROR: pinned UART runtime default changed; re-evaluate 8250.nr_uarts policy.\n' >&2
    exit 1
fi

if grep -Eq '^CONFIG_CMDLINE_(FORCE|EXTEND)=y$' "$defconfig"; then
    printf 'ERROR: pinned kernel forces/extends CONFIG_CMDLINE; firmware cmdline authority must be re-evaluated.\n' >&2
    exit 1
fi

printf 'PASS: Stage 9C direct-root boot contract validated.\n'

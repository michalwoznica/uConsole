# Stage 9C — final boot command line and initramfs policy

**Status:** complete; all Stage 9C validation workflows passed.

## Goal

Freeze the first-image boot contract before Stage 10 creates partitions or a
flashable microSD image.

Stage 9C changes no kernel source and performs no full kernel rebuild.

## Boot chain

The first uConsole image uses the Raspberry Pi CM4 firmware directly:

1. CM4 EEPROM bootloader selects the FAT boot partition;
2. Raspberry Pi firmware reads `config.txt`;
3. firmware loads `bcm2711-rpi-cm4.dtb` plus project overlays;
4. firmware loads `/boot/kernel8.img`;
5. firmware passes the single-line `cmdline.txt`;
6. the kernel discovers microSD directly;
7. the kernel mounts the ext4 root filesystem directly;
8. Arch userspace starts.

U-Boot is not part of this chain.

## Initramfs decision

The first image deliberately does **not** load an initramfs.

The pinned Raspberry Pi `bcm2711_defconfig` has the root-critical path built
into the kernel:

- `CONFIG_MMC=y`;
- `CONFIG_MMC_SDHCI=y`;
- `CONFIG_MMC_SDHCI_PLTFM=y`;
- `CONFIG_MMC_SDHCI_IPROC=y`;
- `CONFIG_MMC_BCM2835=y`;
- `CONFIG_MMC_BCM2835_MMC=y`;
- `CONFIG_EXT4_FS=y`.

Therefore the CM4 microSD + ext4 root path does not require modules from an
initramfs.

`CONFIG_BLK_DEV_INITRD=y` remains enabled and the `linux-uconsole` package
retains its mkinitcpio preset, so an initramfs can be adopted later without a
kernel redesign. It is simply not firmware-loaded for the first image.

This also avoids executing target-AArch64 mkinitcpio before the first physical
boot.

## Deterministic partition identity

Stage 10 must use a DOS/MBR partition table with fixed disk identifier:

`0x55434f4e`

This produces stable partition identities:

- boot partition: `PARTUUID=55434f4e-01`;
- root partition: `PARTUUID=55434f4e-02`.

The value is project-owned and deliberately non-personal.

The first layout remains the conventional Raspberry Pi two-partition shape:

- partition 1: FAT/vfat, mounted at `/boot`;
- partition 2: ext4, mounted at `/`.

Exact partition sizes are a Stage 10 image-construction decision.

## Kernel command line

`image/archlinuxarm/boot/cmdline-uconsole-cm4.txt` contains exactly one line:

`8250.nr_uarts=1 console=tty1 root=PARTUUID=55434f4e-02 rootfstype=ext4 rootwait rw`

Policy:

- `8250.nr_uarts=1` preserves the original uConsole mini-UART availability
  that earlier ClockworkPi hardware support placed in Device Tree bootargs;
- `console=tty1` selects the local Linux virtual console;
- no serial console is enabled;
- GPIO14/15 remain the uConsole expansion UART;
- root uses deterministic PARTUUID rather than `/dev/mmcblk*`;
- root filesystem is explicitly ext4;
- `rootwait` allows the kernel to wait for microSD discovery;
- `rw` requests a read-write root mount;
- no `quiet` or splash option is used for first physical validation.

The Raspberry Pi firmware requires `cmdline.txt` parameters on a single line.

## Serial policy

There is no:

- `console=serial0,...`;
- `console=ttyAMA...`;
- `console=ttyS...`;
- `enable_uart=1`.

This is intentional. The uConsole overlay assigns GPIO14/15 to `uart1` as the
expansion UART. The expansion UART should not silently become a kernel console.

If physical debugging later proves a serial console is necessary, add a
separate explicitly documented debug policy rather than changing the normal
image silently.

## `config.txt`

The existing project policy remains:

- 64-bit CM4 kernel;
- `kernel=kernel8.img`;
- uConsole hardware overlay;
- KMS display overlay;
- PWM audio remap;
- USB2 host mode.

Stage 9C explicitly forbids firmware-loaded `initramfs`/`auto_initramfs` and
does not override the default `cmdline.txt` filename.

## `/etc/fstab`

Stage 10 installs:

`image/archlinuxarm/rootfs/fstab-uconsole-cm4`

with deterministic PARTUUID mounts for:

- `/`;
- `/boot`.

This removes dependence on whether Linux enumerates the card as
`mmcblk0`, `mmcblk1`, or another block-device name.

## Validation

`scripts/validate-arch-boot-contract.sh` checks:

- deterministic DOS disk identifier and derived PARTUUIDs;
- exact one-line cmdline;
- absence of serial-console, quiet/splash and unstable root addressing;
- existing Raspberry Pi firmware config contract;
- absence of firmware-loaded initramfs policy;
- deterministic fstab;
- exact pinned Raspberry Pi kernel baseline for built-in microSD/ext4 root
  support;
- `CONFIG_SERIAL_8250_RUNTIME_UARTS=0`, which makes the explicit
  `8250.nr_uarts=1` policy intentional;
- absence of forced/extended compiled-in command-line policy.

## Boundary

Stage 9C does not:

- create a partition table;
- create FAT/ext4 filesystems;
- copy rootfs contents into an image;
- generate or load an initramfs;
- flash microSD;
- perform physical boot testing.

Those begin in Stage 10.

## Completion criterion

Stage 9C is complete only when:

`Validate uConsole Arch boot contract`

passes.

## First CI correction — PARTUUID false positive

The first Stage 9C validation run passed:

- deterministic image identity;
- final kernel command line;
- Raspberry Pi firmware boot policy;
- exact root and boot fstab entries.

It then failed in the generic unstable-addressing guard.

Root cause:

The validator searched for the substring `UUID=`. A valid token such as
`PARTUUID=55434f4e-02` necessarily contains that substring, so the guard
incorrectly rejected the intended deterministic PARTUUID policy.

Correction:

The forbidden-addressing expression is now token-boundary aware. It rejects:

- `/dev/mmcblk...`;
- `/dev/sd...`;
- `/dev/nvme...`;
- standalone `UUID=...`;
- standalone `LABEL=...`;

while allowing the explicitly required `PARTUUID=...` form.

No boot policy, PARTUUID value, cmdline, fstab content, kernel configuration or
image-layout contract changed.

## Final Stage 9C result

All workflows triggered by the corrected Stage 9C candidate completed successfully.

Proven: deterministic DOS/MBR identity and PARTUUIDs; exact one-line kernel
command line; expansion-UART/no-serial-console policy; Raspberry Pi firmware
configuration; direct `kernel8.img` boot; no firmware-loaded initramfs;
deterministic fstab; built-in CM4 microSD and ext4 root prerequisites; and no
forced/extended compiled-in kernel command line.

Stage 9C is complete.

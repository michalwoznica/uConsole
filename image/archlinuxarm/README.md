# Arch Linux ARM image target

This is the first userspace/image target.

Stage 7 now defines two reusable Arch inputs:

- `packages/linux-uconsole/` — standard Arch package metadata for the custom
  kernel;
- `boot/config-uconsole-cm4.txt` — uConsole-specific Raspberry Pi firmware
  policy to be composed into the eventual image.

The package owns kernel/DTB/overlay/module files. The image layer owns boot
policy, rootfs setup, networking and Arch/systemd-specific configuration.

Planned later responsibilities:

- obtain and pin an Arch Linux ARM aarch64 rootfs;
- install the `linux-uconsole` package;
- compose boot configuration and kernel command line;
- configure networking and userspace packages;
- provide Arch/systemd-specific service integration;
- produce a flashable microSD image.

The existing `fabiiw05/uconsole-archlinux` project remains a useful
image-building reference, but this project uses its own pinned 6.18 LTS kernel
composition and pacman-managed kernel package.

## Stage 9A rootfs pin

The Arch Linux ARM base is pinned in `rootfs.lock`.

The project uses the versioned Raspberry Pi AArch64 2026.08 archive and
verifies its published checksum and detached signature before extraction.
The moving `-latest` alias is informational only and is never a build input.

Stage 9A validates provenance and inventory only. Stage 9B performs custom
kernel/rootfs integration.

## Stage 9B rootfs integration

Stage 9B replaces the authenticated rootfs's `linux-aarch64` +
`uboot-raspberrypi` path with a real pacman-managed `linux-uconsole` package.

`firmware-raspberrypi`, `raspberrypi-bootloader`, `mkinitcpio` and firmware
packages remain installed. The image policy owns `/boot/config.txt`; the
kernel package does not.

Stage 9B validation is pending after a CI workspace-permission correction.
The first run authenticated/extracted the rootfs and reached the real
unprivileged `makepkg` invocation.

Stage 9B result: **PASS**. The authenticated rootfs accepts the real
pacman-managed `linux-uconsole` package; `linux-aarch64` and
`uboot-raspberrypi` are removed, retained firmware/boot packages remain
registered, `/boot/kernel8.img` is owned by `linux-uconsole`, and
`/boot/config.txt` remains deliberately image-policy-owned.

## Stage 9C boot contract

The first image boots directly through Raspberry Pi firmware into
`kernel8.img` and mounts its ext4 microSD root without an initramfs.

Stable image identity is defined in `image-layout.lock`.
`cmdline-uconsole-cm4.txt` and `rootfs/fstab-uconsole-cm4` both use the same
deterministic PARTUUID contract.

The normal image does not use a serial console; GPIO14/15 remain the uConsole
expansion UART.

Stage 9C result: **PASS**. The deterministic boot identity, cmdline, fstab,
direct-root kernel prerequisites and Raspberry Pi firmware boot composition
all validate successfully.

## Stage 10 first image

Stage 10 materializes the completed Stage 9C contract into an 8 GiB raw
microSD image:

- 512 MiB FAT32 `/boot`;
- remaining space ext4 `/`;
- fixed DOS disk ID and PARTUUIDs;
- fixed filesystem identities;
- compressed `.img.zst` workflow artifact plus checksums/manifest.

No physical flashing is performed by CI.

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

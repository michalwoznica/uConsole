# Stage 9B — pacman-managed uConsole rootfs integration

**Status:** complete; pacman-managed rootfs integration validation passed.

## Goal

Take the authenticated Stage 9A Arch Linux ARM 2026.08 Raspberry Pi AArch64
rootfs and prove the custom uConsole kernel can replace the stock boot path
while keeping pacman's package database consistent.

This remains a build/integration checkpoint. It does not create a partitioned
microSD image.

## Exact stock transition

Stage 9A observed:

- `linux-aarch64`;
- `uboot-raspberrypi`;
- `firmware-raspberrypi`;
- `raspberrypi-bootloader`;
- `mkinitcpio`;
- the normal `linux-firmware*` packages.

The project `linux-uconsole` package follows Arch Linux ARM's `linux-rpi`
packaging shape and conflicts with both `linux-aarch64` and
`uboot-raspberrypi`.

Stage 9B therefore removes exactly:

- `linux-aarch64`;
- `uboot-raspberrypi`.

It retains:

- `firmware-raspberrypi`;
- `raspberrypi-bootloader`;
- `mkinitcpio`;
- `linux-firmware*`.

The result boots the Raspberry Pi firmware directly into `/boot/kernel8.img`;
U-Boot is no longer part of the intended uConsole boot chain.

## Rootfs authenticity

Stage 9B independently rechecks:

- versioned filename;
- exact byte size;
- published MD5;
- locked SHA-256;
- detached signature;
- exact Arch Linux ARM signing fingerprint.

The authenticated SHA-256 is:

`f10903be472e2662e110f0f7bae2750a30914ce3dc0fcd38ec85d3405d8c8967`

## Rootfs extraction

Unlike Stage 9A's read-only archive audit, Stage 9B needs a real filesystem
tree.

The validation job runs inside a disposable Arch Linux container as root and
extracts the authenticated archive with:

`bsdtar -xpf`

This matches Arch Linux ARM's guidance to extract rootfs archives as root so
ownership, ACLs and extended attributes can be preserved.

## Real pacman package

Stage 9B does not copy the Stage 8 package root by hand.

It stages the authoritative `linux-uconsole` PKGBUILD and runs real Arch
`makepkg` on x86_64 with:

- `CARCH=aarch64`;
- `ARCH=arm64`;
- `CROSS_COMPILE=aarch64-linux-gnu-`;
- all available runner CPUs by default.

The resulting package must be a real:

`linux-uconsole-6.18.60-1-aarch64.pkg.tar.*`

Its `.PKGINFO` must declare the expected architecture, dependencies and
conflicts before it can touch the rootfs.

## Pacman target mutation

The host/container pacman operates on the extracted ARM rootfs with:

- `--sysroot <rootfs>`;
- `--arch aarch64`.

Pacman documents `--sysroot` specifically for operating on mounted/guest
systems and `--arch` for overriding the target architecture.

AArch64 package scriptlets and ALPM hooks are intentionally not executed in
Stage 9B:

- package scriptlets are disabled with `--noscriptlet`;
- target hook directories are temporarily moved aside for the two
  transactions and restored afterward.

This means Stage 9B validates package files/database composition without
requiring QEMU user emulation.

Initramfs generation, if required by the final boot design, belongs to the
later image/boot checkpoint.

## Package transaction

1. remove `linux-aarch64` and `uboot-raspberrypi`;
2. install the real `linux-uconsole` package as explicit;
3. restore target ALPM hook directories;
4. install the project-owned `/boot/config.txt` from
   `config-uconsole-cm4.txt`.

The boot config remains image policy and is deliberately not owned by
`linux-uconsole`.

## Validation

Stage 9B requires:

- `linux-uconsole 6.18.60-1` registered;
- `linux-aarch64` absent;
- `uboot-raspberrypi` absent;
- firmware, Raspberry Pi bootloader, mkinitcpio and linux-firmware retained;
- `pacman -Dk` local database consistency;
- `pacman -Qk linux-uconsole`;
- `/boot/kernel8.img`;
- CM4 DTB;
- uConsole DTBO;
- `6.18.60-1-uconsole` modules;
- mkinitcpio preset;
- project boot config byte-for-byte installed as `/boot/config.txt`;
- `/boot/kernel8.img` owned by `linux-uconsole`;
- `/boot/config.txt` not package-owned;
- U-Boot `boot.txt`/`boot.scr` absent.

## Boundary

Stage 9B does not:

- generate an initramfs under AArch64 emulation;
- choose a final root partition UUID;
- create filesystems or partition tables;
- create a disk image;
- flash microSD;
- boot physical hardware.

Those remain later stages.

## Completion criterion

Stage 9B is complete only when:

`Validate Arch rootfs uConsole integration`

passes.

## Final Stage 9B result

The `Validate Arch rootfs uConsole integration` workflow completed
successfully.

This proves the complete Stage 9B contract:

1. the exact pinned 2026.08 Arch Linux ARM Raspberry Pi AArch64 rootfs is
   re-authenticated;
2. the locked SHA-256 matches;
3. the rootfs is extracted as root in the disposable Arch build container;
4. the authoritative `linux-uconsole` PKGBUILD is staged;
5. a real `aarch64` pacman package is cross-built successfully with makepkg;
6. package metadata identifies `linux-uconsole 6.18.60-1`, architecture
   `aarch64`, expected dependencies and expected conflicts;
7. target-root pacman sees the Stage 9A stock package state;
8. `linux-aarch64` and `uboot-raspberrypi` are removed;
9. `linux-uconsole` is installed and registered as explicit;
10. `firmware-raspberrypi`, `raspberrypi-bootloader`, `mkinitcpio` and
    `linux-firmware` remain installed;
11. target pacman database consistency passes;
12. `pacman -Qk linux-uconsole` passes;
13. `/boot/kernel8.img`, CM4 DTB and uConsole DTBO are installed;
14. `/usr/lib/modules/6.18.60-1-uconsole` exists;
15. the uConsole mkinitcpio preset is installed;
16. project boot policy is installed byte-for-byte as `/boot/config.txt`;
17. `/boot/kernel8.img` is owned by `linux-uconsole`;
18. `/boot/config.txt` remains image-policy-owned rather than package-owned;
19. U-Boot `boot.txt`/`boot.scr` residue is absent.

Stage 9B is complete.

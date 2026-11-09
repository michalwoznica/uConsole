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

Stage 10 result: **PASS**. The first complete partitioned uConsole Arch image
was built, populated, filesystem-checked, compressed, checksummed, manifested
and uploaded as a CI artifact.

## Stage 11 console-first usability baseline

Physical validation showed that the minimal upstream rootfs lacks several
command-line tools needed both for practical administration and for uConsole
hardware validation. The final image therefore installs the packages listed in
`rootfs/uconsole-base-packages.txt`.

NetworkManager is the default manager for normal network interfaces. The image
enables `NetworkManager.service`, keeps `systemd-resolved` for DNS, wires
`/etc/resolv.conf` to the resolved stub, and disables systemd-networkd services.
This provides persistent console networking through `nmcli`/`nmtui` without
requiring a graphical environment.

The image also sets kernel console logging to level 3 so routine device/kernel
messages remain in logs instead of overwriting the interactive tty.

The Stage 10 rootfs builder uses host-side `pacman --sysroot` from inside a
disposable x86_64 Docker container. That builder invocation disables only
pacman's filesystem download sandbox because GitHub-hosted Docker cannot apply
the Landlock ruleset to the mounted target sysroot. Package signatures remain
verified. Before the cross-architecture transaction, the builder initializes a
temporary keyring at the staged target's normal `/etc/pacman.d/gnupg` path and
populates it from the Arch and authenticated Arch Linux ARM distribution trust
roots. This is the keyring path visible to pacman while operating inside the
`--sysroot`. The stock `linux-aarch64` and `uboot-raspberrypi` packages are
excluded from the full userspace upgrade because they are replaced by
`linux-uconsole` immediately afterward.

The temporary build keyring contains generated local private signing material,
so the builder deletes the entire target GPG directory after all pacman
transactions and package-database checks finish.
`uconsole-pacman-keyring-init.service` then runs once on first boot, before the
login console, to initialize a unique local pacman keyring and populate the
packaged Arch and Arch Linux ARM trust roots. The booted uConsole therefore
retains normal package-signature verification and normal pacman sandboxing
backed by the uConsole kernel's enabled Landlock LSM.

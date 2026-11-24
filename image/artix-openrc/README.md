# Artix / OpenRC image target

This target provides an Artix Linux userspace with OpenRC for the uConsole.

The target reuses the shared uConsole kernel, device-tree, Raspberry Pi boot
policy, hardware support, and distro-neutral image-building helpers used by the
Arch Linux ARM target. Artix-specific code is limited to userspace integration
that genuinely differs from Arch/systemd.

The shared kernel package definition is `../shared/packages/linux-uconsole/`.

## Upstream userspace source

The aarch64 userspace bootstrap comes from the ARMtix OpenRC rootfs. ARMtix is
an implementation/provenance detail of the ARM target; the public-facing image
name remains **Artix Linux / OpenRC**.

The exact audited upstream archive is pinned in `rootfs.lock`:

```text
armtix-openrc-20260921.tar.xz
SHA-256: 250abf136930f5c7d4ba1a6d2b9b56f6b32acb072e05ccb4b6ab7aa23b834699
```

The lock was established from the publisher's checksum metadata. Builds verify
the exact pinned size and SHA-256 before extraction.

## Raspberry Pi support package inputs

`rpi-support.lock` records the exact Raspberry Pi firmware and bootloader
package versions proven compatible with the pinned ARMtix rootfs and the shared
`linux-uconsole` package.

The rootfs composer does not acquire those packages itself. Their exact package
payloads are supplied explicitly by the caller, and the composer verifies their
embedded package name, version, and architecture before installation.

## Rootfs composition

`scripts/build-artix-openrc-rootfs.sh` prepares the first Artix integration
layer. It:

- verifies and extracts the pinned ARMtix/OpenRC rootfs;
- removes the generic ARMtix regular/LTS kernels and headers;
- installs the supplied Raspberry Pi firmware/bootloader payloads;
- installs the shared `linux-uconsole` package;
- removes generated residue from the removed generic kernels;
- regenerates module dependency metadata for the uConsole kernel;
- installs the shared uConsole `config.txt`, console sysctl policy, and
  brightness-key handler;
- validates the pacman database, kernel/DTB/overlay payload, Raspberry Pi boot
  firmware, modules, and uConsole drivers;
- requires the OpenRC init target and runlevel state to remain unchanged.

This rootfs checkpoint intentionally does **not** configure NetworkManager,
Bluetooth, elogind policy, DNS, final `cmdline.txt`/`fstab`, or final image
identity.

## Current status

The kernel/hardware-integrated Artix rootfs composer is implemented. The next
work is Artix/OpenRC userspace service integration, followed by target image
identity/layout and final image assembly.

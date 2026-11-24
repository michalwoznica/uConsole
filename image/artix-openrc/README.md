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

This base rootfs checkpoint intentionally does **not** configure networking,
Bluetooth, elogind policy, final `cmdline.txt`/`fstab`, or final image identity.

## Networking integration

`networking.lock` pins the exact top-level ARMtix aarch64 NetworkManager package
identities used by this target. The complete dependency closure is supplied by
the caller as an offline package directory; every supplied payload must be
`aarch64` or `any`, and the configurator verifies the locked `networkmanager`
and `networkmanager-openrc` identities before installation.

`scripts/configure-artix-openrc-networking.sh` applies only the Artix/OpenRC
networking policy to an already kernel-integrated rootfs. It:

- installs the caller-supplied offline NetworkManager package closure;
- disables the upstream `dhcpcd` service without removing its package;
- enables the OpenRC `NetworkManager` service in the default runlevel;
- keeps standalone `wpa_supplicant` disabled while retaining its package for
  NetworkManager's Wi-Fi backend;
- preserves the existing `dbus` service state;
- installs `10-uconsole-dns.conf` with `dns=default` and `rc-manager=file`, so
  NetworkManager writes active-connection nameservers directly to the regular
  `/etc/resolv.conf`;
- proves that the only OpenRC runlevel change is the intended
  `dhcpcd` -> `NetworkManager` handoff.

The networking configurator does not start target-architecture services during
the cross-architecture build. Runtime Wi-Fi/DHCP/DNS behavior remains a
physical-validation item.

## Bluetooth integration

`bluetooth.lock` pins the exact top-level ARMtix aarch64 BlueZ package
identities used by this target: `bluez`, `bluez-utils`, and `bluez-openrc`. The
complete dependency closure is supplied by the caller as an offline package
directory; every supplied payload must be `aarch64` or `any`, and the
configurator verifies all three locked identities before installation.

`scripts/configure-artix-openrc-bluetooth.sh` applies only the Artix/OpenRC
Bluetooth service policy to an already kernel-integrated rootfs. It:

- installs the caller-supplied offline BlueZ package closure;
- keeps the existing `dbus` default-runlevel service unchanged;
- enables the OpenRC `bluetoothd` service in the default runlevel;
- verifies `bluetoothd`, `bluetoothctl`, and `btmgmt` are present;
- proves that the only OpenRC runlevel change is addition of `bluetoothd`.

The accepted Arch Linux ARM target has already physically validated the same
shared kernel/hardware path with normal BlueZ controller discovery, so this
Artix layer does not add a speculative `hciuart`/`pi-bluetooth` service. The
Bluetooth configurator does not start target-architecture services during the
cross-architecture build. Artix controller/radio discovery remains a physical
validation item.

## Current status

The kernel/hardware-integrated rootfs composer, Artix/OpenRC NetworkManager
policy layer, and Artix/OpenRC Bluetooth service layer are implemented.
Elogind-specific power-button policy, target image identity/layout, host-side
package acquisition and final image assembly remain later checkpoints.

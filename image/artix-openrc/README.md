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
Bluetooth, elogind power-button policy, final `cmdline.txt`/`fstab`, or final
image identity.

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

## Elogind power-button integration

The pinned ARMtix/OpenRC rootfs already contains `elogind` and
`elogind-openrc`, with the native OpenRC `/etc/init.d/elogind` service enabled
in the `boot` runlevel. No additional elogind package transaction or service
enablement is required for this checkpoint. The pinned rootfs archive itself
therefore fixes the elogind package payload used by the target.

`scripts/configure-artix-openrc-elogind.sh` applies only the uConsole
power-button policy to an already integrated Artix rootfs. It:

- requires the existing OpenRC `elogind` boot-runlevel service and `dbus`
  default-runlevel service to be present and unchanged;
- installs `99-uconsole-power.conf` under `/etc/elogind/logind.conf.d/`;
- sets only `HandlePowerKey=ignore`, matching the accepted Arch Linux ARM
  short-press behavior;
- leaves long-press, suspend, lid, idle, and other elogind policies at their
  upstream defaults;
- proves that no OpenRC runlevel link changes during this integration.

This is elogind-native configuration. It does not create, enable, or depend on
a systemd `.service` unit. Runtime power-key handling remains a physical
validation item on the Artix image.


## Runtime services integration

`runtime.lock` pins the exact top-level ARMtix aarch64 runtime package
identities added after physical validation: `evtest`, `chrony`, and
`chrony-openrc`. It also records the stock ARMtix `ntp` / `ntp-openrc` package
names that this checkpoint intentionally replaces. The caller supplies the new
runtime dependency closure as an offline package directory, and the configurator
verifies every supplied payload is for `aarch64` or `any` before installation.

`scripts/configure-artix-openrc-runtime.sh` applies the two runtime fixes proven
necessary on physical hardware:

- installs `evtest`, which the shared
  `/usr/lib/uconsole/uconsole-brightness-keys` handler uses to consume
  `KEY_BRIGHTNESSDOWN` / `KEY_BRIGHTNESSUP` events;
- installs a native OpenRC `uconsole-brightness-keys` service and enables it in
  the default runlevel;
- removes the `hwclock` boot-runlevel service because physical validation
  showed that this CM4/uConsole exposes no `/dev/rtc*`;
- enables OpenRC `swclock` in the boot runlevel so shutdown time is preserved
  across RTC-less boots;
- verifies the pinned ARMtix stock NTP service files (`sntp`, `ntp-client`, and
  `ntpd`) are present and disabled, removes the stock `ntp` + `ntp-openrc`
  time-sync stack, then installs `chrony` + `chrony-openrc` and enables the
  native OpenRC `chrony` service in the default runlevel for network time correction;
- installs an RTC-less chrony client policy using the global `pool.ntp.org`
  pool with `iburst` and `makestep 1.0 3`, so a clock that starts far from real
  time can be stepped promptly once NTP becomes reachable;
- overrides only the packaged OpenRC service startup policy needed by this
  target: the `chrony` OpenRC service does not hard-depend on OpenRC `net` and uses the packaged
  non-blocking `FAST_STARTUP` path. This lets it remain running on a fresh image
  before Wi-Fi has been configured and retry source resolution after networking
  appears;
- preserves the existing ARMtix boot-runlevel `esysusers` and
  `etmpfiles-setup` services, which create chrony's packaged system user and
  runtime/state directories before the default runlevel starts the `chrony` service;
- proves that the OpenRC runlevel delta is exactly `hwclock` -> `swclock` plus
  addition of `chrony` and `uconsole-brightness-keys`; the pinned source has no
  stock NTP service enabled in a runlevel.

No timezone, country, locale, or systemd service policy is introduced.

## Final image identity and assembly

`image-layout.lock` defines an Artix-specific deterministic DOS/MBR identity
while intentionally retaining the same proven 8 GiB two-partition geometry as
the Arch Linux ARM target. Artix uses its own disk identifier, PARTUUIDs,
filesystem UUID/labels, `cmdline.txt`, and `/etc/fstab`; the low-level partition,
filesystem, rootfs-copy, compression and checksum mechanics remain shared.

`scripts/finalize-artix-openrc-rootfs.sh` is the final userspace gate before
image construction. It verifies the completed NetworkManager, Bluetooth,
elogind, brightness, RTC-less clock/time-sync, D-Bus and OpenRC runlevel state,
installs the deterministic Artix
`cmdline.txt` and `/etc/fstab`, and proves that finalization itself does not
change any OpenRC runlevel link.

`scripts/build-artix-openrc-image.sh` treats that finalized rootfs as read-only
input. It builds and validates the partitioned image, checks the copied boot,
kernel, module, OpenRC and service-policy state while mounted, performs FAT/ext4
filesystem checks after unmount, and emits the compressed `.img.zst`, checksum
files and manifest. As with the accepted Arch image, the raw 8 GiB image is
removed after successful compression.

`scripts/build-artix-openrc.sh` is the host-side orchestration entry point. It
requires the exact `linux-uconsole`, Raspberry Pi firmware and bootloader
payloads plus caller-supplied offline NetworkManager, BlueZ, and runtime
dependency closures. An already-downloaded pinned ARMtix rootfs may be supplied
through
`UCONSOLE_ARTIX_ROOTFS_ARCHIVE`; otherwise the rootfs composer downloads the
pinned archive in its disposable container. The orchestrator intentionally does
not resolve or substitute package versions: package acquisition/provenance
remains explicit and the existing integration scripts reject identities that do
not match the committed locks.

The final image remains console-only. This checkpoint does not add a graphical
environment, systemd service management, timezone/country assumptions, or any
new runtime policy beyond the already validated Artix integration layers.

A complete local assembly is invoked as:

```text
scripts/build-artix-openrc.sh \
  /path/to/linux-uconsole.pkg.tar.zst \
  /path/to/firmware-raspberrypi.pkg.tar.xz \
  /path/to/raspberrypi-bootloader.pkg.tar.xz \
  /path/to/networkmanager-package-closure \
  /path/to/bluez-package-closure \
  /path/to/runtime-package-closure
```

Each closure directory should contain only the package payloads resolved for
that integration layer. The configurators validate package architecture and the
committed top-level package identities before performing their offline
transactions.

## Current status

The first complete Artix/OpenRC image was built successfully and physically
validated on the uConsole. Boot/console, Wi-Fi/NetworkManager, DNS, Bluetooth,
battery/charging, power-button policy, analog audio/headphone switching and
clean power-off all passed. Physical validation also identified two concrete
runtime defects: the brightness handler lacked its `evtest` dependency/service,
and the RTC-less device was incorrectly using `hwclock`, leaving the system at
1970 after reboot. This checkpoint adds the corresponding OpenRC-native fixes;
a rebuilt image and focused regression validation of brightness keys plus clock
behavior remain required before the Artix target can be treated as
release-ready.

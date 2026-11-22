# uConsole Arch Linux CM4 — v1.0.0

**Status:** prepared first stable public release  
**Target:** ClockworkPi uConsole + Raspberry Pi CM4 Lite, original/2024 display  
**Project version:** `v1.0.0`

`v1.0.0` is the version of this project/image. It is not an Arch Linux ARM
release date. The accepted rootfs lineage is the pinned Arch Linux ARM
`2026.08` input recorded by the repository.

## Release artifact

Publish exactly this filename:

```text
uconsole-archlinuxarm-v1.0.0-cm4.img.zst
```

It must be a rename/copy of the exact Stage 12F image that passed Stage 12G
physical validation and Stage 12H promotion. Do not recompress or rebuild it.

Checksums:

```text
compressed SHA-256 d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19
raw image SHA-256 a2daeb466eae193917da5405adf52d60cadb55d029278502c407bbedd4aa0212
kernel package SHA-256 e4eb51edf12d7022ee96a5599ac7643dc665afd02aad1ecdd074c3e108674206
```

The later Stage 12H locked-rebuild image with compressed SHA-256
`dd2538723b8a1bc0f7ccbffabf07ab0811aa4b55db5ea85c2198e962b3672dcf`
is reproducibility evidence only and is **not** the v1.0.0 release artifact.

## System identity

```text
baseline_id=archlinuxarm-stage12h-2026-11-22
rootfs_release=2026.08
kernel_release=6.18.64-1-uconsole
rpi_linux_commit=a40f735325391b1705161b07f36ed45e1bf04521
final_inventory_sha256=151fd2dcead053dd748b3d6b3993f776df786ca40510bb41f43592be2c629666
```

## Validated hardware/functionality

Physically validated on:

- ClockworkPi uConsole;
- Raspberry Pi CM4 Lite (`104000`, no eMMC);
- original/2024 uConsole display revision;
- microSD boot/storage.

Validated functionality includes:

- boot and visible console;
- CWU50 display and OCP8178 backlight;
- brightness keys;
- keyboard input;
- NetworkManager Wi-Fi, IPv4 and DNS;
- package management;
- Bluetooth discovery;
- USB storage;
- AXP20x/AXP221 battery reporting;
- built-in speaker audio;
- headphone audio and live speaker/headphone switching;
- short power-button press policy;
- clean reboot and poweroff.

The image is intentionally console-only; no X11/Wayland desktop environment is
installed by this project.

## Verify the download

```sh
printf '%s  %s\n' \
  d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19 \
  uconsole-archlinuxarm-v1.0.0-cm4.img.zst \
  | sha256sum -c -
```

Expected result:

```text
uconsole-archlinuxarm-v1.0.0-cm4.img.zst: OK
```

## Flash on Linux

Identify the correct **whole microSD device** first. The command below destroys
all existing data on the selected device.

```sh
zstd -dc uconsole-archlinuxarm-v1.0.0-cm4.img.zst \
  | sudo dd of=/dev/sdX bs=16M iflag=fullblock oflag=direct,sync status=progress
sudo blockdev --flushbufs /dev/sdX
```

Replace `/dev/sdX` with the actual microSD device, not a partition such as
`/dev/sdX1`.

## First login

The image builder does not create project-specific accounts or passwords. It
retains the standard accounts from the pinned Arch Linux ARM rootfs:

```text
user:     alarm
password: alarm

root password: root
```

Change the default passwords immediately after first login.

## Maintenance model

`main` is the stable Arch/publication branch. Accepted updates are not taken
from live upstream state automatically. Stage 12 requires discovery,
compatibility validation, exact candidate construction, physical validation,
explicit promotion, and an offline locked-rebuild proof before a new baseline
can replace the accepted release.

ARMtix/Artix OpenRC development is intentionally separate and will begin on a
dedicated development branch after the v1.0.0 public release is confirmed.

## Publication checklist

Before announcing the release:

1. tag the exact stable `main` commit as `v1.0.0`;
2. make the repository public;
3. create the GitHub release from tag `v1.0.0`;
4. upload the renamed exact validated image without recompressing it;
5. publish/verify the compressed SHA-256 above;
6. verify the repository, release page and image download as a public/logged-out
   user.

## Licensing

The repository is multi-license. Project tooling/documentation defaults to MIT,
while kernel-facing files and upstream sources retain GPL/upstream licensing.
See `LICENSING.md` and `docs/PROVENANCE.md`.

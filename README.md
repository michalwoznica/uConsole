# uConsole Arch Linux CM4

Reproducible Arch Linux ARM image project for the ClockworkPi uConsole with a
Raspberry Pi Compute Module 4 Lite.

## Stable Arch Linux ARM baseline

The Arch Linux ARM target is complete through Stage 12 and has been physically
validated on the target uConsole hardware.

```text
baseline_id=archlinuxarm-stage12h-2026-11-22
rootfs_release=2026.08
kernel_release=6.18.64-1-uconsole
rpi_linux_commit=a40f735325391b1705161b07f36ed45e1bf04521
kernel_package_sha256=e4eb51edf12d7022ee96a5599ac7643dc665afd02aad1ecdd074c3e108674206
image_raw_sha256=a2daeb466eae193917da5405adf52d60cadb55d029278502c407bbedd4aa0212
image_compressed_sha256=d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19
final_inventory_sha256=151fd2dcead053dd748b3d6b3993f776df786ca40510bb41f43592be2c629666
```

The compressed image identified by
`d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19`
is the exact Stage 12F image that passed the Stage 12G physical regression and
was promoted by Stage 12H. A later offline locked rebuild produced the same
accepted package inventory but intentionally does not replace that physically
tested image as the release artifact.

## Target hardware

- ClockworkPi uConsole
- Raspberry Pi CM4 Lite (`104000`, no eMMC)
- original/2024 uConsole display revision
- microSD boot/storage
- console-only Arch Linux ARM userspace

## Hardware support

The project uses the official Raspberry Pi `rpi-6.18.y` kernel lineage plus a
small auditable uConsole-specific delta:

1. CWU50 display panel support
2. OCP8178 backlight support
3. uConsole CM4 device-tree overlay
4. minimal AXP20x/AXP221 battery support delta
5. headphone/speaker amplifier switching

The physically validated Arch image covers boot/display, brightness controls,
keyboard input, Wi-Fi and DNS, package management, Bluetooth discovery, USB
storage, battery reporting, speaker/headphone audio and live switching, power
button policy, reboot, and shutdown.

## Reproducibility and update policy

The repository is a build recipe rather than a forked Linux source tree.
Authoritative source and release identities are recorded in repository locks.
Stage 12 defines two maintenance modes:

- `locked-rebuild` reconstructs the accepted baseline from preserved inputs with
  no live package or kernel refresh;
- `update-candidate` deliberately evaluates newer upstream inputs without
  changing the accepted baseline until the candidate has passed compatibility,
  image-build, physical-validation, and explicit-promotion gates.

The accepted Stage 12H baseline was reproduced offline with an exact final
package-inventory match. Byte-identical disk-image output is not required by the
project reproducibility contract.

See `docs/STAGE12_UPDATE_REBUILD.md` for the complete maintenance contract and
`docs/UCONSOLE_ARCH_PROJECT_HANDOFF.md` for the implementation/validation
history.

## Multi-distro direction

The kernel and hardware-support layer is intentionally distro-neutral. Arch
Linux ARM is the first completed target. ARMtix/Artix with OpenRC is the next
planned userspace target under `image/armtix-openrc/`.

`main` is the stable Arch/publication baseline. Future ARMtix/Artix development
must occur on a dedicated development branch and should not change the stable
Arch baseline on `main` until that target is independently validated and ready
for promotion.

## First public release — v1.0.0

The first stable public project release is prepared as **`v1.0.0`**. The
version identifies this project release; it does **not** imply that the bundled
Arch Linux ARM userspace is a November 2026 upstream distribution snapshot.
The accepted rootfs lineage remains the pinned Arch Linux ARM `2026.08` input
recorded by the repository.

The release artifact must be the exact physically validated Stage 12F/12G
compressed image, renamed for publication without recompressing or rebuilding:

```text
uconsole-archlinuxarm-v1.0.0-cm4.img.zst
SHA-256 d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19
```

After decompression, the raw image SHA-256 is:

```text
a2daeb466eae193917da5405adf52d60cadb55d029278502c407bbedd4aa0212
```

The project does not customize the accounts inherited from the pinned Arch
Linux ARM rootfs. The standard initial local-console credentials are user
`alarm` with password `alarm`, and the root password is `root`. Change these
credentials immediately after first login.

To flash on Linux, replace `/dev/sdX` with the **whole microSD device** (not a
partition). The target device is overwritten completely:

```sh
zstd -dc uconsole-archlinuxarm-v1.0.0-cm4.img.zst \
  | sudo dd of=/dev/sdX bs=16M iflag=fullblock oflag=direct,sync status=progress
sudo blockdev --flushbufs /dev/sdX
```

See `docs/RELEASE_V1.0.0.md` for the release notes, verification details,
supported hardware and publication checklist.

`main` remains the stable Arch/publication branch. ARMtix/Artix OpenRC work
will begin only after the public `v1.0.0` release is published, on a dedicated
development branch.

## License

The repository contains material under more than one license. The root MIT
license is the default for project-authored material without a more specific
notice; kernel-facing files and fetched third-party sources retain their
explicit/upstream licenses. See `LICENSING.md`.

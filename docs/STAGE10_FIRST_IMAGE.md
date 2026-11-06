# Stage 10 — first reproducible partitioned microSD image

**Status:** image construction complete; physical integration defects corrected;
corrected CI artifact and untouched-media boot/display revalidation PASS.

## Goal

Construct the first real microSD image artifact from the already-proven
components:

- authenticated Arch Linux ARM 2026.08 Raspberry Pi AArch64 rootfs;
- real cross-built `linux-uconsole` pacman package;
- completed Stage 9B package transition;
- completed Stage 9C boot contract.

The original image-construction boundary stopped before physical flashing and
boot testing. This report now also records the bounded physical-validation
correction and its successful corrected-image revalidation.

## Runner architecture

The workflow uses the standard `ubuntu-24.04` GitHub-hosted VM rather than
`ubuntu-slim`.

Image construction requires:

- loop devices;
- partition scanning;
- FAT/ext4 filesystem creation;
- mounting filesystems.

The standard Ubuntu runner is a VM and supports normal privileged host
operations through `sudo`. The slim runner is intentionally not used for this
stage.

The expensive kernel package build still uses:

`JOBS=${JOBS:-$(nproc)}`

No explicit CPU cap is introduced.

## Rootfs/package construction

`scripts/build-stage10-rootfs.sh` runs inside a disposable
`archlinux:base-devel` Docker container.

It repeats the proven Stage 9B contract rather than consuming an opaque prior
workflow artifact:

1. fetch exact pinned versioned rootfs;
2. verify exact size;
3. verify published MD5;
4. verify locked SHA-256;
5. verify detached OpenPGP signature against the pinned Arch Linux ARM
   fingerprint;
6. extract rootfs as root;
7. verify stock package state;
8. cross-build a real `aarch64` `linux-uconsole` package through makepkg;
9. suppress target ALPM hooks and target-AArch64 `ldconfig`;
10. remove `linux-aarch64` and `uboot-raspberrypi`;
11. install `linux-uconsole`;
12. restore transaction machinery;
13. install final `config.txt`, `cmdline.txt` and `/etc/fstab`;
14. verify package DB, installed files and boot artifacts.

The integrated rootfs is emitted into the Stage 10 workspace.

## Concrete image geometry

Stage 10 extends `image-layout.lock` with concrete geometry.

Raw image size:

`8589934592` bytes (8 GiB)

Logical sector size:

`512` bytes

DOS/MBR disk identifier:

`0x55434f4e`

Partition 1 — boot:

- start sector: `8192`;
- size: `1048576` sectors (512 MiB);
- type: `0x0c` / FAT32 LBA;
- bootable flag set;
- PARTUUID: `55434f4e-01`.

Partition 2 — root:

- start sector: `1056768`;
- extends to the end of the image;
- type: `0x83` / Linux;
- PARTUUID: `55434f4e-02`.

The partition table is written with `sfdisk` using an explicit DOS label ID.

## Filesystem identities

Boot filesystem:

- FAT32;
- label `UCONBOOT`;
- volume ID `55434F01`.

Root filesystem:

- ext4;
- label `UCONSOLEROOT`;
- UUID `55434f4e-534f-4c45-8000-000000000002`;
- no reserved-root percentage;
- lazy inode/journal initialization disabled during image creation.

Mount policy continues to use PARTUUID, not filesystem UUID.

## Population

The ext4 root filesystem is populated with numeric ownership, hard links,
ACLs and xattrs preserved.

`/boot` is populated separately onto FAT. FAT cannot carry normal Unix
ownership/mode/xattr semantics, so boot files are copied as ordinary files
with symlinks dereferenced.

This mirrors the conventional Raspberry Pi model where boot firmware files
live on FAT and Linux root data lives on ext4.

## Capacity

Before copying root data, the builder compares the integrated rootfs size
against the actual ext4 free space and requires at least 512 MiB of remaining
headroom.

If the pinned rootfs grows beyond the current 8 GiB image contract, Stage 10
fails explicitly rather than silently changing image geometry.

## Validation

The image builder verifies:

- exact MBR disk identifier;
- loop-created partition devices;
- exact boot/root PARTUUIDs;
- FAT/ext4 types and labels;
- fixed ext4 UUID;
- kernel image;
- CM4 DTB;
- uConsole DTBO;
- module tree;
- final `config.txt`;
- final `cmdline.txt`;
- final `/etc/fstab`;
- installed `linux-uconsole` local package DB;
- no stock `linux-aarch64`/`uboot-raspberrypi` DB residue;
- no U-Boot boot-script residue;
- FAT filesystem consistency;
- ext4 filesystem consistency.

## Artifact

The raw image is 8 GiB and is not uploaded directly.

After validation it is compressed with zstd using all CPUs:

`uconsole-archlinuxarm-2026.08-cm4.img.zst`

The workflow also emits:

- raw-image SHA-256;
- compressed-image SHA-256;
- exact `linux-uconsole` package used;
- a machine-readable manifest containing source pins, package checksum,
  image checksums, partition identity and boot-policy facts.

The workflow uploads these as:

`uconsole-archlinuxarm-stage10`

with seven-day artifact retention.

## Reproducibility scope

Stage 10 provides a deterministic **construction recipe and disk identity**:

- pinned rootfs bytes;
- pinned signing identity;
- pinned kernel source;
- fixed package source/config;
- fixed partition table;
- fixed PARTUUIDs;
- fixed filesystem identities;
- fixed boot/root policy.

The first Stage 10 image is not yet claimed to be byte-for-byte reproducible
across independent builds. Filesystem creation timestamps, pacman transaction
timestamps and package/build metadata can still make raw-image checksums vary
between runs.

The manifest records exact checksums for each produced artifact.

Bit-for-bit reproducibility can be tightened later if it becomes valuable;
it is not a blocker for the first physical uConsole validation.

## Boundary

Stage 10 does not:

- flash a microSD card;
- boot a physical uConsole;
- resize the root filesystem on first boot;
- customize accounts/passwords;
- add user-identifying information.

## Completion criterion

Stage 10 is complete only when:

`Build first uConsole Arch microSD image`

passes and publishes the compressed image artifact.

## First CI correction — sfdisk sector-size compatibility

The first Stage 10 image-construction run reached the host image builder after
the authenticated rootfs/package preparation step, then failed before
partition creation because the Ubuntu 24.04 runner's sfdisk rejected the
`--sector-size` command-line option.

Correction:

1. attach the sparse raw image to a loop device with an explicit 512-byte
   logical sector size;
2. verify that size with `blockdev --getss`;
3. run sfdisk against the loop block device without the unsupported option;
4. keep `sector-size: 512` in the sfdisk input header as explicit script
   metadata;
5. verify the DOS disk identifier;
6. detach and reattach with both `--sector-size 512` and `--partscan`;
7. verify the sector size again before formatting partitions.

No image geometry, disk identifier, PARTUUID, filesystem identity, boot policy,
kernel package, rootfs input or CPU policy changed.

## Second CI correction — FAT volume label length

The second Stage 10 image-construction run proved the host-side partitioning
path: sparse image creation, explicit 512-byte loop sectors, deterministic
DOS/MBR partitioning, exact disk identifier, exact partition geometry, and
detach/reattach with partition scanning all reached the filesystem step.

The run then failed at FAT filesystem creation because the configured boot
volume label `UCONSOLEBOOT` contained 12 characters. FAT volume labels are
limited to 11 characters.

Correction:

- boot FAT label changed to `UCONBOOT` (8 characters).

The label is informational only. The boot/root mount contract uses PARTUUID,
so no `cmdline.txt`, `/etc/fstab`, partition identity or boot behavior changes.
All partition geometry, disk/PARTUUID identity, root filesystem identity,
kernel/rootfs/package inputs, and boot policy remain unchanged.

## Final Stage 10 result

The corrected `Build first uConsole Arch microSD image` workflow completed
successfully.

Final proven contract:

- authenticated Arch Linux ARM 2026.08 rootfs preparation: PASS;
- real aarch64 `linux-uconsole` package build: PASS;
- Stage 9B package transition reproduction: PASS;
- final Stage 9C boot/root policy installation: PASS;
- sparse 8 GiB raw image creation: PASS;
- explicit 512-byte loop logical-sector size: PASS;
- deterministic DOS/MBR partition-table creation: PASS;
- disk identifier `0x55434f4e`: PASS;
- boot and root partition geometry: PASS;
- loop detach/reattach with partition scanning: PASS;
- FAT32 boot filesystem creation: PASS;
- ext4 root filesystem creation: PASS;
- boot PARTUUID `55434f4e-01`: PASS;
- root PARTUUID `55434f4e-02`: PASS;
- boot FAT label `UCONBOOT`: PASS;
- root label `UCONSOLEROOT`: PASS;
- fixed root filesystem UUID: PASS;
- rootfs capacity/headroom validation: PASS;
- ext4 root population preserving Unix metadata: PASS;
- FAT boot population: PASS;
- kernel image / DTB / uConsole DTBO / modules: PASS;
- final `config.txt`, `cmdline.txt`, and `/etc/fstab`: PASS;
- `linux-uconsole` local package database record: PASS;
- no stock `linux-aarch64` / `uboot-raspberrypi` package residue: PASS;
- no U-Boot boot-script residue: PASS;
- FAT filesystem consistency check: PASS;
- ext4 filesystem consistency check: PASS;
- raw-image SHA-256 generation: PASS;
- zstd image compression and integrity test: PASS;
- compressed-image SHA-256 generation: PASS;
- machine-readable manifest generation: PASS;
- exact `linux-uconsole` package inclusion: PASS;
- workflow artifact upload: PASS.

The original Stage 10 image-construction workflow completed and published its
artifact. Physical validation then exposed the integration defects documented
below. The corrected pipeline required a fresh CI image and untouched-media
physical revalidation before promotion.

## First physical validation — display integration correction

The preserved Stage 10 artifact was flashed unchanged to a physical CM4 Lite
uConsole with the original display revision. The first boot reached Linux but
the display remained black after a brief backlight flash.

A known-good ClockworkPi image booted repeatedly on the same hardware, ruling
out a panel, CM4, backlight or basic power fault.

The bounded investigation established two independent Stage 10 integration
defects:

1. the generated `config.txt` did not assert GPIO9 during firmware handoff;
2. the target rootfs contained `panel-cwu50.ko.xz` and `ocp8178_bl.ko.xz`, but
   the cross-architecture pacman transaction had intentionally suppressed
   target ALPM hooks/scriptlets and therefore also suppressed the normal
   `depmod` hook. The installed module tree had only `modules.builtin`,
   `modules.builtin.modinfo` and `modules.order`; `modules.dep`,
   `modules.alias` and the other generated kmod metadata were absent.

Physical diagnostic evidence before the correction showed:

- the intended `6.18.60-1-uconsole` kernel and root filesystem booted;
- the uConsole overlay applied and `/soc/dsi@7e700000/panel@0` existed;
- `modinfo panel_cwu50` failed with `Module panel_cwu50 not found`;
- no MIPI-DSI device, DRM connector or backlight class device appeared;
- systemd explicitly reported missing `modules.devname`;
- the DSI power dependency remained pending.

The test card was then repaired with only the two required changes:

- `gpio=9=op,dh` in `config.txt`;
- host-side `depmod -b <target-root> 6.18.60-1-uconsole` against the installed
  ARM64 module tree.

After `depmod`, `modinfo` resolved both `panel_cwu50` and `ocp8178_bl` with
their expected Device Tree aliases. The same card then booted successfully to
the Arch Linux ARM login prompt. Live inspection showed the CWU50/OCP8178
modules loaded, VC4/DRM active, a DSI connector present, and the backlight
class device created. The physical display rendered boot output and the login
console correctly.

### Build-pipeline correction

The Stage 10 source now reproduces that proven repair automatically:

- `image/archlinuxarm/boot/config-uconsole-cm4.txt` asserts GPIO9 high as an
  output during firmware boot;
- `scripts/build-stage10-rootfs.sh` explicitly runs host-side `depmod` after
  the cross-architecture pacman transaction and before rootfs validation;
- rootfs validation requires generated module metadata and verifies that
  `panel_cwu50` and `ocp8178_bl` resolve by name with their expected DT aliases;
- `scripts/build-stage10-image.sh` verifies that the dependency/alias metadata
  survives into both the integrated rootfs input and the populated image.

This correction does not change the kernel source, uConsole DT overlay,
partition geometry, PARTUUIDs, filesystem identities, rootfs pin, package
version or direct-root boot policy.

### Corrected-image revalidation result

The corrected pipeline passed the complete revalidation boundary:

1. `Build first uConsole Arch microSD image` passed from the corrected source;
2. the published artifact was preserved and its compressed-image, raw-image
   and kernel-package SHA-256 values matched the manifest;
3. the corrected image was freshly flashed to clean media and was not modified
   afterward;
4. the physical uConsole booted to the visible Arch Linux ARM login console
   without manual `depmod` or boot-config repair;
5. interactive login succeeded;
6. live inspection showed `panel_cwu50` and `ocp8178_bl` loaded, VC4/DRM
   active, a DSI connector present and the backlight class device created.

Corrected Stage 10 physical boot/display validation: **PASS**.

Preserved corrected-artifact identities:

- workflow artifact ZIP SHA-256:
  `27919add8106ca637ae0416f1b473e014734aa1b77300bac50c2c3e1b8c88051`;
- `linux-uconsole-6.18.60-1-aarch64.pkg.tar.zst` SHA-256:
  `ca53afee2b42af14dab64fc31de2f283cd10051867a8d25a05b8069f1dbca1fb`;
- raw image SHA-256:
  `e2ca929b5cf4e9d263ea9fe2705d49e71e2133e463735dc6127a7017fcda8721`;
- compressed image SHA-256:
  `b75f6284503dc7f0ea6266006fb0a8ef18fb162ed1bc81da2e4a107a2821ce99`.

The repeated early CWU50 old-panel/regulator retry messages observed during
boot are transient probe/dependency retries: the panel subsequently binds,
DRM initializes and the console is rendered. They are not treated as a Stage
10 blocker.

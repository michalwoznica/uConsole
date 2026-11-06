# Stage 10 — first reproducible partitioned microSD image

**Status:** implemented; CI validation pending.

## Goal

Construct the first real microSD image artifact from the already-proven
components:

- authenticated Arch Linux ARM 2026.08 Raspberry Pi AArch64 rootfs;
- real cross-built `linux-uconsole` pacman package;
- completed Stage 9B package transition;
- completed Stage 9C boot contract.

This stage still stops before physical flashing/boot testing.

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

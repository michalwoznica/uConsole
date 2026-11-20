# Project scripts

Automation added here should support reproducible source verification, building, validation, packaging, or image creation.

Shared scripts should avoid distro- or init-system-specific assumptions where practical.

Scripts should fail clearly and must not hide important build inputs such as source commit hashes.

## Executable-bit policy

Shell scripts should be committed executable (`100755`) for normal local use.

Checkpoint ZIP handling can lose Unix mode bits in some extraction/repackaging
paths. CI workflows therefore invoke project shell validators explicitly with
`bash ./scripts/<name>.sh` rather than relying on the executable bit. This
prevents archive metadata loss from turning a valid source checkpoint into a
spurious CI `Permission denied` failure.

Stage 7 adds:

- `stage-arch-kernel-package.sh` — create a self-contained Arch makepkg
  workspace without duplicating authoritative project sources in Git;
- `validate-kernel-config-package.sh` — compose the full pinned source tree,
  execute the actual PKGBUILD `prepare()` path, resolve the uConsole kernel
  config, and stop before the Stage 8 full build.

Stage 8 adds:

- `validate-full-kernel-build.sh` — execute the real staged PKGBUILD
  `prepare()`, `build()` and `package()` paths, validate the built kernel
  image/modules/DTBs, apply the uConsole DTBO to the CM4 DTB, and inspect the
  temporary package root.

## CI timeout policy

Long-running kernel/image workflows should use the hosting platform's current
maximum job timeout unless a lower limit is specifically justified.

For GitHub Actions, verify the platform limit before changing workflow
timeouts. At Stage 8 completion, the maximum/default job timeout is 360
minutes, so full kernel/image jobs use `timeout-minutes: 360`.

Stage 9A adds:

- `validate-arch-rootfs-pin.sh` — download the versioned Arch Linux ARM
  Raspberry Pi AArch64 rootfs, validate size/MD5/OpenPGP signature, extract it,
  and report the stock kernel/boot package inventory needed by Stage 9B.

Stage 9B adds:

- `validate-arch-rootfs-integration.sh` — authenticate and extract the pinned
  ARM rootfs, cross-build the real aarch64 `linux-uconsole` package, perform
  the pacman-managed stock-kernel/U-Boot replacement, install boot policy, and
  verify the resulting rootfs/package database.

Stage 9C adds:

- `validate-arch-boot-contract.sh` — validate deterministic PARTUUID identity,
  one-line Raspberry Pi cmdline policy, fstab/config composition and the exact
  pinned kernel's built-in direct-root prerequisites.

Stage 10 adds:

- `build-stage10-rootfs.sh` — authenticate the pinned ARM rootfs, build/install
  the real `linux-uconsole` package, explicitly generate target kmod metadata
  with host-side `depmod` after the hook-suppressed cross-architecture pacman
  transaction, and emit the completed target rootfs;
- `build-stage10-image.sh` — create, populate, validate and compress the
  deterministic partitioned microSD image, including checks that generated
  module dependency/alias metadata survives into the final root filesystem.

## Shared local/CI image build entry point

Stage 11 adds:

- `build-stage10-host.sh` — orchestrate the complete Stage 10 image build from
  a Linux host. GitHub Actions calls it with Docker; local Arch development
  calls the same script with rootful Podman by default. It preserves the
  existing authenticated-rootfs and image-builder contracts and caches a
  completed `linux-uconsole` package by kernel-input hash so post-kernel image
  failures can be retried without recompiling an unchanged kernel.

Local usage is documented in `docs/LOCAL_IMAGE_BUILD.md`.

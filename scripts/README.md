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

## Stage 12 baseline capture

Stage 12C adds:

- `capture-release-baseline.sh` — capture the accepted Stage 11 rootfs→final
  package delta from the retained Stage 10 workspace, preserve the exact target
  package payloads and validated `linux-uconsole` package, reacquire and verify
  the pinned rootfs archive, and emit a hashed baseline input bundle under the
  gitignored `out/baselines/` tree;
- `verify-release-baseline-bundle.sh` — verify bundle identity against
  `release-baseline.lock`, validate all file hashes, and prove that every final
  package delta has a preserved package payload.

The capture script is deliberately fail-closed. It refuses to overwrite an
existing baseline bundle and refuses to fall back to live packages when the
accepted Stage 10 workspace no longer contains an exact required payload.

## Stage 12 locked baseline rebuild

Stage 12C2 adds:

- `build-release-baseline.sh` — rebuild the accepted baseline from the
  project-preserved bundle without live package/kernel refreshes. It verifies
  the bundle against `release-baseline.lock`, requires the existing local
  builder image rather than pulling it, disables container networking, reuses
  the accepted `linux-uconsole` package, and requires the reconstructed final
  package name/version inventory to match the accepted inventory exactly.

Locked rebuild output is isolated under `build/locked-rebuild/` and
`out/locked-rebuild/`; it does not overwrite Stage 10 artifacts.

## Stage 12 read-only update checker

Stage 12D adds:

- `check-updates.sh` — verify that the accepted baseline, rootfs lock, kernel
  source lock and `linux-uconsole` PKGBUILD still agree, then query the
  configured Arch Linux ARM rootfs mirror and Raspberry Pi `rpi-6.18.y` branch
  for newer candidates. The checker never edits locks, downloads build
  payloads, changes package databases or updates the repository. It snapshots
  Git status before/after and fails if repository state changes while it runs.

A candidate being available is informational and returns success. Failure to
query an upstream source reliably is distinct from "no update" and returns a
non-zero status.

Stage 12E adds:

- `run-kernel-update-candidate.sh` — host launcher for Stage 12E. It uses the
  already-local Arch `base-devel` builder image, mounts the repository
  read-only, uses host networking for this deliberately online candidate
  container, installs the current cross-build/toolchain packages only inside
  the disposable container, and records builder/toolchain identity.
- `validate-kernel-update-candidate.sh` — validate one explicitly selected
  newer Raspberry Pi Linux commit in an ignored candidate workspace. Host
  invocation automatically delegates to the container launcher. Inside the
  container it stages a candidate-only PKGBUILD, executes the normal
  patch/config `prepare()` path with `--fuzz=0`, builds/applies the CM4/uConsole
  device trees, and proves Git state is unchanged. It intentionally stops
  before a full kernel or image build.

## Stage 12 real kernel candidate build

Stage 12F adds:

- `build-kernel-update-candidate.sh` — require a matching Stage 12E PASS, build
  the real candidate `linux-uconsole` package in the existing local builder
  image, reconstruct accepted userspace from the preserved baseline bundle
  offline, install only the candidate kernel offline, and build a separately
  named candidate image without changing accepted pins;
- `install-kernel-update-candidate.sh` — perform the offline kernel-only package
  replacement inside the reconstructed baseline rootfs using a temporary
  Stage 12F-specific pacman configuration that is removed afterward, remove
  stale generated metadata from the accepted kernel release, regenerate
  candidate module metadata, and require the final userspace inventory to match
  the accepted baseline exactly except for `linux-uconsole`.

Candidate artifacts are written only under ignored `build/update-candidate/`
and `out/update-candidate/`. A successful Stage 12F build does not promote the
candidate; physical regression remains a separate gate.


# Stage 12 — Reproducible Update / Rebuild Path

**Status:** Stage 12A input audit COMPLETE; policy/design work next  
**Baseline:** final physically validated Stage 11 Arch Linux ARM image  
**Date:** 2026-11-21

## 1. Purpose

Stage 12 does not repair the current image. Stage 11 already proved that the
current image builds, boots and works on the physical uConsole.

Stage 12 defines how the project will be maintained later when Arch Linux ARM,
Raspberry Pi Linux, build tooling or other upstream inputs move.

The first checkpoint, Stage 12A, is deliberately read-only with respect to the
build. Its job is to identify every meaningful build input and classify it as:

- **pinned** — exact identity is controlled by the repository;
- **rolling** — resolved from a mutable/live source at build time;
- **generated** — derived during a build or first boot and not a fixed source.

No build behavior is changed by Stage 12A.

## 2. Known-good baseline

The Stage 11 final image is the reference baseline for all future maintenance.

```text
rootfs_release=2026.08
rootfs_sha256=f10903be472e2662e110f0f7bae2750a30914ce3dc0fcd38ec85d3405d8c8967
rpi_linux_commit=0b41724521c9adf5399409d02aece6c1df0a4432
kernel_release=6.18.60-1-uconsole
package_sha256=0f830217a766cd106347498f6aeb58f5cb320651ca26cb6ab68b096a2c61a812
image_raw_sha256=002eee704787770ad873f1cd56789df4cf56c86655895148ebbe4c03320b9a86
compressed_sha256=aa0d9c961579e12e5eb9991086d0c2b0a91670e07cc4c8cd8711f0316b0bce7a
```

The kernel package hash remained stable through the Stage 11 image-only
corrections because the kernel/hardware layer did not change.

## 3. Audit result

### 3.1 Pinned inputs

The following inputs are already explicit and stable.

| Input | Repository control | Notes |
|---|---|---|
| Raspberry Pi Linux source | `kernel/source.lock` exact commit | `0b417245...`, Linux 6.18.60 |
| Kernel branch family | recorded | `rpi-6.18.y`; informational once exact commit is selected |
| Arch Linux ARM rootfs archive | exact release, size and SHA-256 | moving `-latest` alias is forbidden |
| Rootfs signing identity | exact fingerprint | detached signature is verified |
| Rootfs archive mirrors | location only | archive bytes remain constrained by SHA-256 |
| CWU50 source | immutable AK-Rex commit URL | exact commit, but PKGBUILD checksum is currently `SKIP` |
| OCP8178 source | immutable AK-Rex commit URL | exact commit, but PKGBUILD checksum is currently `SKIP` |
| uConsole patches | Git-tracked project files | exact content determined by project Git commit |
| uConsole config/overlay/amp driver | Git-tracked project files | exact content determined by project Git commit |
| Kernel package version policy | explicit | `6.18.60-1-uconsole` |
| Image geometry | `image-layout.lock` | fixed size, partition starts/types and identities |
| PARTUUID/filesystem identities | `image-layout.lock` | fixed |
| Boot policy/cmdline/fstab | Git-tracked files | fixed by project Git commit |
| Console package-name set | `uconsole-base-packages.txt` | package **names** fixed; package versions are not |

The immutable remote kernel/driver references are materially pinned by Git
commit, but the package currently uses `SKIP` for all PKGBUILD source
checksums. This is an integrity-hardening gap rather than a moving-source
problem.

### 3.2 Rolling inputs

These inputs can change without any repository pin changing.

#### A. Final target userspace — highest-impact rolling input

`scripts/build-stage10-rootfs.sh` runs:

```text
pacman ... -Syu <uConsole package-name set>
```

against the live Arch Linux ARM repositories.

Therefore a build performed later with the same:

```text
ROOTFS_RELEASE=2026.08
RPI_LINUX_COMMIT=0b417245...
```

can still contain newer versions of:

- systemd;
- NetworkManager;
- BlueZ;
- firmware;
- `raspberrypi-bootloader`;
- `mkinitcpio`;
- libraries and base packages;
- the Stage 11 console/validation tools;
- any other package upgraded by the full `-Syu` transaction.

The rootfs lock therefore pins the **starting rootfs archive**, not the final
userspace package state.

This is the most important Stage 12 finding.

#### B. Disposable Arch build container

`scripts/build-stage10-host.sh` runs:

```text
docker.io/library/archlinux:base-devel
```

without an image digest.

Inside that mutable container it then runs another live:

```text
pacman -Syu
```

to install/update the cross-compiler and build tools.

Consequences:

- the compiler/binutils/build-tool versions can move;
- a forced kernel rebuild can produce a different package even if kernel
  source and project patches did not change;
- the local kernel-package cache can hide this variability during normal
  rebuilds, but `UCONSOLE_REBUILD_KERNEL=1` exposes it.

#### C. Local host image-building tools

The local path uses whatever versions are installed on the build host for:

- Podman or Docker;
- `losetup`, `sfdisk`, `mkfs.vfat`, `mkfs.ext4`, `e2fsck`;
- `rsync`;
- `zstd`;
- other host utilities.

The required command set is validated, but versions are not locked.

This is less likely to alter functional uConsole policy, but it can affect raw
filesystem/image bytes and compression output.

#### D. GitHub Actions execution environment

CI currently uses:

```text
runs-on: ubuntu-24.04
actions/checkout@v4
actions/upload-artifact@v4
```

and installs current Ubuntu packages with `apt-get`.

These identify a platform/release family, not immutable runner/action/package
artifacts.

This is primarily a CI/tooling reproducibility concern.

### 3.3 Generated / intentionally variable state

The following are generated rather than source pins:

- raw image SHA-256;
- compressed image SHA-256;
- filesystem creation metadata/timestamps;
- package build timestamps when the kernel package is rebuilt;
- compression output details;
- the temporary build-time pacman keyring;
- the unique pacman keyring generated on first boot of each installed device.

The generated target pacman private key is intentionally **not** shipped in the
image. This is correct security behavior and should remain device-specific.

## 4. What “reproducible” currently means

The existing project is strongly **structurally reproducible**:

- exact kernel source;
- exact uConsole source/patch policy;
- exact rootfs archive starting point;
- exact boot policy;
- exact partition geometry/identity;
- deterministic validation contracts.

It is **not yet an exact final-userspace rebuild system**, because the target
and build-container package repositories are live.

It also does not claim byte-for-byte image identity across builds.

Those distinctions should remain explicit.

## 5. Current archive/snapshot reality

Arch Linux ARM's official mirror documentation describes mirrors as being
synchronized with the current package repositories.

The Arch Linux ARM community currently discusses third-party historical
archives/rollback mirrors. A 2026 forum update points aarch64 users to a
community-hosted dated snapshot service after older community archives were
reported abandoned.

Stage 12 should therefore **not make exact rebuilds depend on an unofficial
archive service**. Such services may remain useful for recovery or research,
but they are not a sufficiently strong project-owned reproducibility anchor.

References:

- https://archlinuxarm.org/about/mirrors
- https://archlinuxarm.org/forum/viewtopic.php?f=8&t=15698

## 6. Gaps to close after Stage 12A

### Gap 1 — no final package-version lock

The build verifies that required package names are installed but does not
preserve a complete final `pacman -Q` inventory as a release input/output.

### Gap 2 — no preserved package payload set

Even if a future manifest records every package version, the official live
mirrors may no longer carry those exact package files later.

A truly exact userspace rebuild therefore needs project-controlled preservation
of the packages that differ from the pinned rootfs archive, or an equivalent
trusted snapshot mechanism.

### Gap 3 — rolling kernel build toolchain

The kernel source is pinned more tightly than the toolchain that builds it.

### Gap 4 — remote source checksums are `SKIP`

The kernel and AK-Rex sources use immutable commit URLs, but PKGBUILD should
eventually verify exact content hashes too.

### Gap 5 — manifests do not explain package-level drift

The Stage 10 manifest records rootfs/kernel/package/image identities, but not
the final userspace package inventory or build-toolchain identity.

## 7. Proposed Stage 12 design

Stage 12 should continue in small independent checkpoints.

### Stage 12A — audit and classification: COMPLETE

This document is the output.

No build logic changed.

### Stage 12B — define the release/update policy

Choose and document two distinct modes:

1. **locked rebuild**
   - reproduce an already accepted known-good release;
   - do not silently consume newer packages.

2. **update candidate**
   - deliberately refresh one class of inputs;
   - record exactly what moved;
   - validate before promoting it to the new known-good baseline.

Kernel and Arch userspace updates should normally be performed separately.

Stage 12B must decide how exact package payloads and the build toolchain are
preserved. The preferred design should not depend on a third-party historical
mirror remaining online.

### Stage 12C — baseline/manifest improvements

Likely additions:

- complete final target package inventory (`name version`);
- hashes of package payloads used for the update transaction;
- build-container identity/digest;
- build-toolchain package inventory;
- explicit mode (`locked-rebuild` vs `update-candidate`);
- meaningful baseline comparison output.

### Stage 12D — non-destructive update checker

Add a read-only tool that reports available upstream changes without modifying
locks or the repository.

It should report at least:

- current pinned Arch rootfs release;
- newer rootfs candidate, if available;
- current Raspberry Pi kernel release/commit;
- newer candidate on the selected kernel line;
- whether local project source locks still match package metadata.

The checker must never silently update a pin.

### Stage 12E — update workflow and validation matrix

Document/automate the required validation for each update class.

#### Arch userspace/rootfs update

Expected validation:

- rootfs provenance/signature;
- package transaction/inventory;
- boot policy unchanged;
- services/networking/pacman;
- bounded physical smoke test.

#### Kernel update

Expected validation:

- exact new kernel commit;
- patches apply with `--fuzz=0`;
- config/package validation;
- DT/overlay validation;
- full package build;
- targeted physical hardware regression.

### Stage 12F — prove the workflow without changing the known-good baseline

First prove the new maintenance machinery against the current pins.

Do **not** upgrade Linux or the Arch rootfs merely to test Stage 12.

Only after the maintenance path itself is proven should a real upstream update
be attempted.

## 8. Stage 12A conclusion

The current build is working and maintainable, but its reproducibility model is
mixed:

```text
pinned source/hardware policy
        +
pinned starting rootfs
        +
live final Arch package update
        +
live build toolchain
```

The next checkpoint should make the distinction between a **locked rebuild**
and an **intentional update candidate** explicit before changing any package or
kernel version.

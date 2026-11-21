# Stage 12 — Reproducible Update / Rebuild Path

**Status:** Stage 12C1 baseline-capture tooling IMPLEMENTED; local accepted-baseline capture pending  
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

### Stage 12B — release/update policy: COMPLETE

Stage 12B establishes two modes with deliberately different trust and network
semantics. The current build scripts are not switched between these modes yet;
that implementation begins in Stage 12C.

#### Mode 1 — `locked-rebuild`

Purpose: reproduce an already accepted baseline without silently moving any
upstream package or kernel input.

Rules:

- the accepted baseline is identified by
  `image/archlinuxarm/release-baseline.lock`;
- no live `pacman -Syu` is permitted;
- no moving OCI tag may determine the kernel package;
- no kernel source update is permitted;
- the exact accepted `linux-uconsole` package is reused rather than rebuilt;
- the pinned rootfs archive and all package payloads required to transform it
  into the accepted final userspace must come from a project-preserved baseline
  input bundle;
- missing baseline payloads are a hard failure, never a reason to fall back to
  live repositories;
- the final installed package inventory must match the accepted inventory;
- exact raw/compressed image hashes are informative, not a pass/fail contract.

The last point is intentional. Stage 12's primary reproducibility target is the
accepted system content and policy, not byte-identical ext4/FAT/zstd output.
Filesystem creation metadata and host image-tool versions may legitimately
change image bytes while preserving the same installed system.

A locked rebuild therefore needs the exact validated kernel **package**, not an
identical kernel compiler environment. Kernel toolchain reproducibility matters
when a new kernel package is deliberately built, not when the accepted package
is simply reused.

#### Mode 2 — `update-candidate`

Purpose: deliberately consume newer upstream state and produce a candidate that
must be reviewed before it can replace the accepted baseline.

Rules:

- live repository access is allowed only in this mode;
- the candidate must state which update class was requested;
- the candidate must record the complete final target package inventory;
- every downloaded target package payload needed to reproduce the candidate
  must be preserved before the disposable build workspace is removed;
- the exact resulting `linux-uconsole` package is preserved;
- if the kernel is rebuilt, the build-container digest and toolchain inventory
  must be recorded;
- the candidate is never promoted automatically;
- promotion occurs only after the validation matrix for that update class
  passes.

#### Update classes

Updates should normally be isolated so a regression has one clear source.

1. **Arch userspace refresh**
   - keep the rootfs archive pin and kernel package fixed;
   - refresh packages from the live Arch Linux ARM repositories;
   - capture the resulting package delta/inventory as candidate inputs.
2. **Rootfs-base refresh**
   - explicitly move to a newer versioned Arch Linux ARM rootfs archive;
   - authenticate and pin that archive first;
   - regenerate the userspace delta against the new rootfs.
3. **Kernel refresh**
   - keep Arch userspace/rootfs fixed wherever practical;
   - move the exact Raspberry Pi kernel commit deliberately;
   - rebuild and validate `linux-uconsole`;
   - record the exact builder/toolchain identity.
4. **Project-policy change**
   - change project-owned boot/userspace policy without an unrelated upstream
     refresh;
   - validate only the affected behavior plus baseline integrity.

Combining classes is allowed only when an upstream dependency makes separation
impractical, and the reason must be recorded.

#### Accepted-baseline promotion

The promotion flow is:

```text
accepted baseline
      |
      +--> locked-rebuild --------------------> same accepted baseline
      |
      `--> update-candidate
              |
              +--> capture exact candidate inputs
              +--> automated validation
              +--> targeted physical validation
              |
              `--> explicit promotion
                       |
                       `--> new accepted baseline
```

Promotion updates `release-baseline.lock` only after validation. Merely
building a candidate must never move the baseline.

#### Project-owned baseline input bundle

A self-contained baseline rebuild must not depend on old packages remaining on
Arch Linux ARM mirrors. Official mirrors are synchronized to current packages,
and pacman normally retains downloaded package files in its cache. Therefore
the project will preserve its own baseline input bundle outside Git.

The bundle design for Stage 12C is:

```text
baseline-inputs/
├── manifest
├── rootfs/
│   ├── ArchLinuxARM-<release>-rpi-aarch64-rootfs.tar.gz
│   └── provenance/signature metadata
├── target-packages/
│   ├── *.pkg.tar.*
│   └── package hashes/signatures where available
├── kernel/
│   └── linux-uconsole-<version>-aarch64.pkg.tar.*
├── inventories/
│   ├── rootfs-packages.txt
│   └── final-packages.txt
└── build-metadata/
    └── candidate/builder identity as applicable
```

The large bundle is a release artifact, not Git content. Git stores the small
lock/manifest identity and the tooling needed to create/verify the bundle.

The current final build workspace is especially useful for Stage 12C because
pacman leaves downloaded packages in `/var/cache/pacman/pkg/`. The next
checkpoint should capture those payloads before another clean build replaces
the Stage 10 workspace.

### Stage 12C — capture and describe the current accepted baseline

#### Stage 12C1 — capture tooling: IMPLEMENTED

Two fail-closed tools now define the capture contract:

- `scripts/capture-release-baseline.sh`;
- `scripts/verify-release-baseline-bundle.sh`.

The capture tool:

1. requires the retained final Stage 10 rootfs workspace and accepted Stage 10
   artifacts;
2. proves the compressed image and kernel package match
   `release-baseline.lock`;
3. records the complete final pacman inventory from the accepted workspace;
4. reacquires and verifies the pinned rootfs archive, published MD5 and detached
   Arch Linux ARM signature;
5. records the original rootfs package inventory by extracting its pacman
   local-database records in one archive pass;
6. computes exact rootfs→final added/changed and removed package sets;
7. requires an exact cached package payload for every changed/new final package
   except `linux-uconsole`;
8. preserves the exact accepted `linux-uconsole` package separately;
9. copies the Stage 10 and source/geometry lock metadata;
10. hashes every file in the resulting baseline bundle;
11. invokes the verifier before reporting success.

The default bundle location is:

```text
out/baselines/<BASELINE_ID>/
```

which is already outside Git because `out/` is ignored. Existing bundles are
never overwritten. Missing package payloads are a hard failure; capture never
consults live repositories to repair an incomplete accepted baseline cache.

#### Stage 12C2 — local capture and lock promotion: NEXT

Run the capture tool once on the machine that still holds the final Stage 11
build workspace. Record its final summary, especially:

- `bundle_lock_sha256`;
- `bundle_files_sha256`;
- `final_inventory_sha256`;
- delta/payload counts.

Stage 12C2 will then promote those identities into Git and implement the first
`locked-rebuild` consumption path against the preserved bundle.

Do not run another clean Stage 10 build until this capture succeeds.

Builder/toolchain capture is required for future kernel-update candidates. It
is not required to reproduce the accepted baseline image when the exact
validated kernel package is reused.

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

## 8. Stage 12B conclusion

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

Stage 12B has now made that distinction explicit. The next checkpoint is
Stage 12C: capture the current accepted baseline's userspace inventory and
package payloads while the final Stage 11 build workspace still exists.

# Stage 12 — Reproducible Update / Rebuild Path

**Status:** Stage 12C COMPLETE — accepted baseline captured and offline locked rebuild physically executed successfully; Stage 12D update checker next  
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
5. records the original rootfs package inventory;
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

#### Stage 12C2 — local capture, lock promotion and offline locked rebuild: COMPLETE

The accepted Stage 11 bundle was captured successfully from the retained final
workspace and passed the bundle verifier. Captured identity:

```text
bundle_lock_sha256=911d40bdc33076d962bb19a546161362367f9fb6e22a9fabfc34f004385b0986
bundle_files_sha256=b177485e629b8ed633572ef13cb9f7572e7b02ddd8a8f24fa1352172a24f4789
rootfs_inventory_sha256=3c8f488f1362c4f1d3c246c4b85645b31584f5e97c4daabb04bd32d501344a8a
final_inventory_sha256=72078b8777c61d60e3798f5a7fbb86c4c737b1d97227ddfc1151f2450befacd4
package_delta_count=141
removed_package_count=93
target_payload_count=140
```

These values are now promoted into `release-baseline.lock`. The bundle verifier
therefore validates not only internal file hashes but also the exact accepted
bundle identity recorded in Git.

The first locked-rebuild consumer is now implemented as:

```text
scripts/build-release-baseline.sh
```

Its contract is deliberately stricter than the normal Stage 10/update path:

1. verify the preserved bundle against the Git baseline lock;
2. require the existing local `archlinux:base-devel` builder image rather than
   pulling a moving tag;
3. run the container with networking disabled;
4. extract the preserved pinned rootfs;
5. replay only the preserved package payloads plus the exact accepted
   `linux-uconsole` package;
6. remove only package *names* absent from the accepted final inventory (the
   captured 93-line removed set also contains old versions of upgraded
   packages and is therefore not blindly removed);
7. require the resulting final name/version package inventory to match the
   captured accepted inventory exactly;
8. build the partitioned image into separate `build/locked-rebuild/` and
   `out/locked-rebuild/` paths so the accepted Stage 10 artifacts are not
   overwritten;
9. report the rebuilt image hash for information only — byte-identical image
   output remains intentionally outside the acceptance contract.

The locked replay disables local package signature policy only inside the
foreign-architecture replay transaction because the exact package-file hashes
are already transitively anchored by the Git-recorded bundle manifest hash.
The resulting target image still receives the normal first-boot pacman keyring
initialization policy.

A performance correction is also included for future baseline captures: the
pinned rootfs pacman database is now extracted in one archive pass instead of
reopening/decompressing the rootfs once per package entry. The already captured
bundle is valid and does not need to be regenerated.

**Validation result:** the offline locked rebuild completed successfully with
an exact accepted final package inventory and container networking disabled. No
physical hardware retest is required for this maintenance-path proof.

Builder/toolchain capture remains required for future kernel-update candidates.
It is not required for ordinary locked rebuilds because the exact accepted
kernel package is reused.

#### Stage 12C2 locked-rebuild validation result

The first offline locked rebuild reconstructed and validated the accepted rootfs
through `pacman -Dk` and `linux-uconsole` file validation, then exposed a cleanup
bug: the shared Stage 10 rootfs builder attempted to remove the preserved rootfs
archive/sidecars from the read-only `/baseline` mount. That cleanup path was
made mode-aware; normal Stage 10 behavior remained unchanged.

The corrected offline locked rebuild then completed successfully. Final proof:

```text
baseline_id=archlinuxarm-stage11-2026-11-21
builder_image_id=3f2743e9ec055adcc0ae9c3a4b055aad2daca4c48aedf3198c8213efe440eda8
final_inventory_sha256=72078b8777c61d60e3798f5a7fbb86c4c737b1d97227ddfc1151f2450befacd4
accepted_final_inventory_sha256=72078b8777c61d60e3798f5a7fbb86c4c737b1d97227ddfc1151f2450befacd4
compressed_image_sha256=a1f5bd497a4e033c53e44e92b2c536f536458f74767700143c7159b20a721eec
accepted_compressed_image_sha256=aa0d9c961579e12e5eb9991086d0c2b0a91670e07cc4c8cd8711f0316b0bce7a
byte_identical_image_required=no
```

Acceptance result:

- exact final package name/version inventory: PASS;
- accepted inventory hash equality: PASS;
- preserved rootfs/package/kernel inputs only: PASS;
- container networking disabled: PASS;
- live `pacman -Syu`: not used;
- separate locked-rebuild output path: PASS;
- byte-identical compressed image: intentionally not required.

Stage 12C is complete.

### Stage 12D — non-destructive update checker: IMPLEMENTED, LOCAL VALIDATION PENDING

`scripts/check-updates.sh` is the read-only discovery path. It first verifies
that the accepted baseline still agrees with:

- `image/archlinuxarm/rootfs.lock`;
- `kernel/source.lock`;
- `image/archlinuxarm/packages/linux-uconsole/PKGBUILD`.

Only after those local invariants pass does it query upstream. For the Arch
rootfs it reads the already configured rootfs mirror directory and selects the
latest versioned Raspberry Pi AArch64 release; if a mirror disables directory
listing, it falls back to comparing the versioned and moving `-latest` MD5
sidecars without downloading either rootfs archive. For the kernel it queries
only the selected Raspberry Pi `rpi-6.18.y` branch, records its branch-head
commit and derives the upstream version from that commit's Makefile.

The checker reports:

- pinned and candidate Arch rootfs release;
- whether an Arch rootfs candidate differs from the pin;
- pinned Raspberry Pi kernel version/commit;
- candidate `rpi-6.18.y` version/commit;
- whether the kernel branch head differs from the pin;
- local lock/package consistency;
- `repository_mutated=no`.

It creates no files and performs no package/build transaction. Git status is
snapshotted before and after the network queries; a state change is treated as
a failure. An available update is informational and does not change exit
status. An upstream source that cannot be queried reliably is reported as
unknown and causes a non-zero exit rather than being misreported as
"no update".

No project pin is ever changed by this script. Local execution is the remaining
Stage 12D validation step.

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

### 2026-11-21 — Stage 12D update-checker SIGPIPE correction

- First physical/local Stage 12D run produced no report despite successful upstream queries.
- Debug tracing proved the checker reached the current Raspberry Pi `rpi-6.18.y` branch head and fetched its Makefile.
- Root cause: `set -o pipefail` treated the intentional early exit from `awk` in a `printf | awk` pipeline as a failure when `printf` received SIGPIPE while writing the large kernel Makefile.
- Kernel VERSION/PATCHLEVEL/SUBLEVEL parsing now uses direct here-strings, removing the SIGPIPE path.
- Added an `ERR` trap so any future unexpected checker termination prints the failing line and exit status rather than exiting silently.
- No source pins, accepted baseline identity, build behavior, or update policy changed.


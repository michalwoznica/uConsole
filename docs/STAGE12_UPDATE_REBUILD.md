# Stage 12 — Reproducible Update / Rebuild Path

**Status:** Stage 12H promotion tooling IMPLEMENTED — local promotion/reproducibility proof pending  
**Baseline:** final physically validated Stage 11 Arch Linux ARM image  
**Date:** 2026-11-22

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

### Stage 12D — non-destructive update checker: COMPLETE

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

The first local run exposed a `set -o pipefail`/SIGPIPE bug in the kernel
Makefile parser. That parser now uses here-strings and the checker has an ERR
trap so unexpected failures cannot be silent.

Final local Stage 12D evidence:

```text
local_lock_consistency=pass
pinned_rootfs_release=2026.08
rootfs_candidate_release=2026.08
rootfs_update_available=no
pinned_kernel_version=6.18.60
pinned_kernel_commit=0b41724521c9adf5399409d02aece6c1df0a4432
kernel_candidate_version=6.18.64
kernel_candidate_commit=a40f735325391b1705161b07f36ed45e1bf04521
kernel_update_available=yes
repository_mutated=no
```

Stage 12D therefore proves update discovery is read-only and distinguishes
"update available" from "update applied". No project pin was changed.

### Stage 12E — isolated kernel update-candidate compatibility validation: COMPLETE

`scripts/validate-kernel-update-candidate.sh VERSION COMMIT` validates one
explicitly selected Raspberry Pi Linux candidate without modifying project
pins. Host execution delegates to `scripts/run-kernel-update-candidate.sh`,
which runs the validator in the existing local Arch builder image with the
repository mounted read-only. Candidate selection is deliberately explicit
rather than following a moving branch head during validation.

The first selected candidate was exactly the Stage 12D discovery:

```text
version=6.18.64
commit=a40f735325391b1705161b07f36ed45e1bf04521
```

Final local Stage 12E evidence:

```text
candidate_kernel_release=6.18.64-1-uconsole
patch_series=0001-0005
patch_fuzz=0
required_config_count=17
kernel_prepare=pass
device_tree_build=pass
dt_overlay_application=pass
builder_image_id=3f2743e9ec055adcc0ae9c3a4b055aad2daca4c48aedf3198c8213efe440eda8
cross_gcc_version=aarch64-linux-gnu-gcc (GCC) 16.2.0
cross_ld_version=GNU ld (GNU Binutils) 2.47
dtc_version=Version: DTC v1.8.1
project_pins_changed=no
repository_mutated=no
```

This proves mechanical compatibility only. It does not promote the candidate
or alter the physically accepted 6.18.60 baseline.

The local validation also proved two host-environment facts now encoded in the
launcher: the developer workstation does not need a host cross compiler, and
the deliberately online rootful Podman candidate container uses host networking
because normal rootful container DNS did not resolve Arch package mirrors on
this host. The repository remains read-only inside that container.

### Stage 12F — real candidate package/image build: COMPLETE

Stage 12F is intentionally kernel-only. It does not combine the kernel test
with a rolling userspace refresh.

`scripts/build-kernel-update-candidate.sh VERSION COMMIT` requires the matching
Stage 12E PASS report and then:

1. verifies the accepted Stage 11 baseline bundle against
   `release-baseline.lock`;
2. stages the normal `linux-uconsole` package inputs and changes `pkgver` and
   `_commit` only in the ignored candidate workspace;
3. uses the already-local Arch builder image and host networking only while
   building the real candidate `linux-uconsole` package;
4. records builder image/toolchain identity and preserves the exact candidate
   package plus SHA-256;
5. reconstructs the accepted Stage 11 userspace/rootfs from the preserved
   baseline bundle with container networking disabled;
6. creates a Stage 12F-specific temporary offline pacman configuration inside
   the reconstructed rootfs, installs only the candidate `linux-uconsole`
   package with networking disabled, and removes that temporary configuration
   before candidate validation completes;
7. requires every installed package other than `linux-uconsole` to match the
   accepted baseline inventory exactly;
8. removes stale generated module metadata from the accepted kernel release and
   regenerates dependency metadata for the candidate release;
9. reuses the proven Stage 10 image-construction path to build/validate the
   candidate microSD image under a candidate-specific filename;
10. preserves the candidate final inventory, builder metadata, image manifest,
    image/package hashes and a Stage 12F candidate report under
    `out/update-candidate/`;
11. verifies Git state is unchanged and records that physical validation and
    promotion have not occurred.

Stage 10 image construction now has opt-in environment overrides for candidate
kernel release/commit, checkpoint label and output-name variant. With those
overrides unset, normal Stage 10/locked-rebuild behavior and filenames are
unchanged.

The real Stage 12F build completed successfully:

```text
candidate_kernel_version=6.18.64
candidate_kernel_commit=a40f735325391b1705161b07f36ed45e1bf04521
candidate_kernel_release=6.18.64-1-uconsole
candidate_package_sha256=e4eb51edf12d7022ee96a5599ac7643dc665afd02aad1ecdd074c3e108674206
userspace_inventory=accepted-baseline-except-linux-uconsole
final_inventory_sha256=151fd2dcead053dd748b3d6b3993f776df786ca40510bb41f43592be2c629666
compressed_image_sha256=d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19
project_pins_changed=no
repository_mutated=no
```

### Stage 12G — physical candidate validation: COMPLETE

The Stage 12F image was flashed and booted on the physical uConsole CM4.
Validation passed for:

- kernel identity `6.18.64-1-uconsole`;
- zero failed systemd units;
- brightness keys;
- Wi-Fi association, DHCP, routing and DNS;
- Bluetooth scan;
- USB storage;
- battery reporting;
- built-in speaker output;
- headphone output;
- live speaker/headphone switching in both directions;
- short power-button ignore policy;
- clean reboot;
- clean poweroff with the device remaining off.

Stage 12G therefore closes the candidate-validation chain. Promotion remains a
separate operation and has not occurred at this checkpoint.

### Stage 12H — promote exact physically validated candidate: IMPLEMENTED, LOCAL RUN PENDING

Stage 12H is the terminal step of this update cycle. It does not discover or
chase another upstream kernel. It promotes the exact Stage 12F artifact that
already passed Stage 12G physical validation.

`image/archlinuxarm/stage12g-physical-validation.lock` records the machine-
readable physical-validation gate for the accepted candidate identity.

`scripts/promote-kernel-update-candidate.sh VERSION COMMIT [NEW_BASELINE_ID]`
performs the promotion atomically:

1. require a clean Git worktree;
2. verify the current accepted baseline bundle before changing anything;
3. verify the exact Stage 12F package/image/report hashes against the Stage 12G
   physical-validation lock;
4. derive a new baseline bundle by reusing the accepted rootfs/userspace
   payloads and replacing only `linux-uconsole` with the physically validated
   candidate package;
5. update `kernel/source.lock`, the authoritative `linux-uconsole` PKGBUILD and
   `release-baseline.lock` to the validated candidate;
6. verify the newly generated baseline bundle against the promoted repository
   lock;
7. audit executable/configuration files for stale references to the previous
   accepted kernel identity;
8. run `build-release-baseline.sh` with container networking disabled;
9. require the locked rebuild package inventory to match the promoted accepted
   inventory exactly;
10. keep the promotion only if every gate passes. On failure, restore the old
    accepted locks and remove the unaccepted new bundle.

The locked rebuild output is evidence only. Its image does not become a second
candidate and does not require another physical flash. The exact Stage 12F
image remains the accepted physically validated image.

To support promotion and future cycles, Stage 12H also removes old hard-coded
`6.18.60-1` assumptions from the baseline capture/verifier and Stage 10 locked
rootfs/image builders. Those paths now derive the accepted kernel release from
`release-baseline.lock`.

The update cycle ends when the Stage 12H promotion block reports both
`physical_validation=pass` and `locked_rebuild=pass`. No higher kernel is
evaluated unless a future update cycle is explicitly started.

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

Stage 12B made that distinction explicit. Stage 12C subsequently proved the
offline locked rebuild, Stage 12D proved non-destructive update discovery,
Stage 12E proved candidate compatibility, Stage 12F built the isolated real
candidate, and Stage 12G physically validated it on the uConsole.

The current checkpoint is Stage 12G complete. Stage 12H is the separate
promotion step for the physically validated 6.18.64 kernel; no userspace refresh
is part of that promotion.



### 2026-11-22 — Stage 12F/12G candidate build and physical-validation closeout

- Real Stage 12F kernel-only build passed for Raspberry Pi Linux 6.18.64 at
  `a40f735325391b1705161b07f36ed45e1bf04521`.
- Candidate `linux-uconsole-6.18.64-1` package SHA-256:
  `e4eb51edf12d7022ee96a5599ac7643dc665afd02aad1ecdd074c3e108674206`.
- Candidate compressed image SHA-256:
  `d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19`.
- Stage 12G physical regression passed for boot, systemd health, brightness,
  Wi-Fi/DHCP/routing/DNS, Bluetooth, USB storage, battery reporting, speakers,
  headphones, live audio switching, power-key ignore policy, reboot and
  shutdown.
- Accepted pins remain unchanged in this closeout. Stage 12H promotion is next.

### 2026-11-22 — Stage 12F temporary pacman-policy correction

- The first real Stage 12F run successfully reconstructed and validated the
  accepted Stage 10/11 rootfs, then stopped before candidate-kernel replacement.
- Root cause: the Stage 10 locked builder intentionally removes its temporary
  `/etc/pacman.stage12-locked.conf` after rootfs composition, while the new
  Stage 12F installer incorrectly required that build-only file to remain.
- Stage 12F now creates its own temporary offline pacman configuration only for
  candidate-kernel replacement and removes it on success or failure.
- The accepted image/rootfs policy is unchanged; no build-only pacman
  configuration is retained in the candidate image.

### 2026-11-21 — Stage 12D update-checker SIGPIPE correction

- First physical/local Stage 12D run produced no report despite successful upstream queries.
- Debug tracing proved the checker reached the current Raspberry Pi `rpi-6.18.y` branch head and fetched its Makefile.
- Root cause: `set -o pipefail` treated the intentional early exit from `awk` in a `printf | awk` pipeline as a failure when `printf` received SIGPIPE while writing the large kernel Makefile.
- Kernel VERSION/PATCHLEVEL/SUBLEVEL parsing now uses direct here-strings, removing the SIGPIPE path.
- Added an `ERR` trap so any future unexpected checker termination prints the failing line and exit status rather than exiting silently.
- No source pins, accepted baseline identity, build behavior, or update policy changed.



### 2026-11-22 — Stage 12H stale-reference audit false-positive correction

- The first real Stage 12H promotion attempt passed current-bundle verification,
  constructed the promoted bundle, updated the temporary promotion locks and
  verified the promoted bundle, then stopped at the stale-kernel-reference audit.
- The audit reported `kernel/sources/axp20x-battery.lock` and
  `scripts/validate-arch-rootfs-integration.sh`, but an exact fixed-string check
  after rollback found neither the old `6.18.60` version nor the old kernel
  commit in those files.
- Root cause: the audit attempted to escape dots through Bash parameter
  substitution before `grep -E`; the backslashes were not preserved, so the dots
  in `6.18.60` acted as regular-expression wildcards and caused false matches.
- The audit now checks the previous version and commit independently with
  `grep -F`, so only literal stale accepted-kernel identities are actionable.
- Promotion rollback worked as designed: the previous accepted repository state
  was restored and the unaccepted `archlinuxarm-stage12h-2026-11-22` bundle was
  removed.
- No accepted pin, package, image or baseline bundle changed in the failed run.

### 2026-11-22 — Stage 12H promotion tooling

- Added a machine-readable Stage 12G physical-validation lock for the exact
  6.18.64 candidate package/image identity.
- Added atomic promotion tooling that derives the new locked baseline from the
  existing accepted userspace bundle plus the exact physically validated kernel
  package.
- Promotion runs the network-disabled locked rebuild before it is retained.
- Failed promotion restores the previous accepted kernel/package/baseline locks
  and removes the unaccepted new bundle.
- Generalized baseline capture/verification and Stage 10 locked rebuild defaults
  so future accepted kernels are derived from `release-baseline.lock` rather
  than hard-coded to 6.18.60.
- This is the final implementation step of the current 6.18.64 update cycle; a
  later upstream version is informational only until a new cycle is explicitly
  started.

# uConsole Arch Linux Project Handoff

**Project:** Linux for ClockworkPi uConsole (Raspberry Pi CM4 Lite, original 2024 display)
**Status date:** 2026-11-22
**Document revision:** 6.19
**Current phase:** Stage 12 COMPLETE; stable Arch baseline frozen; public-release transition next

---

## 1. Project goal

Build and maintain a reproducible Linux system for a ClockworkPi uConsole using:

- Raspberry Pi Compute Module 4 Lite (`104000`; no eMMC)
- Original/older uConsole display revision from 2024
- microSD boot/storage
- Arch Linux ARM as the first userspace target
- ARMtix/Artix with OpenRC as a later userspace target
- Raspberry Pi Linux `rpi-6.18.y` as the shared kernel base
- A minimal uConsole-specific patchset rather than a permanently forked kernel tree
- Normal Arch-style packaging so the kernel can be rebuilt and upgraded later
- A deterministic image-building path

The project should remain understandable and reproducible months later, not merely produce one working image.

---

## 2. Reproducibility and project-history policy

The project is maintained in the user's own GitHub repository.

Every completed implementation stage should:

1. have one narrow goal;
2. produce independently reviewable changes;
3. be validated before moving on;
4. be committed to Git;
5. update this handoff document;
6. record what is proven, what remains assumed, and what comes next.

The handoff filename must remain exactly:

`UCONSOLE_ARCH_PROJECT_HANDOFF.md`

Version/revision information belongs inside the file so Git tracks it as one evolving document.

Checkpoint workflow:

- Git repository is authoritative.
- Assistant supplies complete checkpoint ZIPs without `.git/`.
- User overlays/extracts them into the local repository.
- User reviews `git diff`, commits, and pushes.
- Deletions/renames must be explicitly called out because ZIP overlay alone does not remove old files.

---

## 3. Multi-distro architecture policy

Arch Linux ARM is the **first implementation target**, but the project is deliberately shaped so that **ARMtix/Artix with OpenRC can be added later** without redesigning the hardware-support layer.

```text
shared uConsole hardware/kernel support
                |
        +-------+-------+
        |               |
        v               v
 Arch Linux ARM    ARMtix / OpenRC
   first target      later target
```

Therefore:

- kernel patches remain distro-neutral;
- device-tree and boot-hardware logic remain distro-neutral;
- shared build scripts avoid systemd assumptions;
- distro/init-specific userspace logic lives under separate image-target directories;
- systemd-specific integration belongs only in the Arch Linux ARM image layer;
- OpenRC-specific integration will later live in the ARMtix target.

Planned image layout:

```text
image/
├── archlinuxarm/
└── armtix-openrc/
```

The Arch target is complete and physically validated. `main` is now the stable
Arch/publication baseline. Future ARMtix/Artix OpenRC implementation must occur
on a dedicated development branch and should not alter `main` until that target
has its own validation/promotion evidence.

---

## 4. Hardware facts

### uConsole

- ClockworkPi uConsole
- 2024 generation
- Original/older screen revision

### Compute Module

- Raspberry Pi Compute Module 4 Lite
- Module code: `104000`
- No onboard eMMC
- Boots from the uConsole microSD slot

---

## 5. Starting repository investigated

Initial project:

- https://github.com/fabiiw05/uconsole-archlinux

This is best understood as a complete image builder rather than merely a kernel patch collection.

Useful parts likely worth retaining or adapting later:

- Arch Linux ARM rootfs handling
- partition and image creation
- first-boot root filesystem expansion
- NetworkManager setup
- general boot-image assembly
- some uConsole-specific userspace setup

Its 6.12 kernel builder should not be treated as our long-term kernel architecture.

---

## 6. Kernel lineage investigation

Relevant projects investigated:

- ClockworkPi uConsole:
  https://github.com/clockworkpi/uConsole
- AK-Rex:
  https://github.com/ak-rex/rpi-linux
- OuinOuin74:
  https://github.com/OuinOuin74/linux-clockwork-arch
- KondratokGK:
  https://github.com/KondratokGK/linux-clockwork-arch
- ClusterM:
  https://github.com/ClusterM/ClockworkPi-linux
- PotatoMania:
  https://github.com/PotatoMania/uconsole-cm3
- Raspberry Pi kernel:
  https://github.com/raspberrypi/linux
- postmarketOS packages:
  https://pkgs.postmarketos.org/

Main conclusion:

```text
official raspberrypi/linux
        rpi-6.18.y
             +
small auditable uConsole patchset
             +
distro-neutral kernel package
```

Linux 6.18 LTS is preferred over 6.12 and short-lived 7.x branches for long-term maintainability.

---

## 7. Intended uConsole-specific delta

### Required

1. CWU50 LCD panel driver
2. OCP8178 backlight driver
3. uConsole CM4 device-tree overlay

### Strongly desirable

4. small AXP20x battery/fuel-gauge improvements
5. headphone/speaker amplifier switching

### Keep stock unless testing proves otherwise

- CM4 CPU/platform support
- VC4/KMS GPU
- Wi-Fi
- Bluetooth
- SD
- USB
- I2C
- SPI
- UART
- GPIO
- TI ADC driver
- generic AXP20x support
- VC4 DSI internals

---

## 8. Provenance decisions

### CWU50 panel

Preferred source: modern AK-Rex unified CWU50 lineage.

Reasons:

- supports old and new panel revisions;
- retains original-panel initialization;
- includes DSI diagnostics;
- avoids adopting an entire kernel fork.

### OCP8178 backlight

Preferred design:

- AK-Rex behavior/state handling as base;
- evaluate ClusterM's 22-level brightness map.

### CM4 device tree

Create a cleaned project-specific overlay:

- conservative AK-Rex structure;
- selected useful modern OuinOuin74 properties;
- avoid unrelated policy such as forced PCIe/Ethernet disablement and SD overclocking;
- make battery capacity configurable where practical.

### AXP20x battery

Start from stock Raspberry Pi 6.18.

Add only small proven improvements, potentially:

- correct design capacity;
- correct design energy;
- fuel-gauge capacity handling.

Do not import an entire alternate AXP subsystem.

### Power button

Use stock 6.18 `axp20x-pek` initially.

### Audio/headphone switching

Prefer PotatoMania's simple amplifier-switch design.

### DSI recovery

Use stock Raspberry Pi 6.18 VC4/DSI plus modern CWU50 diagnostics first.

Do not carry old invasive VC4 DSI workarounds unless physical testing demonstrates a real failure.

---

## 9. Target repository architecture

```text
.
├── README.md
├── LICENSE
├── docs/
│   ├── PROVENANCE.md
│   └── UCONSOLE_ARCH_PROJECT_HANDOFF.md
├── kernel/
│   ├── README.md
│   ├── config/
│   └── patches/
├── image/
│   ├── README.md
│   ├── archlinuxarm/
│   └── armtix-openrc/
└── scripts/
```

The repository should be a build recipe, not a snapshot of a modified Linux source tree.

---

## 10. Planned stages

### Stage 0 — Repository bootstrap

Create:

- README
- license
- `.gitignore`
- handoff
- provenance document
- shared kernel structure
- Arch Linux ARM image target
- reserved ARMtix/OpenRC image target

### Stage 1 — Pin exact Raspberry Pi 6.18 baseline

Record:

- repository
- branch
- exact commit hash
- kernel version
- selection rationale

### Stage 2 — Dry-port CWU50 panel

### Stage 3 — Dry-port OCP8178 backlight

### Stage 4 — Create cleaned CM4 overlay

### Stage 5 — Minimal AXP20x battery patch

### Stage 6 — Audio/headphone switching

### Stage 7 — Kernel config and Arch-style packaging

### Stage 8 — Build-only validation

### Stage 9 — Arch Linux ARM image-builder integration

### Stage 10 — First microSD image

### Stage 11 — Physical hardware validation

Validate at minimum:

- boot
- LCD
- backlight
- keyboard
- Wi-Fi
- Bluetooth
- audio
- headphone switching
- battery
- charging
- power button
- USB
- SD
- GPU/KMS
- reboot/shutdown

### Stage 12 — Reproducible update/rebuild path

Stage 12 is split into bounded maintenance checkpoints:

- **12A:** audit/classify all build inputs as pinned, rolling or generated;
- **12B:** define locked-rebuild versus intentional-update policy — COMPLETE;
- **12C:** capture the accepted baseline package inventory/payload bundle and implement locked rebuild — COMPLETE;
- **12D:** add and locally prove a non-destructive update checker — COMPLETE;
- **12E:** validate an explicit kernel update candidate without changing pins — COMPLETE;
- **12F:** build the real candidate package/image without promotion, then perform bounded physical regression — IMPLEMENTED, LOCAL BUILD PENDING.

See `docs/STAGE12_UPDATE_REBUILD.md`.


### Later milestone — ARMtix/OpenRC image target

Reuse the proven shared kernel/hardware layer and replace Arch/systemd-specific userspace integration with ARMtix/OpenRC equivalents.

---

## 11. Proven vs unproven

### Proven through investigation

- Existing Arch/uConsole image builders exist.
- Modern uConsole support exists beyond 6.12.
- Raspberry Pi maintains a 6.18 kernel branch.
- The required uConsole-specific delta is much smaller than the original ClockworkPi monolithic patch.
- Patch-based packaging is practical.
- Arch-first / ARMtix-later can share the same kernel/hardware layer.

### Proven by this project

- CWU50 compile compatibility against the pinned 6.18.60 baseline;
- OCP8178 compile compatibility against that baseline;
- cleaned CM4 DT overlay compilation/application;
- minimum AXP20x battery delta integration;
- audio-switch driver integration;
- full kernel/modules/DTB build and package construction;
- authenticated Arch Linux ARM rootfs integration;
- deterministic partition/boot contract;
- physical boot from microSD into Arch Linux ARM userspace;
- physical CWU50 panel output and VC4/KMS/DSI console path;
- physical OCP8178 backlight operation and direct sysfs brightness control;
- built-in keyboard, Consumer Control input interface and correct
  `KEY_BRIGHTNESSUP` / `KEY_BRIGHTNESSDOWN` event generation;
- Wi-Fi association, IPv4 traffic, DNS through NetworkManager/systemd-resolved
  and profile/password persistence across reboot;
- normal `pacman -Syu` on the physical image with the target Landlock sandbox;
- built-in speaker output and headphone-jack output;
- GPIO10 headphone detect and the existing amplifier-switch driver logic after
  live no-pull configuration, including correct speaker mute/restore behavior;
- battery charging/discharging state and AXP22x AC-online transition reporting;
- power-button input path;
- Bluetooth controller power/rfkill state plus real LE RF discovery through
  the kernel management path (`btmgmt find`);
- USB mass-storage detection, mount and unmount;
- reboot and shutdown/power-off behavior exercised during physical validation;
- console printk level 3 prevents routine kernel/device messages from overwriting tty1.

### Still unproven / incomplete

- long-duration hardware reliability beyond the completed bounded physical tests;
- byte-for-byte image reproducibility across independent builds (not required by
  the accepted reproducibility contract);
- public-repository/release readiness audit and publication;
- ARMtix/Artix OpenRC image target.

---

## 12. Current step

### Stage 0 — repository bootstrap: COMPLETE
### Stage 1 — Raspberry Pi Linux 6.18.60 baseline: COMPLETE
### Stage 2 — CWU50 panel dry-port: COMPLETE
### Stage 3 — OCP8178 backlight dry-port: COMPLETE
### Stage 4 — cleaned uConsole CM4 device-tree overlay: COMPLETE
### Stage 5 — minimal AXP20x/AXP221 battery delta: COMPLETE
### Stage 6 — audio/headphone speaker switching: COMPLETE
### Stage 7 — kernel configuration and Arch packaging: COMPLETE
### Stage 8 — full build-only validation: COMPLETE
### Stage 9A — pin/authenticate Arch Linux ARM rootfs: COMPLETE
### Stage 9B — pacman-managed uConsole rootfs integration: COMPLETE
### Stage 9C — final boot command line/initramfs policy: COMPLETE

### Stage 10 — first partitioned microSD image: COMPLETE

Final Stage 10 evidence:

- authenticated rootfs preparation: PASS;
- real aarch64 `linux-uconsole` build: PASS;
- pacman-managed stock kernel/U-Boot replacement: PASS;
- final boot/root policy installation: PASS;
- 8 GiB raw image creation: PASS;
- explicit 512-byte logical-sector loop device: PASS;
- deterministic DOS/MBR partition table: PASS;
- disk ID `0x55434f4e`: PASS;
- boot partition: 512 MiB FAT32, PARTUUID `55434f4e-01`;
- root partition: ext4, PARTUUID `55434f4e-02`;
- boot FAT label `UCONBOOT`: PASS;
- root label `UCONSOLEROOT`: PASS;
- fixed root filesystem UUID: PASS;
- rootfs capacity/headroom gate: PASS;
- ext4 root population with Unix metadata: PASS;
- FAT boot population: PASS;
- kernel/DTB/uConsole DTBO/modules validation: PASS;
- final config/cmdline/fstab validation: PASS;
- `linux-uconsole` local package DB validation: PASS;
- no stock kernel/U-Boot DB residue: PASS;
- no U-Boot boot-script residue: PASS;
- FAT fsck: PASS;
- ext4 fsck: PASS;
- raw image SHA-256: generated;
- zstd compression/integrity: PASS;
- compressed image SHA-256: generated;
- manifest: generated;
- exact `linux-uconsole` package: preserved;
- workflow artifact upload: PASS.

Workflow artifact name:

`uconsole-archlinuxarm-stage10`

Expected artifact contents include the compressed `.img.zst`, raw/compressed
SHA-256 files, Stage 10 manifest and exact `linux-uconsole` package.

### Stage 10 physical display/module integration correction: COMPLETE / PHYSICALLY VALIDATED

The first physical boot of the untouched Stage 10 artifact produced a brief
backlight flash followed by a black panel. A current official ClockworkPi CM4
image was tested repeatedly on the same uConsole and displayed normally,
ruling out a basic hardware/display fault.

The investigation proved that the Stage 10 image itself reached Linux and
userspace, and that the uConsole DT overlay applied, but the display modules
were not autoloaded. The installed target module directory contained
`panel-cwu50.ko.xz` and `ocp8178_bl.ko.xz` but lacked the depmod-generated
`modules.dep`, `modules.alias`, `modules.devname` and related metadata. This
was caused by the intentional suppression of target ALPM hooks/scriptlets in
the cross-architecture pacman transaction; the normal kernel depmod hook was
therefore skipped as a side effect.

The manually repaired test card proved the required correction:

1. adding `gpio=9=op,dh` to `config.txt` made the backlight remain asserted;
2. running host-side `depmod -b <target-root> 6.18.60-1-uconsole` generated the
   missing module metadata;
3. `modinfo` then resolved both `panel_cwu50` and `ocp8178_bl` with their DT
   aliases;
4. the same card booted to the Arch login prompt with visible console output;
5. live inspection showed CWU50/OCP8178 loaded, VC4/DRM active, a DSI connector
   present and the backlight class device created.

The repository correction now:

- asserts GPIO9 in the generated boot config;
- runs host-side `depmod` explicitly after the cross-architecture kernel
  package transaction;
- validates the generated kmod metadata and CWU50/OCP8178 module aliases;
- validates that the metadata survives into the populated image.

No kernel source/patch, DT overlay, package version, rootfs pin, partition
geometry, PARTUUID, filesystem identity or direct-root boot policy changed.

Fresh corrected-image revalidation subsequently passed end to end:

- corrected Stage 10 CI workflows: PASS;
- workflow artifact ZIP SHA-256:
  `27919add8106ca637ae0416f1b473e014734aa1b77300bac50c2c3e1b8c88051`;
- compressed image checksum verification: PASS;
- kernel package SHA-256:
  `ca53afee2b42af14dab64fc31de2f283cd10051867a8d25a05b8069f1dbca1fb`;
- raw image SHA-256:
  `e2ca929b5cf4e9d263ea9fe2705d49e71e2133e463735dc6127a7017fcda8721`;
- compressed image SHA-256:
  `b75f6284503dc7f0ea6266006fb0a8ef18fb162ed1bc81da2e4a107a2821ce99`;
- freshly flashed untouched media booted with no manual repair: PASS;
- visible boot output and Arch login console: PASS;
- interactive login as the stock Arch Linux ARM user: PASS;
- live CWU50/OCP8178 module loading: PASS;
- VC4/DRM DSI connector and backlight class presence: PASS.

The early old-panel/regulator retry messages observed from CWU50 resolve during
probe; the panel subsequently binds and renders the console. They are recorded
as non-blocking runtime behavior rather than a Stage 10 failure.

### Repository privacy/publication policy

Treat Git history as permanently public. Never commit user/host identifiers,
usernames, account IDs, machine-specific absolute paths or other PII. Continue
privacy audits before every checkpoint and before publication.

### Stage 11 — physical hardware validation: COMPLETE

Stage 11 is complete. See `docs/STAGE11_PHYSICAL_VALIDATION.md` for the full
physical evidence and correction history.

The final rebuilt image was flashed to microSD and booted on the physical
uConsole. All required Stage 11 hardware paths and the three image-layer
corrections are physically proven:

- microSD boot to visible Arch console;
- CWU50 panel + VC4/KMS/DSI display path;
- OCP8178 backlight and `Fn + <` / `Fn + >` brightness control;
- keyboard input and Consumer Control events;
- Wi-Fi, DNS, NetworkManager persistence and normal `pacman -Syu`;
- built-in speaker and headphone audio;
- automatic headphone insertion/removal switching from boot;
- battery charge/discharge and AC-online transitions;
- brief power-button press ignored by the selected logind policy;
- Bluetooth controller/kernel/RF path and normal BlueZ discovery;
- USB mass-storage detection/mount/unmount;
- reboot and shutdown/power-off paths.

The three Stage 11 corrections are:

1. `gpio=10=ip,np` for reliable headphone detection;
2. the console-only brightness-key service using the exact physical input name
   `ClockworkPI uConsole Consumer Control`;
3. `HandlePowerKey=ignore` for brief power-button presses.

Final validated artifact identity:

```text
rootfs_release=2026.08
rpi_linux_commit=0b41724521c9adf5399409d02aece6c1df0a4432
kernel_release=6.18.60-1-uconsole
package_sha256=0f830217a766cd106347498f6aeb58f5cb320651ca26cb6ab68b096a2c61a812
image_raw_sha256=002eee704787770ad873f1cd56789df4cf56c86655895148ebbe4c03320b9a86
compressed_sha256=aa0d9c961579e12e5eb9991086d0c2b0a91670e07cc4c8cd8711f0316b0bce7a
```

The kernel package hash remained unchanged across the Stage 11 image fixes,
which is expected because the physically proven kernel/hardware layer did not
need modification.

### Stage 12A — reproducible update/rebuild input audit: COMPLETE

The current repository was audited without changing build behavior.

Key result:

- kernel source, uConsole hardware sources, starting rootfs and image geometry
  are explicitly pinned;
- the final Arch userspace is **rolling** because the image builder runs
  `pacman -Syu` against live Arch Linux ARM repositories;
- the disposable `archlinux:base-devel` build environment is also rolling and
  performs its own live `pacman -Syu`;
- host filesystem/compression tools and GitHub runner/action versions are not
  immutable;
- the current project is structurally reproducible but does not yet guarantee
  an exact final-userspace or byte-identical rebuild.

The audit is documented in `docs/STAGE12_UPDATE_REBUILD.md`.

### Stage 12B — release/update policy: COMPLETE

Stage 12B defines two explicit maintenance modes without changing the current
Stage 10 build behavior yet:

1. `locked-rebuild` — no live package/kernel refresh, reuse the exact accepted
   kernel package and a project-preserved baseline input bundle, and fail closed
   if required payloads are missing;
2. `update-candidate` — live upstream access is allowed deliberately, but exact
   candidate inventory/payload capture is required and promotion is never
   automatic.

The accepted Stage 11 artifact identity is now machine-readable in:

`image/archlinuxarm/release-baseline.lock`

Raw/compressed image byte identity remains informative rather than the primary
reproducibility contract. Accepted system content, package identity, boot policy
and hardware behavior are the contract.

A normal locked rebuild reuses the exact validated `linux-uconsole` package.
Therefore exact kernel toolchain capture is required when producing a new kernel
package, not for ordinary baseline reconstruction.

### Stage 12C — accepted baseline capture and locked rebuild: COMPLETE

The accepted Stage 11 workspace was captured successfully and verified as:

```text
bundle_lock_sha256=911d40bdc33076d962bb19a546161362367f9fb6e22a9fabfc34f004385b0986
bundle_files_sha256=b177485e629b8ed633572ef13cb9f7572e7b02ddd8a8f24fa1352172a24f4789
final_inventory_sha256=72078b8777c61d60e3798f5a7fbb86c4c737b1d97227ddfc1151f2450befacd4
package_delta_count=141
removed_package_count=93
target_payload_count=140
```

Those identities are promoted into `release-baseline.lock`. The verifier anchors
the local bundle directly to Git metadata before checking every file hash and
package payload.

`scripts/build-release-baseline.sh` implements the locked rebuild path:

- preserved rootfs only;
- preserved package payloads only;
- exact accepted `linux-uconsole` package;
- no container network;
- no live `pacman -Syu`;
- no kernel rebuild;
- exact final package name/version inventory required;
- separate locked-rebuild work/output directories.

The first validation exposed only a mode-specific cleanup bug: the shared Stage
10 rootfs builder tried to remove immutable rootfs inputs mounted read-only from
the baseline bundle. That was corrected without changing normal Stage 10
cleanup semantics.

The corrected offline locked rebuild then completed successfully:

```text
baseline_id=archlinuxarm-stage11-2026-11-21
builder_image_id=3f2743e9ec055adcc0ae9c3a4b055aad2daca4c48aedf3198c8213efe440eda8
final_inventory_sha256=72078b8777c61d60e3798f5a7fbb86c4c737b1d97227ddfc1151f2450befacd4
accepted_final_inventory_sha256=72078b8777c61d60e3798f5a7fbb86c4c737b1d97227ddfc1151f2450befacd4
compressed_image_sha256=a1f5bd497a4e033c53e44e92b2c536f536458f74767700143c7159b20a721eec
accepted_compressed_image_sha256=aa0d9c961579e12e5eb9991086d0c2b0a91670e07cc4c8cd8711f0316b0bce7a
byte_identical_image_required=no
```

This proves the accepted Stage 11 logical userspace/package baseline can be
reconstructed without live repository access. The differing compressed image
hash is expected and accepted because Stage 12 does not require byte-identical
filesystem images.

### Stage 12D — non-destructive update checker: COMPLETE

Added and locally validated `scripts/check-updates.sh`.

Final local result:

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

The first local run exposed a late SIGPIPE/`pipefail` parser bug after the
network queries had already succeeded. The parser was corrected and an ERR trap
was added; the rerun produced the complete report above. No project pin changed.

### Stage 12E — isolated kernel update-candidate compatibility validation: COMPLETE

The exact Stage 12D candidate passed locally:

```text
candidate_kernel_version=6.18.64
candidate_kernel_commit=a40f735325391b1705161b07f36ed45e1bf04521
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

All five project patches therefore remain strict zero-fuzz compatible with
Raspberry Pi Linux 6.18.64, the required config resolves, kernel prepare passes,
and the CM4/uConsole device trees build and compose successfully. No accepted
pin changed.

### Stage 12F — real 6.18.64 candidate package/image build: COMPLETE

Added `scripts/build-kernel-update-candidate.sh VERSION COMMIT` and
`scripts/install-kernel-update-candidate.sh`.

The Stage 12F contract is kernel-only:

- require the matching Stage 12E PASS report;
- verify the accepted baseline bundle first;
- build the real candidate `linux-uconsole` package online in the existing local
  Arch builder image;
- reconstruct accepted Stage 11 userspace from the preserved baseline bundle
  offline;
- create a Stage 12F-only temporary offline pacman configuration, replace only
  `linux-uconsole` with the candidate package offline, then remove that
  temporary configuration;
- require every other installed package name/version to remain exactly equal to
  the accepted inventory;
- build the candidate image through the existing Stage 10 image path with
  candidate-only release/commit/name overrides;
- preserve package/image hashes, builder/toolchain metadata, final inventory and
  candidate report under ignored `out/update-candidate/`;
- leave source/package/baseline pins and Git state unchanged.

The real Stage 12F build completed successfully:

```text
candidate_kernel_version=6.18.64
candidate_kernel_commit=a40f735325391b1705161b07f36ed45e1bf04521
candidate_kernel_release=6.18.64-1-uconsole
candidate_package_filename=linux-uconsole-6.18.64-1-aarch64.pkg.tar.zst
candidate_package_sha256=e4eb51edf12d7022ee96a5599ac7643dc665afd02aad1ecdd074c3e108674206
userspace_inventory=accepted-baseline-except-linux-uconsole
final_inventory_sha256=151fd2dcead053dd748b3d6b3993f776df786ca40510bb41f43592be2c629666
compressed_image_filename=uconsole-archlinuxarm-2026.08-cm4-candidate-kernel-6.18.64-a40f73532539.img.zst
compressed_image_sha256=d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19
project_pins_changed=no
repository_mutated=no
physical_validation=not_run
promotion=not_performed
```

### Stage 12G — physical validation of 6.18.64 candidate: COMPLETE

The Stage 12F image was written to microSD and booted on the physical
ClockworkPi uConsole CM4. The candidate passed the bounded regression:

- booted successfully as `6.18.64-1-uconsole`;
- `systemctl --failed` reported zero failed units;
- brightness buttons worked;
- NetworkManager, systemd-resolved and Bluetooth services were active;
- Wi-Fi associated successfully and obtained DHCP addressing;
- IPv4 routing and DNS resolution worked;
- battery status/capacity reporting worked;
- ALSA enumerated the expected uConsole/headphone and HDMI devices;
- built-in speakers produced audio;
- headphone output produced audio;
- live speaker -> headphone switching worked when inserting headphones;
- live headphone -> speaker switching worked when removing headphones;
- Bluetooth scanning worked;
- USB storage worked;
- short ON/OFF-button press was correctly ignored;
- clean reboot returned to `6.18.64-1-uconsole` with zero failed units;
- clean poweroff shut the uConsole down and it remained off.

The candidate is therefore mechanically and physically validated. Promotion has
still not been performed, and the accepted 6.18.60 project pins remain
unchanged at this checkpoint.

### Stage 12H — promotion of physically validated 6.18.64 candidate: COMPLETE

Stage 12H promoted exactly the Stage 12F image/package that had already passed
Stage 12G physical validation. The final promotion passed accepted-bundle
verification, candidate identity checks, stale-reference audit, promoted-bundle
verification, and a network-disabled locked rebuild.

Final accepted identity:

```text
baseline_id=archlinuxarm-stage12h-2026-11-22
rootfs_release=2026.08
kernel_release=6.18.64-1-uconsole
rpi_linux_commit=a40f735325391b1705161b07f36ed45e1bf04521
kernel_package_sha256=e4eb51edf12d7022ee96a5599ac7643dc665afd02aad1ecdd074c3e108674206
image_raw_sha256=a2daeb466eae193917da5405adf52d60cadb55d029278502c407bbedd4aa0212
image_compressed_sha256=d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19
final_inventory_sha256=151fd2dcead053dd748b3d6b3993f776df786ca40510bb41f43592be2c629666
bundle_lock_sha256=361d87d23a091a40b8312bd8f091cc32759f0f340ca3fb13f4628c06ebc0def2
bundle_files_sha256=11f629b12b561f0d45235613c6bed085cd9f6975ffda4052572f86c1898a461c
physical_validation=pass
locked_rebuild=pass
promotion_complete=yes
```

The offline rebuild reproduced the exact accepted final package inventory. Its
compressed image SHA-256 is
`dd2538723b8a1bc0f7ccbffabf07ab0811aa4b55db5ea85c2198e962b3672dcf`,
which intentionally differs from the accepted image because byte-identical image
output is not required. The exact Stage 12F/12G image (`d90cf0...`) remains the
hardware-tested artifact to publish.

Earlier failed promotion attempts proved rollback behavior while two stale-audit
issues were corrected. Exact inspection established that the AXP20x source lock
is immutable historical provenance while the Stage 9B validator contained real
hard-coded 6.18.60 assumptions; the final code preserves that distinction.

A post-promotion formatting correction restored explanatory comments in the
accepted lock files and made future promotion generation preserve them. No
accepted identity changed and no rebuild/retest was required.

### Stage 12 — COMPLETE

The complete maintenance lifecycle is now proven:

`discover -> compatibility validate -> build -> physical validation -> promotion -> offline reproducibility proof -> stop`

The stable Arch baseline is frozen at `6.18.64-1-uconsole`. No additional kernel
update is part of this cycle.

### NEXT — publish stable Arch v1.0.0

The pre-publication exposure audit is complete. Results:

- current tracked tree: no credentials, private keys, tokens, personal email
  addresses, SSIDs, hostnames, local home paths or meaningful private-network
  configuration found;
- complete 81-commit history: no secret material found; commit identity uses a
  GitHub noreply address;
- historical `192.168.0.1` documentation references are accepted as benign
  generic RFC1918 context and do not justify rewriting history;
- no large accidental blobs, Git LFS dependency, submodules or tracked image /
  package build artifacts were found;
- repository license/provenance presentation is being made explicitly
  multi-license before publication.

The first public project version is **`v1.0.0`**. This is a project release
number and must not be presented as an Arch Linux ARM release date.

Public artifact name:

```text
uconsole-archlinuxarm-v1.0.0-cm4.img.zst
```

It must be a byte-for-byte rename/copy of the exact Stage 12F/12G artifact with
compressed SHA-256
`d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19`.
Do not recompress the image and do not substitute the later locked-rebuild proof
image.

Remaining publication sequence:

1. commit this `v1.0.0` release-preparation checkpoint on `main`;
2. create and push annotated tag `v1.0.0` at that exact stable commit;
3. change the GitHub repository visibility from private to public;
4. create the GitHub `v1.0.0` release from the tag;
5. upload the renamed exact validated image and checksum file;
6. verify the public repository, release page and downloadable image from a
   logged-out/public perspective;
7. create a dedicated ARMtix/Artix development branch only after publication
   is confirmed.

---

## 13. Continuation instructions

In a fresh ChatGPT conversation:

1. provide this handoff file;
2. provide/link the current GitHub repository;
3. ask the assistant to inspect repository state before changing anything;
4. continue from **Current step**;
5. do not redo completed stages without evidence of a problem;
6. preserve the small-patch, upstream-first, distro-neutral architecture;
7. update this exact handoff filename whenever a stage completes.

---

## 14. Change log

### 2026-11-22 — Revision 6.20 / v1.0.0 public-release preparation

- Completed the pre-publication exposure audit of the current tree and complete
  81-commit history; no secret material requiring removal/history rewrite was
  found.
- Selected conventional project version `v1.0.0` for the first stable public
  Arch release.
- Defined public artifact name `uconsole-archlinuxarm-v1.0.0-cm4.img.zst` as a
  rename only of the exact physically validated Stage 12F/12G image.
- Preserved compressed SHA-256 `d90cf0...` and raw SHA-256 `a2daeb...` as the
  public release identities.
- Added explicit multi-license/public provenance presentation so the root MIT
  license cannot be mistaken for relicensing GPL kernel-facing material.
- Set tag/public visibility/GitHub Release publication as the remaining work
  before ARMtix/Artix development begins.

### 2026-11-22 — Revision 6.19 / Stage 12 final closeout

- Recorded successful Stage 12H promotion of the exact physically validated
  `6.18.64-1-uconsole` candidate.
- Promoted accepted baseline to `archlinuxarm-stage12h-2026-11-22`.
- Recorded exact accepted package, image, bundle and final-inventory identities.
- Recorded successful network-disabled locked rebuild with exact package
  inventory reproduction and reaffirmed that byte-identical image output is not
  required.
- Distinguished the physically tested `d90cf0...` image from the later
  `dd2538...` locked-rebuild proof image for future public distribution.
- Closed Stage 12 and froze the stable Arch baseline on `main`.
- Set public-repository/release preparation as the next checkpoint.
- Deferred ARMtix/Artix OpenRC implementation until publication is complete and
  required future work to occur on a dedicated development branch.

### 2026-11-22 — Revision 6.18 / Stage 12H provenance/validator correction

- Recorded two Stage 12H promotion attempts reaching the stale accepted-kernel
  audit and rolling back cleanly before promotion was retained.
- Inspected the exact reported references rather than treating them uniformly.
- Confirmed `kernel/sources/axp20x-battery.lock` is immutable Stage 5 provenance:
  its Raspberry Pi base commit must remain the original audited source identity.
- Confirmed `scripts/validate-arch-rootfs-integration.sh` contained three active
  hard-coded `6.18.60-1` assumptions.
- Generalized Stage 9B to derive package/kernel release from the authoritative
  PKGBUILD and cross-check its version/commit against `kernel/source.lock`.
- Excluded `kernel/sources/*.lock` provenance records from the Stage 12H stale
  accepted-kernel audit while retaining the audit for active scripts/config.
- No accepted pin, package, image or baseline changed in either failed run.

### 2026-11-22 — Revision 6.17 / Stage 12H initial stale-reference audit correction

- Replaced the promotion audit's regex version match with literal `grep -F`
  checks after the first failed promotion attempt.
- A second promotion attempt proved that matching mode was not the underlying
  issue: the same two paths were reported and required exact code inspection.
- Rollback restored the prior accepted state and removed the unaccepted promoted
  bundle after both attempts.

### 2026-11-22 — Revision 6.16 / Stage 12H promotion tooling

- Added machine-readable Stage 12G physical-validation evidence for the exact
  `6.18.64-1-uconsole` candidate package/image hashes.
- Added atomic Stage 12H promotion tooling with rollback on any failed gate.
- Promotion derives a new accepted baseline bundle from unchanged accepted
  userspace plus the exact physically validated kernel package.
- Promotion runs a network-disabled locked rebuild and requires exact promoted
  package inventory before it is retained.
- Generalized baseline capture/verification and locked Stage 10 rootfs/image
  defaults to derive kernel identity from `release-baseline.lock`.
- Defined Stage 12H as the terminal step of this update cycle; no later kernel
  is evaluated unless a new cycle is explicitly started.

### 2026-11-22 — Revision 6.15 / Stage 12F and Stage 12G complete

- Recorded successful real Stage 12F build of `linux-uconsole-6.18.64-1` from
  Raspberry Pi Linux commit `a40f735325391b1705161b07f36ed45e1bf04521`.
- Preserved accepted Stage 11 userspace exactly apart from the intentional
  `linux-uconsole` replacement.
- Recorded candidate package SHA-256
  `e4eb51edf12d7022ee96a5599ac7643dc665afd02aad1ecdd074c3e108674206`.
- Recorded candidate compressed image SHA-256
  `d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19`.
- Recorded successful Stage 12G physical validation on the uConsole: boot,
  brightness, Wi-Fi/DHCP/routing/DNS, Bluetooth, USB storage, battery
  reporting, speaker/headphone audio and live switching, power-key ignore
  policy, reboot and shutdown all passed.
- No accepted kernel/rootfs/baseline pin changed in this closeout checkpoint.
- Set Stage 12H kernel-candidate promotion as the next bounded step.

### 2026-11-22 — Revision 6.14 / Stage 12F temporary pacman-policy correction

- First real Stage 12F run completed accepted-rootfs reconstruction and
  validation, then stopped before candidate-kernel replacement.
- Diagnosed the failure as a lifecycle mismatch: Stage 10 correctly removes its
  temporary `/etc/pacman.stage12-locked.conf` after locked composition, but
  Stage 12F incorrectly expected that file to remain.
- Stage 12F now creates and cleans up its own temporary offline pacman
  configuration solely around candidate-kernel replacement.
- Synthetic kernel-only replacement validation passes with no Stage 10 locked
  pacman configuration present and confirms the Stage 12F temporary config is
  absent afterward.
- No accepted pin, Stage 10 behavior, userspace inventory policy, or promotion
  state changed. Stage 12F remains local-build pending.

### 2026-11-22 — Revision 6.13 / Stage 12E complete, Stage 12F candidate build implementation

- Recorded successful local Stage 12E validation of Raspberry Pi Linux 6.18.64
  at `a40f735325391b1705161b07f36ed45e1bf04521`.
- Confirmed all five uConsole patches apply with zero fuzz, required config
  resolves, kernel prepare passes, and CM4/uConsole DT composition passes.
- Added Stage 12F real candidate package/image build path.
- Stage 12F deliberately reconstructs the accepted Stage 11 userspace from the
  preserved baseline bundle offline, then replaces only `linux-uconsole`.
- Added exact userspace-inventory equality gate excluding only the intentionally
  changed kernel package version.
- Added candidate-specific Stage 10 image metadata/name overrides while keeping
  default Stage 10/locked-rebuild behavior unchanged.
- Candidate package, image, final inventory, builder metadata and hashes remain
  outside Git under ignored build/output trees.
- Accepted kernel/rootfs/baseline pins remain unchanged.
- Stage 12F is local-build pending; physical validation and promotion remain
  explicitly not performed.

### 2026-11-22 — Revision 6.12 / Stage 12E container networking correction

- The second local Stage 12E run reached the disposable Arch builder but
  `pacman -Syu` could not resolve Arch package mirrors through normal rootful
  Podman container networking.
- Verified host DNS resolution independently.
- Verified the expected rootful builder image ID
  `3f2743e9ec055adcc0ae9c3a4b055aad2daca4c48aedf3198c8213efe440eda8`.
- Verified normal rootful Podman used the host LAN resolver but did not
  resolve the mirror during the test.
- Verified the same rootful container resolves correctly with
  `--network=host`.
- Stage 12E now uses host networking only for the deliberately online
  candidate/toolchain-fetch container.
- Repository mount remains read-only; accepted kernel/rootfs/baseline pins and
  target-image networking policy remain unchanged.
- Stage 12E remains local-validation pending for 6.18.64.

### 2026-11-22 — Revision 6.11 / Stage 12E containerized toolchain correction

- First local Stage 12E run stopped immediately because the host did not have
  `aarch64-linux-gnu-gcc` installed.
- Corrected the implementation to match the established project architecture:
  Stage 12E now executes inside the already-local Arch `base-devel` builder
  image rather than requiring a host cross toolchain.
- The repository is mounted read-only; only ignored `build/update-candidate/`
  storage is writable.
- Candidate mode permits live toolchain package installation inside the
  disposable container; the builder image ID and GCC/binutils/DTC versions are
  recorded in the candidate report.
- The launcher refuses to silently pull a moving builder image tag.
- Accepted kernel/rootfs/baseline pins remain unchanged.
- Stage 12E remains local-validation pending for 6.18.64.

### 2026-11-21 — Revision 6.10 / Stage 12D complete, Stage 12E kernel candidate validator

- Recorded successful Stage 12D rerun after the SIGPIPE correction.
- Confirmed Arch Linux ARM rootfs `2026.08` remains current.
- Detected Raspberry Pi `rpi-6.18.y` candidate `6.18.64` at
  `a40f735325391b1705161b07f36ed45e1bf04521`.
- Confirmed the read-only checker left repository state unchanged.
- Added explicit/non-promoting Stage 12E kernel candidate validator.
- Candidate work is isolated under ignored `build/update-candidate/`.
- Candidate PKGBUILD metadata is modified only in the staged workspace.
- Reused the actual `prepare()` path so patches remain strict `--fuzz=0`.
- Added resolved-config, kernel-prepare, DT build/application and Git-state
  validation.
- Deliberately stopped before full kernel/Image/modules/package/image build.
- No accepted source pin, package metadata, baseline lock or release artifact
  changed.
- Stage 12E remains open pending local validation of the exact 6.18.64
  candidate.

### 2026-11-21 — Revision 6.9 / Stage 12D update checker candidate

- Added read-only `scripts/check-updates.sh`.
- Added local consistency checks across accepted baseline, rootfs lock, kernel
  source lock and `linux-uconsole` package metadata.
- Added Arch Linux ARM rootfs candidate discovery using the configured mirror,
  with a sidecar-only fallback when directory listing is unavailable.
- Added Raspberry Pi `rpi-6.18.y` branch-head commit/version discovery.
- Added Git-status before/after protection to prove the checker does not mutate
  repository state.
- Upstream query failure is distinct from no-update state.
- No pin, build logic, package transaction or accepted baseline changed.
- Stage 12D remains open pending one local execution and output review.

### 2026-11-21 — Revision 6.8 / Stage 12C complete

- Recorded successful corrected offline locked rebuild.
- Confirmed exact final package inventory hash equality with the accepted Stage
  11 baseline.
- Confirmed reconstruction used preserved inputs with container networking
  disabled and no live `pacman -Syu`.
- Recorded builder image ID
  `3f2743e9ec055adcc0ae9c3a4b055aad2daca4c48aedf3198c8213efe440eda8`.
- Recorded locked-rebuild compressed image SHA-256
  `a1f5bd497a4e033c53e44e92b2c536f536458f74767700143c7159b20a721eec`.
- Reaffirmed that byte-identical image output is not the Stage 12 acceptance
  contract.
- Marked Stage 12C complete and set Stage 12D read-only update checker next.

### 2026-11-21 — Revision 6.7 / Stage 12C2 locked-rebuild cleanup correction

- Recorded first local offline locked-rebuild result.
- Rootfs reconstruction, pacman database validation and `linux-uconsole` file
  validation passed before cleanup.
- Diagnosed failure as shared Stage 10 cleanup trying to delete preserved
  rootfs archive/sidecars from the read-only accepted baseline mount.
- Made rootfs-input cleanup mode-aware: locked mode preserves immutable
  baseline inputs; normal/update mode retains existing temporary-download
  cleanup.
- Accepted baseline bundle remains unchanged.
- Set corrected offline locked-rebuild rerun as the next action.

### 2026-11-21 — Revision 6.6 / Stage 12C2 baseline lock promotion and locked-rebuild implementation

- Recorded the successful accepted-baseline capture identity and package counts
  in `release-baseline.lock`.
- Strengthened bundle verification so Git anchors both `bundle.lock` and the
  complete `bundle-files.sha256` manifest.
- Added the first offline/fail-closed locked rebuild consumer.
- Locked rebuild requires the builder image to already exist locally, disables
  container networking, reuses the exact accepted kernel package and consumes
  only preserved baseline package payloads.
- Added exact final package name/version inventory comparison as the locked
  rebuild acceptance gate.
- Kept locked-rebuild artifacts separate from the accepted Stage 10 output.
- Corrected future baseline capture performance by extracting the pinned-rootfs
  pacman database in one archive pass.
- The already captured accepted bundle remains valid; no recapture is required.
- Set one local locked-rebuild execution as the next validation step.

### 2026-11-21 — Revision 6.5 / Stage 12C1 baseline-capture tooling

- Added fail-closed accepted-baseline capture tooling without changing Stage 10
  image construction behavior.
- Capture validates the retained final Stage 10 image/kernel identities against
  `release-baseline.lock` before accepting the workspace as a source.
- Capture reacquires and authenticates the pinned 2026.08 rootfs, records both
  rootfs and final package inventories, and derives exact added/changed and
  removed package sets.
- Exact package payloads are selected from the accepted final workspace pacman
  cache by `.PKGINFO` name/version identity; missing payloads are a hard failure.
- The exact validated `linux-uconsole` package is preserved separately.
- Added complete bundle file hashing plus a standalone verifier that proves
  baseline identity and package-payload coverage.
- Baseline bundles live under the existing gitignored `out/baselines/` tree and
  are never overwritten by the capture tool.
- Set Stage 12C2 local capture and manifest/lock promotion as next.

### 2026-11-21 — Revision 6.4 / Stage 12B release/update policy complete

- Added `image/archlinuxarm/release-baseline.lock` for the accepted Stage 11
  artifact identity.
- Defined `locked-rebuild` as fail-closed and free of live package/kernel
  refreshes.
- Defined `update-candidate` as the only mode allowed to consume live upstream
  state.
- Defined userspace, rootfs-base, kernel and project-policy update classes.
- Defined explicit baseline promotion after automated and targeted physical
  validation.
- Chose a project-owned baseline input bundle outside Git rather than relying
  on third-party historical package mirrors.
- Clarified that locked rebuilds reuse the accepted kernel package; exact
  kernel toolchain capture is required for new kernel packages, not ordinary
  baseline reconstruction.
- Set Stage 12C baseline inventory/payload capture as next, with priority on
  preserving the current final build workspace package cache before another
  clean build.

### 2026-11-21 — Revision 6.3 / Stage 12A input audit complete

- Audited the current Stage 10/11 build from the reconstructed committed
  checkpoint state without changing build behavior.
- Classified exact kernel/rootfs/image/hardware inputs as pinned.
- Identified the final target `pacman -Syu` transaction as the highest-impact
  rolling input: the 2026.08 archive is pinned, but the final userspace package
  versions are not.
- Identified the mutable `archlinux:base-devel` container plus its own
  `pacman -Syu` as a second rolling layer affecting kernel toolchain identity.
- Recorded local host tools and GitHub runner/action versions as additional
  non-immutable build-environment inputs.
- Recorded the PKGBUILD `SKIP` checksums for immutable remote commit URLs as an
  integrity-hardening gap.
- Confirmed that official Arch Linux ARM mirrors track current packages and
  that historical snapshot services discussed by the community are
  third-party; Stage 12 should not depend on them for exact rebuilds.
- Added `docs/STAGE12_UPDATE_REBUILD.md`.
- Set Stage 12B locked-rebuild versus intentional-update policy as next.

### 2026-11-21 — Revision 6.2 / Stage 11 complete

- Rebuilt the final image with the permanent `ClockworkPI` brightness-device
  name correction.
- Recorded final raw image SHA-256
  `002eee704787770ad873f1cd56789df4cf56c86655895148ebbe4c03320b9a86`.
- Recorded final compressed image SHA-256
  `aa0d9c961579e12e5eb9991086d0c2b0a91670e07cc4c8cd8711f0316b0bce7a`.
- Flashed and booted the final artifact on the physical uConsole.
- Confirmed `Fn + <` and `Fn + >` work immediately from the clean rebuilt
  image with no live edit or manual service restart.
- Closed Stage 11 physical hardware validation.
- Set Stage 12 reproducible update/rebuild path as the next project stage.

### 2026-11-21 — Revision 6.1 / Stage 11 rebuilt-image regression and brightness-name correction

- Physically confirmed the GPIO10 no-pull correction: headphone insertion now
  mutes speakers and unplugging restores them without manual `pinctrl`.
- Physically confirmed `HandlePowerKey=ignore`: a brief power-button press now
  does nothing.
- Confirmed normal BlueZ discovery with `bluetoothctl -t 20 scan on`; the
  earlier external `timeout` wrapper was a misleading test and no Bluetooth
  workaround is required.
- Isolated the remaining brightness failure to a case-sensitive input-device
  name mismatch: the kernel reports `ClockworkPI uConsole Consumer Control`,
  while the handler searched for `ClockworkPi ...`.
- Applied the exact capitalization correction live; after restarting the
  service, both brightness keys worked immediately.
- Updated the permanent handler to match the physically observed kernel name.
- Reduced the remaining validation to one final rebuilt-image brightness-key
  regression check.

### 2026-11-21 — Revision 6.0 / Stage 11 physical pass and consolidated image corrections

- Completed the practical Stage 11 physical hardware matrix on the locally
  built Arch Linux ARM image.
- Physically validated speaker/headphone audio, battery/charging transitions,
  power-button input, Bluetooth kernel/RF discovery, USB storage, direct
  backlight control and brightness-key input events in addition to the earlier
  boot/display/network results.
- Isolated headphone switching to missing GPIO10 no-pull boot policy and added
  `gpio=10=ip,np`; left the proven amplifier-switch driver unchanged.
- Added a console-only brightness-key service that consumes the proven
  `KEY_BRIGHTNESSUP/DOWN` events and adjusts the working backlight sysfs
  control; no graphical stack was added.
- Added an Arch logind drop-in with `HandlePowerKey=ignore` so a brief power-key
  tap does not immediately shut down the device; left the working PMIC/kernel
  input path unchanged.
- Recorded Bluetooth lower-level RF discovery as physically proven and
  deliberately avoided a speculative BlueZ pin/downgrade; interactive
  `bluetoothctl` remains a focused rebuild regression check.
- Added `docs/STAGE11_PHYSICAL_VALIDATION.md` as the durable evidence/fix
  handoff for this physical pass.
- Set one consolidated local rebuild and targeted regression pass as next.

### 2026-11-20 — Revision 5.9 / unattended local-build sudo handling

- First long local build reached image composition after the initial sudo
  timestamp had expired and stopped waiting for a second password prompt.
- Local/shared host orchestration now authenticates sudo once before any
  long-running work and refreshes the timestamp every 60 seconds for the
  duration of the build.
- All subsequent privileged calls in the host script use non-interactive sudo,
  so a credential problem fails immediately instead of blocking unattended.
- No kernel, target rootfs, image contents, package set or networking policy
  changed.


### 2026-11-20 — Revision 5.8 / local Podman bridge-DNS correction

- First local image-build attempt failed before kernel compilation because
  rootful Podman's default bridge could not resolve Arch package mirrors.
- Host DNS was healthy, and `sudo podman run --network host ...` resolved and
  synchronized Arch repositories successfully.
- Local Podman image builds now add `--network host`; Docker/GitHub Actions
  behavior is unchanged.
- No kernel, rootfs package-set, or target image networking policy changed.


### 2026-11-10 — Revision 5.7 / shared local Podman image-build path

- Recorded GitHub-hosted Actions quota exhaustion as an infrastructure blocker,
  not a project/build result.
- Added `scripts/build-stage10-host.sh` as the shared host-level image-build
  entry point.
- Local Arch builds use rootful Podman; GitHub Actions uses Docker but now calls
  the same orchestration script.
- Rootful Podman is intentional so target rootfs numeric UID/GID ownership is
  preserved rather than remapped through a rootless user namespace.
- Added an input-keyed local cache for completed `linux-uconsole` packages.
  Image/rootfs retries can therefore reuse an unchanged kernel package instead
  of recompiling the kernel after failures later in the pipeline.
- Added optional `UCONSOLE_PREBUILT_KERNEL_PACKAGE` support to the rootfs builder;
  the package is still subjected to the existing PKGINFO contract checks before
  installation.
- Added `docs/LOCAL_IMAGE_BUILD.md` with Arch/Podman prerequisites, output paths,
  cache behavior and force-rebuild controls.
- Local build outputs remain under already-gitignored `build/` and `out/` trees.
- Current unvalidated build correction remains the Stage 11 pacman sysroot
  keyring-path change from revision 5.6; local image construction is now the
  next validation path.



### 2026-11-09 — Revision 5.6 / CI pacman sysroot keyring path correction

- Recorded the next console-usability image-build failure: the temporary pacman
  keyring was initialized successfully outside the target root, but the
  subsequent `pacman --sysroot` transaction still reported `Public keyring not
  found`, `keyring is not writable`, and `required key missing from keyring`.
- Root cause: the build keyring lived under the outer Docker work directory,
  while `pacman --sysroot` operates from the staged target root. The explicitly
  supplied external GPG path was therefore not the correct keyring location for
  the target-root transaction.
- Moved the temporary verification keyring to the staged target's normal
  `/etc/pacman.d/gnupg` location, initialize/populate it there before package
  operations, and let `pacman --sysroot` use its normal target GPGDir. Package
  signature verification remains enabled.
- Added pre-transaction checks for the generated public keyring/trust database.
- After all pacman operations and package-database validation complete, the
  builder removes the temporary target GPG directory so no CI-generated private
  key ships in the image. The existing first-boot service remains responsible
  for creating a unique pacman keyring on each installed uConsole.
- No package-set, NetworkManager, DNS, Landlock kernel, console logging, boot,
  partition, or hardware-support policy changed in this correction.

### 2026-11-09 — Revision 5.5 / CI pacman keyring initialization ordering fix

- Recorded the next console-usability image-build failure: the kernel package
  built successfully, but CI stopped while preparing the build-host pacman
  keyring because `pacman-key --populate` was invoked before a local key had
  been created. Pacman reported `There is no secret key available to sign
  with` and explicitly required `pacman-key --init`.
- Corrected the build-only keyring sequence to create an isolated temporary
  GnuPG directory under the rootfs-builder work directory, run `pacman-key
  --init`, then populate both the Arch and Arch Linux ARM distribution trust
  roots before any target-rootfs package transaction.
- Kept this keyring strictly build-local. The generated image continues to
  create its own unique pacman keyring on first boot through
  `uconsole-pacman-keyring-init.service`; no CI private key is copied into the
  image.
- No target package set, NetworkManager policy, Landlock kernel policy, or
  console logging policy changed in this correction.

### 2026-11-09 — Revision 5.4 / CI pacman keyring and first-boot trust correction

- Recorded the second Stage 11 console-usability image-build failure after the
  Landlock builder correction: repository synchronization and package downloads
  succeeded, but the target `--sysroot` had no initialized pacman keyring and
  signature verification stopped with `keyring is not writable` /
  `required key missing from keyring`.
- Kept package signature verification enabled. The disposable x86_64 builder
  now imports the authenticated rootfs's `archlinuxarm` distribution keyring
  into the builder's own initialized pacman keyring and explicitly points the
  cross-architecture pacman transaction at that host keyring.
- Deliberately do not copy the builder's local/private signing material into
  the published image. Added `uconsole-pacman-keyring-init.service`, enabled in
  the image, to run `pacman-key --init` and populate the packaged Arch + Arch
  Linux ARM trust roots once on first boot before the login console. Each
  flashed installation therefore creates its own local pacman keyring.
- Excluded `linux-aarch64` and `uboot-raspberrypi` from the full userspace
  upgrade because the build removes them immediately afterward when installing
  `linux-uconsole`; this avoids needless download/installation work without
  weakening the rest of the rolling userspace update.

### 2026-11-09 — Revision 5.3 / CI pacman Landlock sysroot correction

- Recorded the first Stage 11 console-usability image-build failure after the
  kernel package completed successfully.
- Isolated the failure to host-side pacman running inside the disposable
  GitHub Actions Docker container: its download process could not apply a
  Landlock filesystem ruleset to the target `--sysroot`.
- Distinguished this from the target uConsole Landlock fix: the target kernel
  is not running during rootfs composition, so its `CONFIG_LSM="landlock"`
  cannot affect the builder's pacman process.
- Added `--disable-sandbox-filesystem` only to the rootfs builder's host-side
  pacman wrapper. This preserves syscall sandboxing where available and leaves
  the generated target `/etc/pacman.conf` unchanged.
- Retained normal pacman sandboxing on the booted image, backed by the uConsole
  kernel's enabled Landlock LSM.

### 2026-11-08 — Revision 5.2 / Stage 11 console-usability image correction

- Recorded that physical Wi-Fi association and IPv4 connectivity work.
- Identified missing persistent DNS/network-management ergonomics in the bare
  image as a userspace-image gap rather than a uConsole Wi-Fi driver failure.
- Added NetworkManager as the default console-friendly network manager while
  retaining `systemd-resolved` and disabling systemd-networkd services.
- Added the 13-package console/validation baseline: `networkmanager`,
  `usbutils`, `alsa-utils`, `bluez`, `bluez-utils`, `evtest`, `i2c-tools`,
  `ethtool`, `lm_sensors`, `stress-ng`, `raspberrypi-utils`, `iperf3` and
  `memtester`.
- Changed rootfs construction to perform a full `pacman -Syu` transaction when
  installing that package set, avoiding unsupported partial upgrades against
  the pinned rootfs's aging repository metadata.
- Recorded the pacman 7 sandbox failure and physical proof that Landlock works
  when activated; added `CONFIG_LSM="landlock"` to the kernel configuration.
- Made console log level 3 part of the image policy to keep routine kernel
  messages from overwriting tty1 while preserving them in logs.
- No graphical environment or GUI-only management package was added; the image
  remains a console-first starting point.

### 2026-11-06 — Revision 5.1 / corrected Stage 10 physical revalidation PASS

- Recorded successful corrected Stage 10 CI workflows.
- Preserved and independently verified the corrected artifact ZIP, kernel
  package, raw image and compressed-image SHA-256 values.
- Recorded a fresh flash to clean media with no post-build modification.
- Confirmed untouched physical boot to visible Arch Linux ARM login console.
- Confirmed interactive login succeeded.
- Confirmed live `panel_cwu50`, `ocp8178_bl`, VC4/DRM, DSI connector and
  backlight-class state.
- Closed the Stage 10 display/module-integration correction as physically
  validated and moved the immediate project focus to the broader Stage 11
  hardware matrix.
- Added no photos, captured device logs, user/host identifiers or other PII to
  the repository; only textual validation conclusions and non-personal
  artifact identities were recorded.


### 2026-11-06 — Revision 5.0 / Stage 10 physical display/module correction

- Recorded the first physical Stage 10 boot and official-image control test.
- Confirmed hardware/display path works with the official ClockworkPi image.
- Confirmed the custom Stage 10 image boots Linux/userspace despite the black
  display.
- Diagnosed missing target kmod metadata after the intentionally hook-suppressed
  cross-architecture pacman transaction.
- Confirmed `panel-cwu50.ko.xz` and `ocp8178_bl.ko.xz` were present but could
  not be resolved before `depmod`.
- Physically proved that `gpio=9=op,dh` plus target-root `depmod` restores the
  visible CWU50/OCP8178/VC4/DRM display stack and reaches the Arch login prompt.
- Folded GPIO9 assertion and explicit host-side `depmod` into the Stage 10
  builders.
- Added rootfs/image gates for generated module metadata and module aliases.
- Marked Stage 11 physical validation in progress, with fresh corrected-image
  CI/physical revalidation as the immediate bounded next step.
- Preserved kernel/overlay/package/rootfs/partition identities and public-history
  privacy policy.


### 2026-11-06 — Revision 4.9 / Stage 10 complete

- Recorded successful completion of the first real partitioned microSD image.
- Confirmed deterministic MBR/PARTUUID and FAT/ext4 construction.
- Confirmed populated root/boot filesystems and package/boot integrity.
- Confirmed FAT/ext4 filesystem checks.
- Confirmed zstd compression and compressed-image integrity.
- Confirmed raw/compressed SHA-256 generation, manifest generation and exact
  kernel-package preservation.
- Confirmed workflow artifact upload.
- Marked Stage 10 complete.
- Set bounded physical uConsole validation as next.
- Preserved privacy/public-history policy.


### 2026-11-06 — Revision 4.8 / Stage 10 FAT label correction

- Recorded successful deterministic partition-table construction.
- Confirmed exact boot/root partition geometry.
- Recorded the non-fatal sfdisk reread warning followed by successful explicit detach/reattach with partition scanning.
- Diagnosed FAT label-length failure: `UCONSOLEBOOT` was 12 characters.
- Changed boot FAT label to `UCONBOOT` (8 characters).
- Changed no partition/PARTUUID/rootfs/kernel/package/boot behavior.
- Stage 10 remains CI-pending.


### 2026-11-06 — Revision 4.7 / Stage 10 sfdisk compatibility correction

- Recorded first Stage 10 host image-builder failure.
- Diagnosed unsupported sfdisk `--sector-size` option on the Ubuntu 24.04 runner.
- Moved explicit 512-byte logical-sector configuration to the loop device via `losetup --sector-size`.
- Added pre/post partition-scan sector-size verification with `blockdev`.
- Kept all partition geometry, disk/PARTUUID identity and image policy unchanged.
- Stage 10 remains CI-pending.


### 2026-11-06 — Revision 4.6 / Stage 10 image candidate

- Added concrete 8 GiB image geometry to the deterministic layout contract.
- Added fixed filesystem labels/IDs.
- Added Stage 10 authenticated integrated-rootfs builder.
- Added host-VM raw image constructor using loop devices, FAT32 and ext4.
- Added package/boot/partition/filesystem validation.
- Added zstd image artifact, raw/compressed checksums and manifest.
- Added exact linux-uconsole package to workflow artifact.
- Preserved dynamic `nproc` parallelism and 360-minute timeout.
- Added explicit statement that Stage 10 is structurally reproducible but does
  not yet claim byte-identical image checksums across independent builds.
- Stage 10 remains CI-pending.


### 2026-11-06 — Revision 4.5 / Stage 9C complete

- Recorded successful completion of all corrected Stage 9C workflows.
- Marked deterministic image identity, cmdline, fstab, firmware boot policy and direct-root kernel prerequisites as proven.
- Confirmed no U-Boot and no firmware-loaded initramfs for the first image.
- Preserved expansion-UART/no-serial-console policy.
- Set Stage 10 first partitioned microSD image construction as next.
- Retained dynamic `nproc` parallelism, maximum CI timeout and public-history privacy policy.


### 2026-11-05 — Revision 4.4 / Stage 9C PARTUUID validator correction

- Recorded the first Stage 9C CI failure.
- Diagnosed raw `UUID=` substring matching as a false positive against valid
  `PARTUUID=` entries.
- Made unstable-addressing validation token-boundary aware.
- Changed no boot policy, PARTUUID, cmdline, fstab, kernel config or package
  input.
- Stage 9C remains CI-pending.


### 2026-11-05 — Revision 4.3 / Stage 9C candidate

- Defined deterministic DOS/MBR image identity `0x55434f4e`.
- Defined stable boot/root PARTUUIDs.
- Added final one-line Raspberry Pi kernel command line.
- Selected direct ext4 microSD root boot without firmware-loaded initramfs.
- Preserved `8250.nr_uarts=1` as explicit boot policy while leaving the
  expansion UART free of serial-console use.
- Added deterministic `/etc/fstab` policy.
- Added exact pinned-kernel checks for built-in microSD/ext4 root support.
- No kernel source or PKGBUILD changed.
- Stage 9C remains CI-pending.


### 2026-11-05 — Revision 4.2 / Stage 9B complete

- Recorded successful final Stage 9B workflow.
- Confirmed real aarch64 package build and complete target pacman transition.
- Confirmed `pacman -Dk`.
- Confirmed `pacman -Qk linux-uconsole`: 2765 files, 0 missing.
- Confirmed `boot/kernel8.img` in authoritative local package file records.
- Confirmed `boot/config.txt` is deliberately unowned by packages.
- Marked Stage 9B complete.
- Set Stage 9C boot-command-line/initramfs policy as next.
- Retained dynamic `nproc` CPU parallelism and maximum CI timeout policy.


### 2026-11-05 — Revision 4.1 / Stage 9B local-database ownership correction

- Recorded successful real package build and complete target package
  transaction through `pacman -Dk` and `pacman -Qk`.
- Recorded `linux-uconsole`: 2765 files, 0 missing.
- Removed dependence on exact human-readable `pacman -Ql` formatting.
- Validate `boot/kernel8.img` directly in the installed linux-uconsole local
  package `files` record.
- Continue proving `boot/config.txt` is image-policy-owned by requiring it to
  be absent from all package `files` records.
- No functional build, package, rootfs, boot or parallelism behavior changed.
- Stage 9B remains CI-pending.


### 2026-11-05 — Revision 4.0 / Stage 9B cross-architecture pacman correction

- Recorded successful real aarch64 package build and target package
  transaction evidence.
- Diagnosed foreign-architecture `ldconfig` as the source of transaction-end
  `Exec format error` messages.
- Temporarily suppress target ldconfig execution only during the two kernel
  package transactions and restore its exact mode afterward.
- Replaced incorrect `--sysroot -Qo` path ownership checks with package/local
  DB file-record checks.
- Confirmed no build parallelism restriction was introduced.
- Strengthened public-repository privacy/Git-history policy.
- Stage 9B remains CI-pending.


### 2026-11-05 — Revision 3.9 / Stage 9B workspace-permission correction

- Corrected the previous premature Stage 9B completion status.
- Recorded that the first Stage 9B run reached the real unprivileged makepkg
  invocation.
- Diagnosed `Permission denied` as `mktemp -d` parent mode `0700`, not a
  package/kernel failure.
- Made the disposable top-level work directory traversable (`0755`).
- Changed build-user creation to `--no-create-home` to avoid the harmless
  existing-home warning.
- No functional build/package/rootfs policy changed.
- Stage 9B remains validation-pending.


### 2026-11-05 — Revision 3.8 / Stage 9B complete

- Recorded successful `Validate Arch rootfs uConsole integration` workflow.
- Confirmed real aarch64 `linux-uconsole` makepkg build.
- Confirmed pacman-managed replacement of `linux-aarch64` and
  `uboot-raspberrypi`.
- Confirmed retained Raspberry Pi firmware/bootloader, mkinitcpio and
  linux-firmware packages.
- Confirmed target pacman DB and package-file integrity.
- Confirmed direct-firmware boot layout and project-owned `/boot/config.txt`.
- Marked Stage 9B complete.
- Set Stage 9C boot-command-line/initramfs policy as next.


### 2026-11-05 — Revision 3.7 / Stage 9A complete, Stage 9B candidate

- Marked Stage 9A complete after successful archive-native provenance and
  inventory validation.
- Promoted authenticated rootfs SHA-256 into `rootfs.lock`.
- Recorded the exact successful stock kernel/boot package inventory.
- Corrected the Stage 9B replacement set to include both `linux-aarch64` and
  `uboot-raspberrypi`, matching `linux-uconsole`/`linux-rpi` conflict policy.
- Added a real cross-architecture Arch `makepkg` package build.
- Added pacman-managed target-rootfs replacement using `--sysroot` and
  `--arch aarch64`.
- Added direct-firmware boot-policy installation and package/database checks.
- Stage 9B remains validation-pending.


### 2026-11-05 — Revision 3.6 / Stage 9A archive-native audit correction

- Recorded successful cryptographic authentication of the pinned 2026.08
  rootfs with the exact official Arch Linux ARM signing fingerprint.
- Recorded SHA-256
  `f10903be472e2662e110f0f7bae2750a30914ce3dc0fcd38ec85d3405d8c8967`.
- Diagnosed the remaining failure as unprivileged restoration of Linux
  capability xattrs during full extraction.
- Removed full rootfs extraction from Stage 9A.
- Added archive-native structure, pacman database and boot inventory audit.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.5 / Stage 9A keyring-format correction

- Recorded that `gpgv` reached the detached signature and identified the exact
  expected Arch Linux ARM signing key.
- Diagnosed `invalid packet (ctb=2d)` as keyring representation mismatch.
- Added ASCII-armored keyring detection and `gpg --dearmor` normalization.
- Binary keyrings remain supported unchanged.
- Retained exact `VALIDSIG` signer/primary-key fingerprint validation.
- No rootfs input or trust anchor changed.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.4 / Stage 9A direct-gpgv correction

- Recorded the second Stage 9A failure as a GnuPG keyring-inspection invocation
  issue.
- Removed the redundant direct keyring-membership gate.
- Made detached `gpgv` verification authoritative.
- Required machine-readable `VALIDSIG` identity to match the official Arch
  Linux ARM fingerprint as signer or primary key.
- Added diagnostics for both gpgv status and logger output.
- No rootfs version, checksum, size, mirror, or trust anchor changed.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.3 / Stage 9A signature-validator correction

- Recorded that rootfs download, exact size, MD5 and keyring extraction passed.
- Kept the official Arch Linux ARM signing fingerprint unchanged.
- Replaced brittle GnuPG colon-output matching with explicit `fpr` field
  extraction.
- Added `gpgv --status-fd` verification and require `VALIDSIG` to report the
  exact official signing fingerprint.
- No rootfs input or trust-policy decision changed.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.2 / Stage 9A candidate

- Split Stage 9 into bounded rootfs-provenance and rootfs-integration
  checkpoints.
- Selected the versioned Arch Linux ARM Raspberry Pi AArch64 2026.08 rootfs.
- Explicitly prohibited the moving `-latest` alias as a build input.
- Added exact size, published MD5 and detached-signature validation.
- Anchored signature verification to Arch Linux ARM's official full signing
  fingerprint.
- Added structural and pacman-database inventory audit without executing
  AArch64 target binaries.
- Kept the Stage 9A workflow at GitHub's 360-minute job timeout.
- Stage 9A remains open until CI passes and reports the stock kernel/boot
  package inventory.


### 2026-11-05 — Revision 3.1 / Stage 8 complete

- Recorded successful full Stage 8 kernel/package build in approximately
  1 hour 19 minutes.
- Confirmed complete PKGBUILD `prepare()`, `build()` and `package()` paths.
- Confirmed Image, required modules, DTBs/DTBOs, overlay composition and
  package-root layout.
- Standardized long-running GitHub workflow timeout on the current platform
  maximum/default of 360 minutes.
- Added project policy to avoid lower CI timeouts unless specifically
  justified.
- Marked Stage 8 complete.
- Set Stage 9 Arch Linux ARM rootfs/image-builder integration as next.


### 2026-11-05 — Revision 3.0 / Stage 8 timeout correction

- Recorded the first Stage 8 run as a project-timeout cancellation rather than
  a compile failure.
- Increased the full-build workflow timeout from 90 to 240 minutes.
- Changed default CI build parallelism from fixed `-j2` to the runner's
  `nproc` CPU count.
- Retained an explicit positive `JOBS` override.
- No kernel source, config, patch, PKGBUILD, packaging, or validation contract
  changed.
- Stage 8 remains validation-pending.


### 2026-11-05 — Revision 2.9 / Stage 8 candidate

- Added the first complete build-only validation of the Stage 7 composition.
- Reused the actual staged PKGBUILD `prepare()`, `build()` and `package()`
  functions instead of adding a parallel build recipe.
- Added checks for kernel Image, uConsole modules, AXP20x modules, TI ADC,
  CM4 DTB and uConsole DTBO.
- Added built-DTB overlay application with `fdtoverlay`.
- Added package-root verification for kernel8.img, DTBs/DTBO, modules and
  mkinitcpio preset.
- Stage 8 remains open until the full-build workflow passes.


### 2026-11-05 — Revision 2.8 / Stage 7 complete

- Recorded successful `Validate kernel config and Arch package` workflow.
- Confirmed deterministic package staging and policy checks.
- Confirmed actual PKGBUILD `prepare()` composition against the pinned source.
- Confirmed patches 0001-0005 all apply with `--fuzz=0`.
- Confirmed the uConsole config resolves and kernel release is
  `6.18.60-1-uconsole`.
- Confirmed the composed tree passes `make prepare`.
- Marked Stage 7 complete.
- Set Stage 8 full build-only validation as the next step.


### 2026-11-05 — Revision 2.7 / Stage 7 static-assertion correction

- Diagnosed the post-staging exit as a stale validator assertion.
- Updated Stage 7 PKGBUILD checks for the corrected `ARCH=arm64` Kbuild
  commands.
- Added named assertion failures so future static-policy errors are explicit.
- No PKGBUILD, kernel config, boot policy, source pin, patch, or package
  behavior changed.
- Stage 7 remains validation-pending.


### 2026-11-05 — Revision 2.6 / Stage 7 Kbuild architecture correction

- Recorded that all five Stage 7 patches successfully composed in the actual
  PKGBUILD `prepare()` path.
- Diagnosed `ARCH=aarch64` as a shell-variable collision between the
  validator and the PKGBUILD's standard `arch=('aarch64')` declaration.
- Renamed the validator variable to `kernel_arch`.
- Made every PKGBUILD kernel `make` invocation explicitly use `ARCH=arm64`.
- No source, patch, config, boot-policy, or package-layout behavior changed.
- Stage 7 remains validation-pending.


### 2026-11-05 — Revision 2.5 / Stage 7 validator correction

- Diagnosed the initial Stage 7 CI failure as a validator false positive.
- Confirmed the only init-system match in the PKGBUILD was an explanatory
  comment.
- Changed the policy check to ignore comment-only lines while preserving the
  same ban on init-system references in executable package content.
- No package, kernel, boot-policy, source-pin, or patch behavior changed.
- Stage 7 remains validation-pending.


### 2026-11-05 — Revision 2.4 / Stage 7 candidate

- Defined the uConsole CM4 config fragment on top of `bcm2711_defconfig`.
- Added a pacman-managed `linux-uconsole` Arch Linux ARM package definition.
- Added deterministic package-workspace staging without duplicating
  authoritative kernel inputs in Git.
- Added the first Arch CM4 boot-policy fragment with KMS, uConsole overlay,
  USB host and PWM audio settings.
- Kept boot/image policy out of the kernel package and kept init-system policy
  out of the shared kernel layer.
- Added Stage 7 composition/config/package CI.
- Stage 7 remains open until that workflow passes.


### 2026-11-05 — Revision 2.3 / Stage 6 complete

- Recorded successful `Validate uConsole audio switch` workflow.
- Confirmed exact-source Kconfig/Makefile integration applies with
  `--fuzz=0`.
- Confirmed `CONFIG_UCONSOLE_AMP_SWITCH=m` resolves successfully.
- Confirmed `drivers/misc/uconsole-amp-switch.o` cross-compiles for ARM64.
- Confirmed the shared CM4 overlay remains green with the Stage 6 audio node.
- Marked Stage 6 complete.
- Set Stage 7 kernel configuration and Arch packaging as the next step.


### 2026-11-05 — Revision 2.2 / Stage 6 integration-patch correction

- Recorded that Stage 6 driver/overlay policy checks passed.
- Rebuilt Kconfig integration from exact CI-emitted lines.
- Narrowed the Makefile hunk to the exact two adjacent lines shown by CI,
  removing the mismatching `CONFIG_ATMEL_SSC` context.
- Improved validator diagnostics for the integration anchors.
- No driver, overlay, or functional design changes were made.
- Stage 6 remains validation-pending.


### 2026-11-04 — Revision 2.1 / Stage 6 candidate

- Audited uConsole CM4 audio routing and PotatoMania's automatic amplifier
  switch.
- Confirmed GPIO10 HP_DET, GPIO11 PA_EN and GPIO12/13 PWM audio roles.
- Kept stock Raspberry Pi `audremap,pins_12_13` for signal routing.
- Added a narrow project-owned threaded-IRQ amplifier-switch driver.
- Added semantic GPIO properties to the cleaned uConsole overlay.
- Avoided firmware GPIO11 forcing, userspace polling and the historical
  hard-IRQ `*_cansleep()` pattern.
- Added Stage 6 provenance, CI validation and design documentation.
- Stage 6 remains open until driver and overlay CI pass.


### 2026-11-04 — Revision 2.0 / Stage 5 complete

- Recorded successful `Validate AXP20x battery delta` workflow.
- Confirmed the final exact-block patch applies with `--fuzz=0` to the pinned
  Raspberry Pi Linux 6.18.60 source.
- Confirmed the minimal inline AXP221 design-capacity logic compiles for ARM64.
- Retained the zero replaceable-pack defaults and narrow Stage 5 scope.
- Marked Stage 5 complete.
- Set Stage 6 audio/headphone switching as the next step.


### 2026-11-04 — Revision 1.9 / Stage 5 exact-block correction

- Replaced reconstructed probe-function context with the exact four-line block
  emitted by CI from the pinned source.
- Generated unified-diff line counts programmatically to avoid malformed
  patch metadata.
- Removed the helper function and kept the design-capacity write inline.
- Reconfirmed no MFD change is required.
- Stage 5 remains validation-pending.


### 2026-11-04 — Revision 1.8 / Stage 5 single-hunk correction

- Removed cross-hunk offset dependence entirely.
- Colocated the design-capacity helper with the probe function.
- Rebuilt Stage 5 as exactly one contiguous patch hunk.
- Added validator enforcement that the patch contains exactly one hunk.
- Functional scope is unchanged; validation remains pending.


### 2026-11-04 — Revision 1.7 / Stage 5 probe-hunk correction

- Recorded that the Stage 4 overlay workflow remains green.
- Isolated the remaining Stage 5 failure to line-location metadata for the
  probe insertion hunk.
- Regenerated both hunks using real pinned 6.18.60 source-scale positions.
- Added exact helper/probe diagnostics to the validator.
- Stage 5 functional scope is unchanged and remains validation-pending.


### 2026-11-04 — Revision 1.6 / Stage 5 CI correction

- Fixed the Stage 4 overlay validator to expect the Stage 5 zero-capacity
  defaults.
- Rebuilt the AXP221 design-capacity patch from exact pinned 6.18.60 source
  neighborhoods.
- Removed the unnecessary MFD/regmap modification after confirming stock
  AXP22x already allows E0/E1 writes.
- Reduced Stage 5 to a single changed kernel source/object:
  `drivers/power/supply/axp20x_battery.c`.
- Stage 5 remains validation-pending until both workflows pass.


### 2026-11-04 — Revision 1.5 / Stage 5 candidate

- Audited stock 6.18.60 against AK-Rex, ClusterM, historical ClockworkPi and
  AXP228 fuel-gauge behavior.
- Selected only AXP221 design-capacity register programming as the justified
  kernel delta.
- Kept calibration, synthetic energy reporting, writable charge controls and
  unrelated PMIC policy side effects out of scope.
- Changed replaceable-pack design capacity/energy defaults to zero.
- Updated the Stage 4 validator for the refined shared-overlay policy.
- Added Stage 5 provenance, validator, CI workflow and design report.
- Stage 5 remains open until ARM64 object compilation passes.


### 2026-11-04 — Revision 1.4 / Stage 4 complete

- Recorded successful `Validate uConsole CM4 overlay` workflow.
- Confirmed the project-owned overlay compiles to a DTBO against the pinned
  Raspberry Pi Linux 6.18.60 tree.
- Confirmed the compiled overlay applies successfully to the compiled CM4 base
  DTB using `fdtoverlay`.
- Confirmed the compiled overlay retains the expected CWU50 and OCP8178
  structure.
- Marked Stage 4 complete.
- Set Stage 5 minimal AXP20x battery/fuel-gauge work as the next step.


### 2026-11-04 — Revision 1.3 / Stage 4 candidate

- Added a project-owned cleaned CM4 uConsole device-tree overlay.
- Pinned AK-Rex structural provenance and an immutable postmarketOS regulator
  mapping reference.
- Kept OuinOuin74 as a design reference rather than a build dependency.
- Selected panel supply semantics IOVCC=1.8 V DCDC3 and VCI=3.3 V ALDO2.
- Rejected non-standard `nominal-microvolt` and exposed only standard battery
  property overrides.
- Adjusted default OCP8178 brightness to preserve the pre-Stage-3 startup
  hardware index.
- Excluded PCIe/Ethernet disablement, SD overclock, deferred audio switching
  and boot-command-line policy from the hardware overlay.
- Added overlay Makefile integration, CI validation and design documentation.
- Stage 4 remains open until the compiled overlay applies successfully to the
  compiled CM4 base DTB.


### 2026-11-04 — Revision 1.2 / Stage 3 complete

- Recorded successful corrected `Validate OCP8178 port` workflow.
- Confirmed the real-source OCP8178 patch dry-runs and applies with
  `--fuzz=0`.
- Confirmed the selected 22-entry brightness refinement and AK-Rex
  `onewire_ready` behavior coexist as intended.
- Confirmed `CONFIG_BACKLIGHT_OCP8178=m` resolves and `ocp8178_bl.o`
  cross-compiles successfully for ARM64.
- Marked Stage 3 complete.
- Retained narrowed CWU50/OCP8178 workflow path filters.
- Set Stage 4 cleaned uConsole CM4 device-tree overlay as the next step.


### 2026-11-04 — Revision 1.1 / Stage 3 real-source patch correction

- Corrected the project record: Stage 3 was not actually complete.
- Diagnosed the OCP8178 CI failure as a locally generated patch-context error,
  not a kernel API failure.
- Rebuilt all OCP8178 hunks around exact minimal anchors from the real pinned
  Raspberry Pi 6.18.60 and AK-Rex source files.
- Added patch dry-run validation before actual application.
- Tightened CWU50/OCP8178 workflow path filters so unrelated kernel-stage
  changes do not repeatedly run both jobs.
- Stage 3 remains validation-pending until the corrected OCP8178 workflow
  reaches and passes ARM64 compilation.


### 2026-11-04 — Revision 1.0 / Stage 3 complete

- Recorded successful `Validate OCP8178 port` GitHub Actions run.
- Proved that the pinned AK-Rex OCP8178 driver plus the selected 22-entry
  brightness refinement cross-compiles for ARM64 against the pinned Raspberry
  Pi Linux 6.18.60 baseline.
- Confirmed AK-Rex one-wire readiness behavior remains present.
- Closed the CI executable-bit regression by retaining executable script modes
  and invoking validators explicitly with `bash`.
- Marked Stage 3 complete.
- Set Stage 4 cleaned uConsole CM4 device-tree overlay as the next step.


### 2026-11-04 — Revision 0.9 / CI executable-bit regression fix

- Diagnosed repeated GitHub Actions `Permission denied` failures for
  `scripts/validate-cwu50-port.sh`.
- Root cause: an internal ZIP extract/repack step used during checkpoint
  generation dropped the shell script executable bit, causing Git to record
  `100755 -> 100644` in the Stage 2 completion checkpoint; Stage 3 inherited
  that mode regression.
- Restored executable mode on all project shell scripts.
- Changed both CWU50 and OCP8178 GitHub Actions workflows to invoke validators
  explicitly with `bash`, so CI correctness no longer depends on ZIP-preserved
  Unix mode bits.
- Added the executable-bit/checkpoint policy to `scripts/README.md`.
- Stage 3 remains pending until the OCP8178 ARM64 validation workflow passes.


### 2026-11-04 — Revision 0.8 / Stage 3 candidate

- Pinned OCP8178 behavioral source to AK-Rex commit
  `0234e320bec7748fc6f1fb6904a055de10f0a727`.
- Preserved AK-Rex one-wire readiness handling.
- Audited ClusterM's 22-entry brightness map and froze only that narrow
  semantic delta locally.
- Kept ClusterM outside the build dependency chain.
- Added OCP8178 integration patch, source lock, validator, CI workflow, and
  Stage 3 report.
- Stage 3 remains open until ARM64 CI compilation passes.


### 2026-11-04 — Revision 0.7 / Stage 2 complete

- Recorded successful replacement GitHub Actions run for the CWU50 dry-port.
- Proved that the pinned AK-Rex CWU50 driver cross-compiles for ARM64 against
  the pinned Raspberry Pi Linux 6.18.60 baseline.
- Confirmed no functional CWU50 source adaptation is required at this stage.
- Preserved physical display validation for the later hardware-testing phase.
- Set Stage 3 OCP8178 backlight dry-port as the next project step.


### 2026-11-04 — Revision 0.6 / Stage 2 validation correction

- Recorded the first Stage 2 CI failure before compilation.
- Confirmed Raspberry Pi and AK-Rex source downloads succeeded.
- Confirmed the Makefile integration hunk applied.
- Isolated failure to the Kconfig integration hunk.
- Rewrote the Kconfig hunk to use the unique following EBBG panel config as a
  minimal stable anchor.
- Made patch validation strict with `--fuzz=0` and added failure diagnostics.
- Passed a synthetic application test against the relevant pinned 6.18.60
  Kconfig/Makefile context.
- Kept Stage 2 open pending the corrected ARM64 compile-validation run.

### 2026-11-04 — Revision 0.5 / Stage 2 candidate

- Pinned AK-Rex CWU50 source commit
  `0234e320bec7748fc6f1fb6904a055de10f0a727`.
- Chose the independently hardware-verified 6.12.94 unified driver rather than
  a moving/EOL 7.x source branch.
- Added immutable source lock for the GPL-2.0+ third-party driver.
- Added a narrow 6.18 Kconfig/Kbuild integration patch.
- Added reproducible ARM64 compile-validation script and GitHub Actions job.
- Reviewed Raspberry Pi 6.18 panel APIs; no speculative driver rewrite was
  introduced before compilation.
- Investigated but deferred merging CWU50 into the generic JD9365DA-H3 driver.
- Kept all repository paths relative/neutral and added no user-identifying
  information.


### 2026-11-04 — Revision 0.4 / Stage 1

- Marked Stage 0 complete after the initial repository checkpoint was committed
  and pushed.
- Pinned Raspberry Pi Linux `rpi-6.18.y` at
  `0b41724521c9adf5399409d02aece6c1df0a4432`.
- Recorded kernel version `6.18.60`.
- Added `kernel/BASELINE.md` with selection rationale and source policy.
- Added `kernel/source.lock` as the canonical machine-readable baseline input.
- Recorded independent source provenance and CI evidence.
- Set Stage 2 CWU50 dry-port as the next project step.
- Reaffirmed privacy policy: project files use only neutral/relative paths and
  contain no user-identifying information unless explicitly approved first.


### 2026-11-04 — Revision 0.3

- Added Arch-first / ARMtix-OpenRC-later multi-distro policy.
- Required shared kernel/hardware support to remain distro-neutral.
- Split image targets into `image/archlinuxarm/` and `image/armtix-openrc/`.
- Kept handoff filename permanently fixed.

### 2026-11-04 — Initial investigation

- Recorded hardware.
- Investigated `fabiiw05/uconsole-archlinux`.
- Traced kernel-support lineage.
- Selected Raspberry Pi Linux 6.18 LTS architecture.
- Defined minimal uConsole patch strategy.
- Defined staged implementation and validation plan.

### 2026-11-21 — Stage 12D update-checker SIGPIPE correction

- First physical/local Stage 12D run produced no report despite successful upstream queries.
- Debug tracing proved the checker reached the current Raspberry Pi `rpi-6.18.y` branch head and fetched its Makefile.
- Root cause: `set -o pipefail` treated the intentional early exit from `awk` in a `printf | awk` pipeline as a failure when `printf` received SIGPIPE while writing the large kernel Makefile.
- Kernel VERSION/PATCHLEVEL/SUBLEVEL parsing now uses direct here-strings, removing the SIGPIPE path.
- Added an `ERR` trap so any future unexpected checker termination prints the failing line and exit status rather than exiting silently.
- No source pins, accepted baseline identity, build behavior, or update policy changed.


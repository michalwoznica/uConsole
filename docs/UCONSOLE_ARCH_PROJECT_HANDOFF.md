# uConsole Arch Linux Project Handoff

**Project:** Linux for ClockworkPi uConsole (Raspberry Pi CM4 Lite, original 2024 display)  
**Status date:** 2026-11-04  
**Document revision:** 1.2  
**Current phase:** Stage 3 OCP8178 dry-port complete; Stage 4 cleaned CM4 device-tree overlay is next

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

The Arch target will be completed and physically validated first.

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

### Not yet proven by this project

- CWU50 compile compatibility against the pinned 6.18.60 baseline.
- OCP8178 port against that baseline.
- cleaned DT overlay.
- minimum AXP patch.
- audio driver integration.
- full kernel build.
- physical uConsole boot.
- hardware reliability.
- final image reproducibility.

---

## 12. Current step

### Stage 0 — repository bootstrap: COMPLETE

### Stage 1 — Raspberry Pi Linux 6.18.60 baseline: COMPLETE

- commit: `0b41724521c9adf5399409d02aece6c1df0a4432`

### Stage 2 — CWU50 panel dry-port: COMPLETE

- AK-Rex source commit:
  `0234e320bec7748fc6f1fb6904a055de10f0a727`
- ARM64 object compilation: PASS
- no functional source adaptation required

### Stage 3 — OCP8178 backlight dry-port: COMPLETE

Selected behavioral source:

- AK-Rex commit:
  `0234e320bec7748fc6f1fb6904a055de10f0a727`
- source:
  `drivers/video/backlight/ocp8178_bl.c`

Selected local refinement:

- preserve AK-Rex one-wire readiness tracking;
- adopt only the audited 22-entry brightness map;
- keep ClusterM out of the build dependency chain.

The first Stage 3 patch attempt was invalid because its hunks were generated
against synthetic source neighborhoods. That failure was corrected before
Stage 3 closure.

Final validation result:

- exact Raspberry Pi source fetch: PASS;
- exact AK-Rex OCP8178 source fetch: PASS;
- patch dry-run with `--fuzz=0`: PASS;
- patch apply with `--fuzz=0`: PASS;
- 22-entry brightness-map verification: PASS;
- `onewire_ready` preservation check: PASS;
- `CONFIG_BACKLIGHT_OCP8178=m`: PASS;
- ARM64 `ocp8178_bl.o` compilation: PASS.

CI trigger cleanup is also complete:

- CWU50 workflow watches only its own inputs plus the shared kernel baseline;
- OCP8178 workflow watches only its own inputs plus the shared kernel baseline;
- documentation-only changes no longer trigger both kernel jobs.

Physical backlight behavior remains unproven until hardware testing.

### NEXT: Stage 4 — cleaned uConsole CM4 device-tree overlay

Stage 4 should:

1. pin exact AK-Rex and OuinOuin74 overlay source references;
2. compare nodes and properties semantically;
3. retain only justified CM4/uConsole hardware description;
4. exclude unrelated policy such as forced PCIe/Ethernet disablement and SD
   overclocking unless separately justified;
5. make battery capacity configurable where practical;
6. integrate CWU50 and OCP8178 nodes against the already-proven drivers;
7. compile the overlay against the pinned Raspberry Pi Linux 6.18.60 tree;
8. add CI validation and provenance;
9. defer physical boot validation to the later hardware stage.

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

# uConsole Arch Linux Project Handoff

**Project:** Linux for ClockworkPi uConsole (Raspberry Pi CM4 Lite, original 2024 display)  
**Status date:** 2026-11-04  
**Document revision:** 1.6  
**Current phase:** Stage 5 validators/patch corrected against real 6.18.60 source; ARM64 CI validation pending

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

### Stage 2 — CWU50 panel dry-port: COMPLETE

### Stage 3 — OCP8178 backlight dry-port: COMPLETE

### Stage 4 — cleaned uConsole CM4 device-tree overlay: COMPLETE

### Stage 5 — minimal AXP20x/AXP221 battery delta: CORRECTED, VALIDATION PENDING

The first Stage 5 CI run exposed two project-side validation errors:

1. the Stage 4 overlay validator still asserted the old fixed
   6,700,000-uAh / 24,790,000-uWh defaults even though the shared overlay had
   correctly changed them to zero;
2. the Stage 5 kernel patch was generated against synthetic neighborhoods and
   failed against the actual pinned Raspberry Pi Linux source.

Further exact-source audit also showed that the proposed MFD regmap change was
unnecessary. Stock AXP22x already permits writes from `0x80` through `0xe6`,
which includes the E0/E1 design-capacity registers at `0xe0/0xe1`.

Corrected Stage 5 scope:

- no `drivers/mfd/axp20x.c` change;
- only `drivers/power/supply/axp20x_battery.c` changes;
- add the documented 1456-uAh/LSB design-capacity encoder;
- program E0/E1 only when `charge-full-design-microamp-hours` is positive;
- keep zero as the replaceable-pack default;
- retain all previous exclusions for calibration, synthetic energy reporting,
  writable charge-full and unrelated PMIC policy.

Corrected validation:

- Stage 4 overlay validator now expects zero design-capacity/energy defaults;
- Stage 5 patch is constructed from exact pinned 6.18.60 source
  neighborhoods;
- Stage 5 CI dry-runs/applies with `--fuzz=0`;
- only `drivers/power/supply/axp20x_battery.o` is compiled because it is now
  the only changed kernel object.

### NEXT

Push the correction and rerun:

- `Validate uConsole CM4 overlay`
- `Validate AXP20x battery delta`

Stage 5 closes only when both pass.

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

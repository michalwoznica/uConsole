# uConsole Arch Linux Project Handoff

**Project:** Linux for ClockworkPi uConsole (Raspberry Pi CM4 Lite, original 2024 display)  
**Status date:** 2026-11-04  
**Document revision:** 0.7  
**Current phase:** Stage 2 CWU50 dry-port complete; Stage 3 OCP8178 backlight is next

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

The initial repository checkpoint was committed and pushed.

### Stage 1 — pin exact Raspberry Pi 6.18 baseline: COMPLETE

Canonical kernel source:

- Repository: `https://github.com/raspberrypi/linux.git`
- Branch family: `rpi-6.18.y`
- Exact commit: `0b41724521c9adf5399409d02aece6c1df0a4432`
- Kernel version: `6.18.60`

### Stage 2 — CWU50 panel dry-port: COMPLETE

Selected immutable CWU50 source:

- Repository: `https://github.com/ak-rex/rpi-linux.git`
- Exact commit: `0234e320bec7748fc6f1fb6904a055de10f0a727`
- Source path: `drivers/gpu/drm/panel/panel-cwu50.c`
- Recorded source release: `6.12.94-v8+`

Implementation result:

- no functional driver modifications were required;
- a small local patch integrates the driver with 6.18.60 Kconfig/Kbuild;
- the first CI attempt exposed a local Kconfig patch-context bug before
  compilation;
- that integration patch was corrected and validation tightened to
  `--fuzz=0`;
- the replacement GitHub Actions run completed successfully;
- `CONFIG_DRM_PANEL_CWU50=m` resolved correctly;
- `drivers/gpu/drm/panel/panel-cwu50.o` cross-compiled successfully for ARM64.

What is now proven:

- the selected modern/hardware-verified CWU50 implementation is source/API
  compatible with the project's exact Raspberry Pi Linux 6.18.60 baseline;
- the project's integration patch and validation workflow work with the pinned
  inputs.

What is not yet proven:

- physical panel initialization on the user's uConsole;
- runtime DSI reliability;
- backlight behavior;
- interaction with the later device-tree overlay.

Those remain for later hardware validation.

### NEXT: Stage 3 — OCP8178 backlight dry-port

Stage 3 should:

1. pin the exact AK-Rex OCP8178 source used as the behavioral base;
2. pin and review the exact ClusterM source containing the finer brightness
   mapping;
3. compare both implementations semantically;
4. decide whether to carry AK-Rex unchanged first or integrate the narrow
   ClusterM brightness-map improvement immediately;
5. create a narrowly scoped 6.18.60 integration patch;
6. validate patch application and ARM64 compilation;
7. update provenance and this handoff before marking Stage 3 complete.

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

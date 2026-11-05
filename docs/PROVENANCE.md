# Source provenance

This document records where each uConsole-specific component comes from and why it is carried.

Exact source commit hashes will be added as each component is ported. No implementation should be copied into the project without recording its origin here and in the corresponding patch metadata.

## Upstream kernel base

Planned canonical source:

- Repository: https://github.com/raspberrypi/linux
- Branch family: `rpi-6.18.y`
- Exact commit: `0b41724521c9adf5399409d02aece6c1df0a4432`
- Kernel version: `6.18.60`
- Selection stage: Stage 1 — complete
- Detailed rationale: `kernel/BASELINE.md`

## CWU50 panel driver

Preferred lineage:

ClockworkPi → AK-Rex modern unified CWU50 implementation.

Reasons:

- supports original and later uConsole panels;
- retains the initialization path required by the original/2024 display;
- includes useful DSI-state diagnostics;
- avoids depending on an entire community kernel fork.

Exact source selected for Stage 2:

- Repository: `https://github.com/ak-rex/rpi-linux.git`
- Commit: `0234e320bec7748fc6f1fb6904a055de10f0a727`
- Recorded source release: `6.12.94-v8+`
- Path: `drivers/gpu/drm/panel/panel-cwu50.c`
- Lock file: `kernel/sources/cwu50.lock`

The source file is fetched from that immutable commit rather than vendored.
Stage 2 preserved its behavior unchanged while testing API compatibility
with Raspberry Pi Linux 6.18.60.

Validation result: **PASS**. The exact pinned driver cross-compiles for ARM64
against the exact pinned 6.18.60 Raspberry Pi kernel baseline without
functional source adaptation.

## OCP8178 backlight

Selected behavioral source:

- repository: `https://github.com/ak-rex/rpi-linux.git`
- exact commit: `0234e320bec7748fc6f1fb6904a055de10f0a727`
- recorded release: `6.12.94-v8+`
- path: `drivers/video/backlight/ocp8178_bl.c`

AK-Rex is retained as the behavioral base because its implementation tracks
one-wire readiness and avoids repeating the reset/detect sequence on ordinary
brightness changes.

Selected local refinement:

- ClusterM repository: `https://github.com/ClusterM/ClockworkPi-linux.git`
- audited branch: `clockworkpi-7.2.y-live`
- audited date: 2026-11-04
- adopted delta: 22-entry brightness range/map only

ClusterM is intentionally not a build dependency. The selected semantic delta
is frozen in `0002-video-backlight-integrate-ocp8178.patch`, so later movement
of that branch cannot change our build.

Build-time metadata is recorded in `kernel/sources/ocp8178.lock`.

Stage 3 compile validation: **PASS** after rebuilding the local patch around exact anchors from the pinned real sources. The corrected workflow dry-runs and applies the patch with `--fuzz=0`, verifies the selected behavior, and cross-compiles `ocp8178_bl.o` for ARM64 against the pinned Raspberry Pi Linux 6.18.60 baseline.

## uConsole CM4 device tree

Project build input:

- `kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts`
- file SPDX: `GPL-2.0-only`

Primary structural provenance:

- AK-Rex repository: `https://github.com/ak-rex/rpi-linux.git`
- exact commit: `0234e320bec7748fc6f1fb6904a055de10f0a727`
- source path:
  `arch/arm/boot/dts/overlays/clockworkpi-uconsole-cm4-overlay.dts`

Additional immutable reference:

- postmarketOS/pmaports commit:
  `5cf4d21c7e55945a8256c3edceac9341660f1b29`
- selected evidence: DCDC3 1.8 V as panel IOVCC and ALDO2 3.3 V as
  panel VCI.

OuinOuin74 `main` was audited on 2026-11-04 as a design reference only and is
not a build dependency.

Selected cleanup policy:

- modern GPIO flags and `reset-gpios`;
- standard `simple-battery` properties with configurable `batt_uah`,
  `batt_uwh` and `vmin_uv` overrides;
- startup brightness adjusted for the Stage 3 22-level map;
- exclude PCIe/Ethernet disablement, SD overclock, deferred audio switching,
  `/chosen/bootargs` mutation and non-standard battery/PMIC properties.

Detailed rationale: `docs/STAGE4_CM4_OVERLAY.md`.

Stage 4 CI validation: **PASS**. The project-owned overlay builds as a DTBO against the pinned Raspberry Pi Linux 6.18.60 tree and successfully applies to the compiled CM4 base DTB with `fdtoverlay`.

## AXP20x battery/fuel gauge

Planned approach:

- retain Raspberry Pi 6.18's stock AXP20x subsystem;
- add only small, justified changes required for correct uConsole battery reporting;
- do not import a wholesale alternate AXP driver stack.

Candidate ideas are derived from AK-Rex, ClusterM, PotatoMania, and postmarketOS work.

Exact source commits: **to be selected during Stage 5**.

## Headphone/speaker amplifier switching

Preferred lineage:

PotatoMania's simple amplifier-switch design, with OuinOuin74's overlay used as a wiring reference.

Exact source commit: **to be selected during Stage 6**.

## Reference projects

- https://github.com/clockworkpi/uConsole
- https://github.com/ak-rex/rpi-linux
- https://github.com/OuinOuin74/linux-clockwork-arch
- https://github.com/KondratokGK/linux-clockwork-arch
- https://github.com/ClusterM/ClockworkPi-linux
- https://github.com/PotatoMania/uconsole-cm3
- https://github.com/fabiiw05/uconsole-archlinux
- https://github.com/raspberrypi/linux
- https://pkgs.postmarketos.org/

## AXP20x / AXP221 battery and fuel gauge

Stage 5 starts from the pinned Raspberry Pi Linux 6.18.60 driver and keeps its
normal battery behavior.

Comparison evidence:

- AK-Rex exact commit
  `0234e320bec7748fc6f1fb6904a055de10f0a727`;
- ClusterM `clockworkpi-7.2.y-live`, audited 2026-11-04;
- original ClockworkPi CM4 patch lineage;
- AXP228 datasheet E0/E1 definitions;
- upstream AXP288 fuel-gauge use of the same register family and 1456 uAh
  resolution.

Selected delta: program positive standard DT design capacity into the AXP221
fuel gauge. Calibration and unrelated PMIC policy writes remain excluded.

Detailed rationale: `docs/STAGE5_AXP20X_BATTERY.md`.

Stage 5 CI validation: **PASS**. The exact-block AXP221 design-capacity patch applies with `--fuzz=0` to the pinned Raspberry Pi Linux 6.18.60 source and `axp20x_battery.o` cross-compiles successfully for ARM64.

## uConsole audio / headphone speaker switch

Hardware evidence:

- ClockworkPi GPIO documentation identifies GPIO10 as `HP_DET`, high when a
  3.5 mm plug is inserted;
- GPIO11 is `PA_EN`, high to enable the speaker amplifier;
- GPIO12/13 are the PWM audio outputs.

Behavioral lineage:

- PotatoMania `uconsole-cm3` simple amplifier switch;
- immutable postmarketOS archival commit
  `587b03ad734fdf86c378a1d0de8e307ddcdd301d`.

The project does not copy the original hard-IRQ implementation. It uses a
small GPL-2.0-only project-owned driver with a threaded IRQ and semantic GPIO
properties.

Stock Raspberry Pi Linux 6.18 `audremap,pins_12_13` remains the audio-signal
routing mechanism. Boot/image configuration is deferred to later stages.

Detailed rationale: `docs/STAGE6_AUDIO_SWITCH.md`.

Stage 6 CI validation: **PASS**. The uConsole threaded-IRQ amplifier switch integrates into the pinned Raspberry Pi Linux 6.18.60 tree, resolves as `CONFIG_UCONSOLE_AMP_SWITCH=m`, and `uconsole-amp-switch.o` cross-compiles successfully for ARM64. The shared CM4 overlay workflow also remains green.

## Stage 7 Arch Linux ARM packaging reference

The project reviewed the current Arch Linux ARM `linux-rpi` PKGBUILD for
package layout and install conventions: Raspberry Pi source archive,
`bcm2711_defconfig`, `Image`/modules/DTB build targets, `kernel8.img`,
`dtbs_install`, module installation and mkinitcpio integration.

This is a packaging-style reference only. The project's pinned Raspberry Pi
Linux commit in `kernel/source.lock` remains authoritative even when the
Arch Linux ARM package tracks a different commit carrying the same upstream
stable version.

The project also retains ClockworkPi/community boot evidence for CM4 KMS,
uConsole overlay selection, CM4 USB host mode and PWM audio on GPIO12/13.

Detailed rationale: `docs/STAGE7_KERNEL_ARCH_PACKAGE.md`.

Stage 7 CI validation: **PASS**. The actual staged PKGBUILD `prepare()` path composes all five project patches against the pinned Raspberry Pi Linux 6.18.60 source, resolves the uConsole config, produces kernel release `6.18.60-1-uconsole`, and passes `make prepare`.

## Stage 8 full-build validation

Stage 8 introduces no new kernel source lineage. It exercises the exact
sources, project files, patches, configuration and Arch package metadata
already established in Stages 1-7.

The full-build validator additionally verifies representative AXP20x module
output names against the pinned Raspberry Pi Linux Makefiles and uses
`fdtoverlay` for final CM4 DTB/uConsole DTBO composition.

Detailed contract: `docs/STAGE8_FULL_BUILD.md`.

Stage 8 CI validation: **PASS**. The complete staged PKGBUILD `prepare()`, `build()` and `package()` path succeeded, including Image, modules, DTBs/DTBOs, overlay application and package-root verification.

## Stage 9A Arch Linux ARM rootfs

Selected rootfs:

- family: Raspberry Pi AArch64;
- release: `2026.08`;
- file: `ArchLinuxARM-2026.08-rpi-aarch64-rootfs.tar.gz`;
- mirrored size: `850215189` bytes;
- release timestamp: `2026-08-05T12:55:04Z`;
- signing fingerprint:
  `68B3537F39A313B3E574D06777193F152BDBE6A6`.

Arch Linux ARM's downloads page states that releases are signed with its
package-signing build-system key. The versioned mirror directory retains the
2026.08 Raspberry Pi AArch64 archive alongside MD5 and detached-signature
sidecars.

The moving `-latest` alias is not accepted as a project build input.

Detailed contract: `docs/STAGE9A_ARCH_ROOTFS_PIN.md`.

Stage 9A CI validation: **PASS**. The pinned 2026.08 Raspberry Pi AArch64 rootfs was authenticated and its package/boot inventory was audited directly from the archive.

### Stage 9A signature-parser correction

The first CI attempt exposed a brittle local parser for GnuPG colon output.
The official Arch Linux ARM signing fingerprint remains unchanged.

The validator now requires the detached signature's `VALIDSIG` status to name
the exact official fingerprint, in addition to confirming that fingerprint is
present in the extracted Arch Linux ARM keyring.

### Direct gpgv trust path

After CI showed that direct `gpg --keyring ... --list-keys` inspection of the
pacman keyring was not portable in the hosted runner environment, Stage 9A
removed that redundant pre-check.

Detached-signature verification is now authoritative: `gpgv` must succeed and
its `VALIDSIG` record must identify the official Arch Linux ARM build-system
fingerprint as either signer or primary key.

### Stage 9A keyring-format correction

The third Stage 9A CI run proved that the detached signature names the exact
expected Arch Linux ARM signing key, but `gpgv` could not parse the extracted
pacman keyring directly and reported `invalid packet (ctb=2d)`.

The validator now normalizes an ASCII-armored `archlinuxarm.gpg` with
`gpg --dearmor` before passing it to `gpgv`. Binary keyring input is left
unchanged. The `VALIDSIG` fingerprint requirement remains authoritative.

### Stage 9A archive-native audit

The fourth Stage 9A run cryptographically authenticated the pinned rootfs with
the official Arch Linux ARM signing key. Full extraction then failed only
because the unprivileged CI environment could not restore Linux capability
xattrs.

Stage 9A now performs its structural and package-database audit directly from
the authenticated tar archive. No filesystem metadata is restored during this
read-only provenance checkpoint.

## Stage 9B rootfs integration

Stage 9B uses the exact authenticated Stage 9A rootfs and the existing
`linux-uconsole` source/package definition.

The authenticated rootfs SHA-256 is now locked as:

`f10903be472e2662e110f0f7bae2750a30914ce3dc0fcd38ec85d3405d8c8967`

Observed replacement set:

- `linux-aarch64`;
- `uboot-raspberrypi`.

Retained boot/runtime packages include `firmware-raspberrypi`,
`raspberrypi-bootloader`, `mkinitcpio` and the linux-firmware set.

Stage 9B CI validation is **pending**. The first run reached the real `makepkg` invocation but the unprivileged build user could not traverse the root-owned `mktemp` parent directory. The workspace traversal permission has been corrected; no rootfs/package policy changed.

### Stage 9B cross-architecture pacman correction

The real aarch64 package build succeeded. The remaining CI failure was in
host-side validation: libalpm attempted target-AArch64 `ldconfig`, and a
`--sysroot -Qo` query used a literal host path. Stage 9B now suppresses only
the unnecessary ldconfig execution during the kernel-only transactions and
uses package/database file records for ownership checks.

### Stage 9B local-database ownership correction

The package build and target transaction now complete successfully through
`pacman -Dk` and `pacman -Qk linux-uconsole` (2765 files, 0 missing).

The remaining ownership assertion was changed from formatted `pacman -Ql`
output to the target pacman local database `files` record. Package file names
are install-root-relative there, so `boot/kernel8.img` is checked directly and
`boot/config.txt` remains required to be absent from every package file list.

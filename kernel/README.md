# Kernel package

This directory contains the distro-neutral uConsole kernel work.

The project does not vendor a complete Linux source tree. Build tooling fetches
the exact Raspberry Pi Linux revision pinned in `source.lock`, materializes
explicitly pinned third-party hardware-support sources, and applies the local
integration patch series.

## Current baseline

- Raspberry Pi Linux branch family: `rpi-6.18.y`
- Kernel version: `6.18.60`
- Commit: `0b41724521c9adf5399409d02aece6c1df0a4432`

See `BASELINE.md` for the selection rationale and provenance.

## CWU50 source input

The panel implementation is pinned separately in `sources/cwu50.lock`:

- AK-Rex commit: `0234e320bec7748fc6f1fb6904a055de10f0a727`
- source kernel release: `6.12.94-v8+`
- source path: `drivers/gpu/drm/panel/panel-cwu50.c`

That exact implementation was independently recorded as hardware-verified on
a uConsole and supports both the original and newer panel revisions.

The first local patch only integrates the source into the 6.18 Kconfig/Kbuild
structure. No functional modifications to the driver are made during the
initial dry-port.

## Validation

`scripts/validate-cwu50-port.sh` downloads both immutable source inputs,
materializes the driver, applies the integration patch, selects
`CONFIG_DRM_PANEL_CWU50=m`, and cross-compiles the panel object for ARM64.

The same validation runs in GitHub Actions.

Stage 2 result: **PASS**. The GitHub Actions workflow successfully
cross-compiled `panel-cwu50.o` for ARM64 against the exact pinned Raspberry Pi
Linux 6.18.60 baseline. No functional driver adaptation was required.

## Planned later patch order

2. OCP8178 backlight
3. uConsole CM4 device-tree overlay
4. minimal AXP20x battery changes, if required
5. headphone/speaker amplifier switching

## OCP8178 source port

Stage 3 materializes the exact AK-Rex OCP8178 driver pinned in
`kernel/sources/ocp8178.lock`, then applies
`0002-video-backlight-integrate-ocp8178.patch`.

The local patch preserves AK-Rex's one-wire state handling and incorporates
only the selected 22-entry brightness map. Validation is performed by
`scripts/validate-ocp8178-port.sh`.

Stage 3 result: **PASS**. The corrected OCP8178 patch now dry-runs and
applies exactly against the pinned real source files, and `ocp8178_bl.o`
cross-compiles successfully for ARM64 against Raspberry Pi Linux 6.18.60.

## uConsole CM4 device-tree overlay

Stage 4 introduces the project-owned cleaned overlay at
`kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts`.

The overlay is copied into the pinned Raspberry Pi kernel tree and registered
by `0003-arm-dts-build-uconsole-cm4-overlay.patch`.

Validation is performed by `scripts/validate-uconsole-cm4-overlay.sh`.

Stage 4 result: **PASS**. The cleaned uConsole CM4 overlay compiles against
the pinned Raspberry Pi Linux 6.18.60 tree and successfully applies to the
compiled CM4 base DTB with `fdtoverlay`.

## Minimal AXP221 fuel-gauge delta

Stage 5 adds only documented design-capacity programming for the uConsole's
AXP221 PMIC.

Patch: `kernel/patches/0004-power-axp20x-program-design-capacity.patch`

Validation: `scripts/validate-axp20x-battery.sh`

Stage 5 correction: no MFD change is required. The stock AXP22x writable
regmap range already includes E0/E1, so the final Stage 5 delta changes only
`drivers/power/supply/axp20x_battery.c`.

Stage 5 result: **PASS**. The exact-block AXP221 design-capacity patch applies
cleanly to the pinned Raspberry Pi Linux 6.18.60 source and
`axp20x_battery.o` cross-compiles successfully for ARM64.

## uConsole audio amplifier switch

Stage 6 adds the project-owned threaded-IRQ headphone/speaker switch driver:

`kernel/drivers/uconsole-amp-switch.c`

Integration patch:

`kernel/patches/0005-misc-integrate-uconsole-amplifier-switch.patch`

The stock Raspberry Pi `audremap,pins_12_13` overlay remains responsible for
PWM audio signal routing.

Stage 6 result: **PASS**. The uConsole threaded-IRQ audio switch integrates
cleanly with the pinned Raspberry Pi Linux 6.18.60 tree, resolves as a module,
and `uconsole-amp-switch.o` cross-compiles successfully for ARM64.

## Stage 7 configuration and packaging

The complete uConsole kernel is now configured as:

`bcm2711_defconfig` + `kernel/config/uconsole-cm4.config`

Shared kernel package metadata lives under:

`image/shared/packages/linux-uconsole/`

Stage 7 validates composition/configuration only. Stage 8 performs the first
complete build of Image, modules and DTBs from this package path.

Stage 7 result: **PASS**. The complete project source composition and
configuration path succeeds through the staged PKGBUILD `prepare()`
function. The resolved kernel release is `6.18.60-1-uconsole`, and
`make prepare` succeeds.

## Stage 8 full-build validation

Stage 8 is the first end-to-end build of the complete Stage 7 composition.
It reuses the actual `linux-uconsole` PKGBUILD and validates `Image`, modules,
DTBs/DTBOs and the package-root install layout.

Stage 8 result: **PASS**. The complete `linux-uconsole` composition builds
`Image`, modules and DTBs successfully, the uConsole overlay applies to the
built CM4 DTB, and the package-root install path validates successfully.

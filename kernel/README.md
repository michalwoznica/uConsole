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

## Planned later patch order

2. OCP8178 backlight
3. uConsole CM4 device-tree overlay
4. minimal AXP20x battery changes, if required
5. headphone/speaker amplifier switching

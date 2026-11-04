# Kernel package

This directory contains the distro-neutral uConsole kernel work.

The project does not vendor a complete Linux source tree. Build tooling will
fetch the exact Raspberry Pi Linux source revision pinned in `source.lock` and
apply the patch series in `patches/`.

## Current baseline

- Raspberry Pi Linux branch family: `rpi-6.18.y`
- Kernel version: `6.18.60`
- Commit: `0b41724521c9adf5399409d02aece6c1df0a4432`

See `BASELINE.md` for the selection rationale and provenance.

## Planned patch order

1. CWU50 panel
2. OCP8178 backlight
3. uConsole CM4 device-tree overlay
4. minimal AXP20x battery changes, if required
5. headphone/speaker amplifier switching

No uConsole-specific kernel patch has been added yet.

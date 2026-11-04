# Kernel package

This directory will contain the reproducible, distro-neutral uConsole kernel package.

The project will not vendor a complete Linux source tree. The future build recipe will fetch an exact pinned Raspberry Pi Linux 6.18 source revision and apply the patch series in `patches/`.

Planned order:

1. CWU50 panel
2. OCP8178 backlight
3. uConsole CM4 device-tree overlay
4. minimal AXP20x battery changes, if required
5. headphone/speaker amplifier switching

Stage 1 will pin the exact Raspberry Pi Linux 6.18 baseline before any patch is added.

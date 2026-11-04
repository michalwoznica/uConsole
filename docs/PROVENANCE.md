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

Preferred design:

- AK-Rex behavior as the base, particularly one-wire state handling;
- evaluate ClusterM's finer 22-level brightness map as a narrowly auditable improvement.

Exact source commits: **to be selected during Stage 3**.

## uConsole CM4 device tree

Planned approach:

- conservative structural base from AK-Rex;
- selected useful modern properties from OuinOuin74;
- no blind inheritance of unrelated policy such as forced PCIe/Ethernet disablement or SD overclocking.

Exact source commits: **to be selected during Stage 4**.

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

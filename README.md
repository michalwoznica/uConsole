# uConsole Arch Linux CM4

Reproducible Linux build project for the ClockworkPi uConsole with a Raspberry Pi Compute Module 4 Lite.

## Target hardware

- ClockworkPi uConsole
- Raspberry Pi CM4 Lite (`104000`, no eMMC)
- Original/2024 uConsole display revision
- microSD boot/storage

## Project direction

The shared kernel/hardware layer is distro-neutral.

The first userspace target is **Arch Linux ARM**. A later **ARMtix / Artix OpenRC** target is planned.

The kernel will be based on the official Raspberry Pi `rpi-6.18.y` branch plus a small, auditable uConsole-specific patch series.

Expected custom delta:

1. CWU50 display panel
2. OCP8178 backlight
3. uConsole CM4 device-tree overlay
4. minimal AXP20x battery/fuel-gauge changes, if required
5. headphone/speaker amplifier switching

Historical VC4/DSI workarounds will not be carried unless physical testing proves they are still required.

## Repository layout

```text
.
├── README.md
├── LICENSE
├── .github/
│   └── workflows/
│       └── validate-cwu50.yml
├── docs/
│   ├── PROVENANCE.md
│   ├── STAGE2_CWU50_PORT.md
│   └── UCONSOLE_ARCH_PROJECT_HANDOFF.md
├── kernel/
│   ├── README.md
│   ├── BASELINE.md
│   ├── source.lock
│   ├── sources/
│   │   ├── README.md
│   │   └── cwu50.lock
│   ├── config/
│   │   └── README.md
│   └── patches/
│       ├── README.md
│       └── 0001-drm-panel-integrate-cwu50.patch
├── image/
│   ├── README.md
│   ├── archlinuxarm/
│   │   └── README.md
│   └── armtix-openrc/
│       └── README.md
└── scripts/
    └── README.md
```

## Reproducibility policy

The repository is a build recipe, not a permanently forked Linux source tree.

Each completed stage should:

- have a narrow goal;
- be independently reviewable;
- be validated before moving on;
- be committed to Git;
- update `docs/UCONSOLE_ARCH_PROJECT_HANDOFF.md`;
- record what is proven and what remains unverified.

## Multi-distro design

Arch Linux ARM is the first implementation target.

A later ARMtix/OpenRC target is explicitly planned, so the project keeps:

- kernel and hardware support distro-neutral;
- shared build logic outside distro-specific image directories;
- init-system-specific service integration inside each image target.

## Current status

Stage 1: Raspberry Pi Linux baseline pinned.

Current kernel baseline:

- Linux `6.18.60`
- Raspberry Pi `rpi-6.18.y`
- commit `0b41724521c9adf5399409d02aece6c1df0a4432`

Stage 2 CWU50 dry-port candidate is prepared. The panel source is pinned to
AK-Rex commit `0234e320bec7748fc6f1fb6904a055de10f0a727`, integrated by a small
Kconfig/Kbuild patch, and checked by `scripts/validate-cwu50-port.sh` plus
GitHub Actions.

The first CI run exposed a Kconfig patch-context mismatch before compilation.
The patch has been tightened to use a stable exact anchor and the validator now
uses `--fuzz=0`. Stage 2 becomes complete only after the replacement CI run
passes the ARM64 object compile. Next after validation: Stage 3 — OCP8178
backlight.

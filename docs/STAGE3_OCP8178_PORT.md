# Stage 3 — OCP8178 backlight dry-port

**Status:** implemented; ARM64 CI validation pending.

## Goal

Add OCP8178 one-wire backlight support to the pinned Raspberry Pi Linux
6.18.60 baseline while keeping the local delta small and preserving the
best-understood runtime behavior.

## Behavioral base

Build input:

- repository: `https://github.com/ak-rex/rpi-linux.git`
- commit: `0234e320bec7748fc6f1fb6904a055de10f0a727`
- recorded release: `6.12.94-v8+`
- path: `drivers/video/backlight/ocp8178_bl.c`

AK-Rex is retained as the behavioral base because it tracks whether the
OCP8178 is already in one-wire mode. Ordinary brightness changes therefore do
not unnecessarily repeat the reset/detect sequence that can visibly blank or
flash the backlight.

## Brightness refinement

ClusterM's `clockworkpi-7.2.y-live` driver was audited on 2026-11-04 as a
design reference. It raises the exposed brightness range from 0..9 to 0..21
and maps those levels to:

`0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,16,18,20,22,25,28,31`

Only that narrow refinement is adopted.

ClusterM is not a build dependency. Its branch is moving, so the selected
semantic delta is frozen directly in our local GPL kernel patch. The build
therefore remains deterministic even if ClusterM changes later.

## Local patch

`kernel/patches/0002-video-backlight-integrate-ocp8178.patch`

It:

1. adds `CONFIG_BACKLIGHT_OCP8178`;
2. adds the Kbuild object entry;
3. changes only the maximum brightness constant and lookup table in the
   materialized AK-Rex driver.

It does **not** alter timing constants, GPIO behavior, reset/detect sequencing,
one-wire state tracking, probe logic, suspend/resume behavior, or device
matching.

## Validation

`validate-ocp8178-port.sh`:

1. fetches exact Raspberry Pi Linux 6.18.60;
2. fetches exact AK-Rex OCP8178 source;
3. applies the local patch with `--fuzz=0`;
4. verifies the 22-entry map;
5. verifies `onewire_ready` behavior remains present;
6. enables `CONFIG_BACKLIGHT_OCP8178=m`;
7. cross-compiles `ocp8178_bl.o` for ARM64.

Physical brightness quality, absence of flashing on hardware, and
suspend/resume behavior remain for the physical-validation stage.

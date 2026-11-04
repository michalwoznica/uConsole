# Patch series

The patch series is applied to the exact Raspberry Pi Linux baseline recorded
in `../source.lock`.

## Current series

1. `0001-drm-panel-integrate-cwu50.patch`
   - registers the ClockworkPi CWU50 panel driver in DRM Kconfig/Kbuild;
   - the third-party GPL-2.0+ driver source is fetched from the immutable
     AK-Rex commit recorded in `../sources/cwu50.lock` before the patch is
     applied.

This separation is intentional: the repository remains a reproducible build
recipe and provenance record rather than vendoring copies of third-party
kernel source files.

Every patch must remain narrowly scoped, independently reviewable, and tested
against the pinned kernel baseline.

## Current series

1. `0001-drm-panel-integrate-cwu50.patch` — CWU50 panel integration.
2. `0002-video-backlight-integrate-ocp8178.patch` — OCP8178 integration plus
   the selected 22-entry brightness map.

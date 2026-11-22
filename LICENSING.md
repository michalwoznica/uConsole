# Licensing

This repository contains material under more than one license.

## Default project license

The root `LICENSE` (MIT) is the default license for project-authored scripts,
documentation, build metadata and other files that do not carry a more specific
license notice.

A file-specific SPDX identifier or explicit license statement takes precedence
over that default. The MIT license does not relicense Linux-derived or
third-party material.

## Kernel-facing project files

The following project-owned kernel-facing files are explicitly
`GPL-2.0-only`:

- `kernel/drivers/uconsole-amp-switch.c`;
- `kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts`;
- `kernel/patches/0001-drm-panel-integrate-cwu50.patch`;
- `kernel/patches/0002-video-backlight-integrate-ocp8178.patch`;
- `kernel/patches/0003-arm-dts-build-uconsole-cm4-overlay.patch`;
- `kernel/patches/0004-power-axp20x-program-design-capacity.patch`;
- `kernel/patches/0005-misc-integrate-uconsole-amplifier-switch.patch`.

The Arch `linux-uconsole` package declares `GPL-2.0-only` because it builds the
Linux kernel and the project kernel delta.

## Third-party sources and built image

Third-party kernel sources are not vendored by this repository. They are fetched
from immutable upstream revisions recorded under `kernel/sources/` and retain
their upstream licenses. For example, the CWU50 source is recorded as GPL-2.0+
/ GPL-2.0-or-later provenance.

The generated Arch Linux ARM image is an aggregate of many independently
licensed packages. Each package retains its own license; the repository's MIT
license does not apply to the image as a whole.

See `docs/PROVENANCE.md`, `kernel/sources/`, the relevant file SPDX headers and
package metadata for component-level provenance.

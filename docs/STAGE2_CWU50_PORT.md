# Stage 2 — CWU50 panel dry-port

## Decision

Use the hardware-verified AK-Rex unified CWU50 driver from commit
`0234e320bec7748fc6f1fb6904a055de10f0a727` as the immutable source input and
integrate it with the project's Raspberry Pi Linux 6.18.60 baseline.

The driver source is not vendored in this repository. It is fetched from the
exact commit recorded in `kernel/sources/cwu50.lock` during validation/build.

## Why this source revision

The chosen source revision is preferable to following AK-Rex's moving 7.x
branches because it has a concrete hardware-verification record and already
contains the unified old/new-panel implementation needed for the uConsole.
The user's 2024 display uses the original-panel path, while retaining the
new-panel path keeps the kernel useful with replacement displays.

## 6.18 API review

The relevant 6.12 driver interfaces remain present in Raspberry Pi Linux
6.18.60, including:

- `struct drm_panel_funcs` prepare/enable/disable/unprepare/get_modes hooks;
- `struct drm_panel.prepare_prev_first`;
- `drm_panel_init`, `drm_panel_add`, and `drm_panel_remove`;
- MIPI DSI attach/detach and DCS helpers used by the driver;
- `devm_of_find_backlight`;
- `of_drm_get_panel_orientation`;
- `drm_connector_set_panel_orientation`;
- regulator and GPIO consumer APIs used by the driver.

Therefore Stage 2 deliberately makes no functional driver changes before
compile validation. This keeps any later adaptation attributable to an actual
compiler or hardware failure rather than speculative modernization.

## Generic JD9365DA-H3 driver considered

Raspberry Pi Linux 6.18 already contains the generic
`panel-jadard-jd9365da-h3` driver. The uConsole CWU50 uses the same controller
family, so reusing that driver was investigated.

It is not selected for the first port because CWU50 has additional
uConsole-specific behavior:

- runtime old/new panel-revision detection;
- reuse of the panel ID/reset GPIO with revision-dependent direction;
- uConsole regulator sequencing and probe deferral;
- two known uConsole initialization sequences.

Folding those behaviors into the generic Jadard driver would be a larger
semantic change than preserving the known-working standalone driver. It can be
revisited after physical validation if upstream consolidation becomes useful.

## Validation contract

Stage 2 is complete only when the validation workflow succeeds against the
exact pinned sources. The workflow must demonstrate that:

1. Raspberry Pi Linux 6.18.60 is fetched by exact commit;
2. the AK-Rex CWU50 source is fetched by exact commit and path;
3. the integration patch applies cleanly;
4. `CONFIG_DRM_PANEL_CWU50=m` resolves in Kconfig;
5. `drivers/gpu/drm/panel/panel-cwu50.o` cross-compiles for ARM64.

Physical display behavior is intentionally not part of Stage 2; it remains a
later hardware-validation milestone.

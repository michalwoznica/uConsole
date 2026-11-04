# Stage 5 — minimal AXP20x battery/fuel-gauge delta

**Status:** implemented; ARM64 CI validation pending.

## Audit conclusion

Stock Raspberry Pi Linux 6.18.60 already provides the uConsole's core AXP221
battery behavior: charging, voltage/current reporting, charger configuration
and PMIC percentage reporting.

The historical ClockworkPi and later community drivers add substantially more
behavior than is justified for the first release.

## Selected delta

The one retained functional gap is programming the AXP221/AXP228 fuel-gauge
design-capacity registers from the standard
`charge-full-design-microamp-hours` device-tree property.

The AXP228 datasheet defines E0/E1 as a 15-bit battery full design capacity
with 1.456 mAh (1456 uAh) per LSB.

Stage 5 therefore adds only:

1. a helper in `axp20x_battery.c` to encode the documented 15-bit capacity;
2. AXP221 probe logic that programs a positive DT capacity into E0/E1.

No MFD/regmap modification is required: the stock AXP22x writable range is
already `0x80..0xe6`, which includes E0/E1 (`0xe0/0xe1`).

## Replaceable cells

The uConsole's 18650 cells are easily replaceable. The project overlay now
defaults design capacity and energy to zero rather than assuming 2x3350 mAh.

`batt_uah`, `batt_uwh` and `vmin_uv` overrides remain available.

A zero `batt_uah` does not program the PMIC. A positive `batt_uah` is
programmed into E0/E1.

## Explicitly excluded

- calibration sysfs;
- writable `CHARGE_FULL`;
- added `CHARGE_NOW` or energy properties;
- synthetic percentage-to-energy calculations;
- historical percentage remapping;
- VBUS-current-limit writes;
- LED policy;
- power-key timing mutation;
- GPIO0 mutation;
- wholesale community battery-driver replacement.

## Validation

CI dry-runs/applies the patch with `--fuzz=0` against the exact 6.18.60
source and cross-compiles the only changed object:

- `drivers/power/supply/axp20x_battery.o`

Physical fuel-gauge behavior remains for hardware validation.

## Probe-hunk correction

The second Stage 5 CI run proved that the helper insertion hunk was correct,
but the probe insertion hunk still carried line-location metadata derived
from a shortened surrogate file.

The final candidate regenerates the patch with the actual pinned 6.18.60
source positions:

- AXP22x helper neighborhood: around line 166;
- battery-info probe neighborhood: around line 1057.

The Stage 5 code and scope are unchanged; only patch placement metadata and
failure diagnostics were corrected.

## Single-hunk correction

The final Stage 5 candidate colocates the design-capacity helper immediately
above `axp20x_power_probe()` and represents the helper plus probe call as one
contiguous patch hunk. This removes all cross-hunk offset dependence while
leaving functional scope unchanged.

## Exact-block correction

The prior single-hunk candidate still included hand-reconstructed surrounding
probe context. CI printed the exact four-line battery-info block from the
pinned source.

The final candidate patches only that exact block. The design-capacity
conversion and E0/E1 write are inline, so no helper function or distant source
context remains.

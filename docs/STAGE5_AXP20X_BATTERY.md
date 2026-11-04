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

1. AXP22x regmap read/write access to E0/E1;
2. helpers to encode/decode that 15-bit capacity;
3. AXP221 probe logic that programs a positive DT capacity and logs its
   quantized read-back value.

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

CI dry-runs/applies the patch with `--fuzz=0` against the exact 6.18.60 source
and cross-compiles both changed objects:

- `drivers/mfd/axp20x.o`
- `drivers/power/supply/axp20x_battery.o`

Physical fuel-gauge behavior remains for hardware validation.

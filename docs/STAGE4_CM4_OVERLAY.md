# Stage 4 — cleaned uConsole CM4 device-tree overlay

**Status:** implemented; CI compile/application validation pending.

## Goal

Create a single project-owned CM4 uConsole overlay that describes required
hardware without inheriting unrelated distro/performance policy.

The deterministic build input is:

`kernel/overlays/clockworkpi-uconsole-cm4-overlay.dts`

The file carries its own `GPL-2.0-only` SPDX identifier because it derives
from Linux/uConsole device-tree work; the repository's existing MIT license is
not replaced.

## Primary hardware lineage

The conservative structural base is the AK-Rex overlay at:

- repository: `ak-rex/rpi-linux`
- commit: `0234e320bec7748fc6f1fb6904a055de10f0a727`
- path:
  `arch/arm/boot/dts/overlays/clockworkpi-uconsole-cm4-overlay.dts`

This is the same hardware-verified revision already used as CWU50 and
OCP8178 provenance.

## Panel regulator rails

Independent postmarketOS work at commit
`5cf4d21c7e55945a8256c3edceac9341660f1b29` identifies:

- panel IOVCC: AXP DCDC3 at 1.8 V;
- panel VCI: AXP ALDO2 at 3.3 V.

The cleaned overlay therefore wires:

- `iovcc-supply = <&reg_dcdc3>`
- `vci-supply = <&reg_aldo2>`

OuinOuin74's current overlay was reviewed as a design reference, but its
opposite VCI/IOVCC assignment is not adopted.

## Replaceable battery pack

The uConsole accepts user-supplied 18650 cells. Inherited 2x3350 mAh values
are therefore fallbacks rather than immutable board facts.

Only standard Linux `simple-battery` properties are used:

- fallback capacity: 6,700,000 µAh;
- fallback energy: 24,790,000 µWh;
- fallback minimum design voltage: 3,300,000 µV.

Firmware overlay overrides:

- `batt_uah`
- `batt_uwh`
- `vmin_uv`

The non-standard `nominal-microvolt` property is deliberately not carried.

## Backlight default after Stage 3

Stage 3 expanded OCP8178 brightness from levels 0..9 to 0..21.

The legacy default level 5 mapped to hardware index 16. In the new table,
user-visible level 15 maps to the same hardware index 16.

The cleaned overlay therefore uses:

`default-brightness = <15>`

## Retained hardware description

- ADC on I2C1;
- SPI4 expansion bus;
- UART1 expansion interface;
- AXP22x PMIC on I2C0;
- required 3.3 V and 1.8 V regulators;
- battery and AC power-supply children;
- established CM4 I2C0 routing/alias;
- CWU50 on DSI1;
- OCP8178 backlight on GPIO9.

## Intentionally excluded

- forced PCIe disablement;
- forced GENET/Ethernet disablement;
- SD UHS/100 MHz overclock policy;
- headphone/speaker switching (deferred to Stage 6);
- `/chosen/bootargs` UART mutation;
- non-standard `nominal-microvolt`;
- non-standard PMIC `irq-gpios`.

## Validation

The Stage 4 validator:

1. enforces required/excluded source properties;
2. fetches exact Raspberry Pi Linux 6.18.60;
3. copies the project overlay into the kernel overlay tree;
4. dry-runs and applies the Makefile patch with `--fuzz=0`;
5. builds DTBs/DTBOs for ARM64;
6. locates the uConsole DTBO and CM4 base DTB;
7. applies the compiled overlay with `fdtoverlay`;
8. decompiles the DTBO for a final structural sanity check.

Physical behavior remains for later hardware validation.

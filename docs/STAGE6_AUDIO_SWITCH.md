# Stage 6 — uConsole audio/headphone switching

**Status:** implemented; ARM64 CI and shared-overlay validation pending.

## Hardware path

The CM4 uConsole audio signals are:

- GPIO10: `HP_DET` — high when a 3.5 mm plug is inserted;
- GPIO11: `PA_EN` — high enables the internal speaker amplifier;
- GPIO12/13: PWM audio output.

Stock Raspberry Pi Linux 6.18 already provides the standard `audremap`
overlay for moving PWM audio to GPIO12/13. The later image layer must enable:

- `dtparam=audio=on`
- `dtoverlay=audremap,pins_12_13`

Those boot-policy settings do not belong in the uConsole hardware overlay.

## Community lineage

PotatoMania introduced an interrupt-driven amplifier-switch driver in 2023.
It was later carried by postmarketOS and other uConsole kernel packages.

The important behavior is correct and retained:

- react to jack insertion/removal in-kernel;
- disable the speaker automatically when headphones are inserted;
- avoid userspace polling.

## Why the original driver is not copied verbatim

The historical driver is intentionally generic and performs its output update
from a hard IRQ handler. That path allocates a bitmap with `GFP_KERNEL` and
calls `gpiod_set_array_value_cansleep()`.

The project instead uses a small uConsole-specific driver with a threaded IRQ:

- one headphone-detect input;
- one amplifier-enable output;
- `gpiod_get_value_cansleep()`;
- `gpiod_set_value_cansleep()`;
- safe speaker-off output state until the first successful input read;
- amplifier disabled on shutdown.

This keeps the proven behavior while using a cleaner modern execution model.

## Device-tree semantics

The Stage 6 node uses semantic names and physical polarity:

- `headphone-detect-gpios = <&gpio 10 GPIO_ACTIVE_HIGH>`
- `amplifier-enable-gpios = <&gpio 11 GPIO_ACTIVE_HIGH>`

This is clearer than the older generic `sw-gpios`/`outputs-gpios` interface.
The hardware documentation identifies GPIO10 as `HP_DET`, with value 1 when a
plug is inserted, and GPIO11 as `PA_EN`, where 1 enables the speaker.

## Kernel integration

Project-owned driver:

`kernel/drivers/uconsole-amp-switch.c`

Integration patch:

`kernel/patches/0005-misc-integrate-uconsole-amplifier-switch.patch`

The driver is registered under `drivers/misc` as:

`CONFIG_UCONSOLE_AMP_SWITCH`

No separate staging subtree is introduced.

## Explicitly excluded

Stage 6 does not:

- force GPIO11 high from firmware;
- use a systemd/OpenRC service to hold the speaker enabled;
- poll GPIO10 from userspace;
- embed `snd_bcm2835.enable_headphones=1` into the uConsole overlay;
- duplicate Raspberry Pi's stock `audremap` overlay;
- add PipeWire/ALSA userspace configuration;
- attempt separate remembered volume levels for speaker/headphones.

Those userspace/image concerns belong to later packaging stages.

## Validation

The Stage 6 workflow must:

1. enforce the threaded-IRQ/non-polling driver design;
2. verify GPIO10/GPIO11 overlay semantics;
3. fetch the exact Raspberry Pi Linux 6.18.60 source;
4. copy the project driver into `drivers/misc`;
5. dry-run/apply the integration patch with `--fuzz=0`;
6. resolve `CONFIG_UCONSOLE_AMP_SWITCH=m`;
7. cross-compile `drivers/misc/uconsole-amp-switch.o`.

Because the shared uConsole overlay changed, the Stage 4 overlay workflow is
also expected to run and must remain green.

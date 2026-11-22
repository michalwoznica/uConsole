# Stage 7 — reproducible kernel configuration and Arch packaging

**Status:** complete; configuration/composition CI validation passed.

## Goal

Turn the independently proven uConsole kernel deltas into one deterministic
kernel composition and a standard Arch Linux ARM package definition.

Stage 7 deliberately stops before a complete kernel/package build. Full
build-only validation is Stage 8.

## Kernel configuration model

The platform baseline remains the pinned Raspberry Pi Linux
`bcm2711_defconfig`.

The project adds only:

`kernel/config/uconsole-cm4.config`

This fragment enables the already selected hardware paths:

- VC4/MIPI DSI and CWU50 panel;
- OCP8178 backlight;
- AXP221 MFD/ADC/battery/charger/regulator/power-key support;
- TI ADC101C;
- spidev for the exposed expansion SPI path;
- Raspberry Pi PWM audio;
- the project uConsole amplifier-switch module;
- Landlock for a modern Arch userspace security/sandboxing baseline.

A full copied `.config` is intentionally not stored.

## Composition order

The Arch package `prepare()` path performs the real project composition:

1. unpack exact Raspberry Pi Linux 6.18.60 source;
2. install exact pinned CWU50 source;
3. install exact pinned OCP8178 source;
4. install the project-owned CM4 overlay;
5. install the project-owned amplifier-switch driver;
6. apply patches `0001` through `0005` with `--fuzz=0`;
7. remove Raspberry Pi's `CONFIG_LOCALVERSION="-v8"`;
8. set package localversion files;
9. run `bcm2711_defconfig`;
10. merge `uconsole-cm4.config`;
11. run `olddefconfig`;
12. record the resulting kernel release.

Expected release for package revision 1:

`6.18.60-1-uconsole`

## Arch package

Package metadata lives at:

`image/archlinuxarm/packages/linux-uconsole/`

Package name:

`linux-uconsole`

The package installs:

- `/boot/kernel8.img`;
- Raspberry Pi DTBs;
- kernel-matched overlays, including the uConsole overlay;
- `/usr/lib/modules/<kernel-release>/...`;
- an mkinitcpio preset.

It follows the current Arch Linux ARM `linux-rpi` packaging shape where useful,
but does **not** inherit that package's moving Raspberry Pi source commit.
The project `kernel/source.lock` remains authoritative.

The package intentionally does not install `config.txt` or `cmdline.txt`.

## Deterministic staging

The package directory does not contain duplicate copies of kernel patches or
drivers.

Use:

`scripts/stage-arch-kernel-package.sh DESTINATION`

to create a self-contained makepkg workspace from the Git-tracked
authoritative project files.

## Arch boot policy

The first Arch boot-policy fragment is:

`image/shared/boot/config-uconsole-cm4.txt`

It selects:

- 64-bit firmware mode;
- CM4 USB host mode;
- project uConsole overlay;
- Pi 4/CM4 VC4 KMS;
- PWM audio on GPIO12/13;
- `/boot/kernel8.img`.

It intentionally does not restore historical `gpio=11=...` speaker forcing:
the Stage 6 kernel driver owns amplifier switching.

It also does not add SD overclocking, forced Ethernet/PCIe disablement, or
init-system-specific behavior.

Stage 9 will compose this fragment into the actual Arch image.

## Validation boundary

Stage 7 CI must prove:

- package staging is deterministic;
- PKGBUILD shell syntax is valid;
- package source commit/version match the project lock;
- the actual PKGBUILD `prepare()` path composes all five patches;
- the config fragment resolves to all required values;
- kernel release is `6.18.60-1-uconsole`;
- `make prepare` succeeds.

Stage 7 does not compile `Image`, modules, or DTBs. That is Stage 8.

## Validator false-positive correction

The first Stage 7 CI run stopped during repository-policy validation before
source composition.

The package itself was init-system neutral. The validator matched the words
`systemd/OpenRC` inside a comment explaining that no project-specific
init-system hook is added.

The policy check now removes comment-only PKGBUILD lines before searching for
forbidden init-system references. Executable package content remains subject
to the same restriction.

No package behavior, kernel configuration, boot policy, source pin, or patch
changed.

## Kbuild architecture correction

The second Stage 7 CI run reached the actual PKGBUILD `prepare()` composition
path and all five project patches applied successfully.

It then failed before configuration because the validator sourced the PKGBUILD
into the same shell where it had stored the kernel architecture in a variable
named `arch`. The PKGBUILD's standard `arch=('aarch64')` assignment replaced
that variable, causing the validator to export `ARCH=aarch64`.

Linux Kbuild uses `arm64` as the architecture directory name. `aarch64` is the
Arch Linux package/userspace architecture name.

The correction makes this distinction explicit:

- PKGBUILD keeps `arch=('aarch64')`;
- every kernel `make` invocation in the PKGBUILD passes `ARCH=arm64`;
- the validator uses `kernel_arch` rather than `arch`;
- cross-validation still passes its `CROSS_COMPILE` prefix independently.

No kernel source, patches, config fragment, boot policy, or package file layout
changed.

## Static-assertion correction

The third Stage 7 CI run stopped immediately after package staging.

This was another validator-only issue: after the Kbuild architecture fix, the
PKGBUILD correctly changed from:

`make bcm2711_defconfig`

to:

`make ARCH=arm64 bcm2711_defconfig`

but the validator still searched for the old literal string. Because the
script runs with `set -e`, that plain `grep -q` failure terminated the workflow
without an explanatory error.

The validator now:

- checks the corrected `ARCH=arm64` make commands;
- verifies all important prepare/build/install Kbuild invocations;
- reports a named PKGBUILD invariant on failure instead of exiting silently.

No PKGBUILD, kernel config, boot policy, source pin, patch, or package behavior
changed in this correction.

## Final validation result

The GitHub Actions `Validate kernel config and Arch package` workflow completed
successfully.

This proves the Stage 7 composition/package contract:

1. repository and package policy checks pass;
2. deterministic Arch package staging succeeds;
3. exact pinned Raspberry Pi Linux 6.18.60 source is fetched;
4. exact pinned CWU50 and OCP8178 sources are fetched;
5. the actual PKGBUILD `prepare()` path runs successfully;
6. patches `0001` through `0005` all apply with `--fuzz=0`;
7. `bcm2711_defconfig` plus `uconsole-cm4.config` resolves all required
   uConsole hardware symbols;
8. Linux Kbuild consistently uses `ARCH=arm64`;
9. the resulting kernel release is exactly `6.18.60-1-uconsole`;
10. the fully composed source tree passes `make prepare`.

Stage 7 is therefore complete.

A complete compile of `Image`, modules and DTBs is intentionally deferred to
Stage 8, so Stage 7 does not yet prove that the entire configured kernel
builds end-to-end.

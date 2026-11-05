# Stage 8 — full build-only validation

**Status:** complete; full CI build and package-root validation passed.

## Goal

Prove that the exact Stage 7 package composition builds end-to-end before
attempting an Arch rootfs or flashable microSD image.

Stage 8 deliberately reuses the actual `linux-uconsole` PKGBUILD functions
instead of introducing a parallel build recipe.

## Validation path

`scripts/validate-full-kernel-build.sh`:

1. stages the same deterministic Arch package workspace used in Stage 7;
2. fetches the exact pinned Raspberry Pi Linux, CWU50 and OCP8178 sources;
3. sources the staged PKGBUILD;
4. runs its real `prepare()` function;
5. runs its real `build()` function:
   - `Image`
   - modules
   - DTBs;
6. runs its real `package()` function into a temporary package root;
7. verifies the resulting kernel and package artifacts.

CI derives build parallelism from the runner with `nproc` unless `JOBS` is
explicitly supplied. This uses the CPU allocation GitHub actually assigns
without assuming a fixed hosted-runner core count. A real Arch `makepkg`
build may instead supply MAKEFLAGS from makepkg.conf.

## Required source-tree build artifacts

Stage 8 requires:

- `arch/arm64/boot/Image`;
- `panel-cwu50.ko`;
- `ocp8178_bl.ko`;
- `uconsole-amp-switch.ko`;
- AXP20x core/I2C/battery/AC/ADC/power-key/regulator modules;
- TI ADC081C module;
- `clockworkpi-uconsole-cm4.dtbo`;
- `bcm2711-rpi-cm4.dtb`.

Module filenames are checked before package installation, where they are
uncompressed `.ko` build products.

## Device-tree composition proof

The validator applies the newly built uConsole DTBO to the newly built CM4
base DTB with `fdtoverlay`.

This verifies the Stage 4 overlay still composes correctly in the complete
Stage 8 kernel build, not only in its isolated overlay workflow.

## Package-root proof

The PKGBUILD `package()` function installs into a temporary root.

Stage 8 verifies:

- `/boot/kernel8.img` exists and is byte-identical to the built `Image`;
- the CM4 DTB is installed;
- the uConsole DTBO is installed;
- `/usr/lib/modules/6.18.60-1-uconsole/` exists;
- every required uConsole/AXP module is present as `.ko*`;
- module `pkgbase` is `linux-uconsole`;
- the mkinitcpio preset names kernel release `6.18.60-1-uconsole`;
- no build/source symlink leaks remain in the package root.

The installed module check accepts `.ko*` so it remains valid whether package
policy later uses uncompressed or compressed kernel modules.

## Boundary

Stage 8 does not:

- create an Arch root filesystem;
- run pacman;
- generate an initramfs;
- install Raspberry Pi firmware;
- create a partition table/filesystem;
- make a bootable or flashable image;
- perform physical uConsole testing.

Those belong to Stage 9 and later.

## Completion criterion

Stage 8 is complete only when `Validate full uConsole kernel build` passes.

## Initial full-build timeout

The first Stage 8 CI attempt did not report a compile failure. The kernel
continued building normally until the workflow's project-defined 90-minute
job timeout cancelled it.

Correction:

- workflow timeout increased from 90 minutes and then standardized at the GitHub maximum of 360 minutes;
- validator default parallelism changed from fixed `JOBS=2` to `nproc`;
- explicit positive `JOBS` overrides remain supported;
- no kernel source, patches, config, PKGBUILD, packaging behavior, or
  validation requirements changed.

GitHub-hosted jobs currently have a six-hour execution limit, and GitHub's
workflow syntax uses 360 minutes as the default/maximum job timeout. The
project therefore standardizes long-running kernel/image jobs on 360 minutes
rather than imposing a lower project-specific ceiling.

## Final validation result

The second Stage 8 full-build run completed successfully in approximately
1 hour 19 minutes after the validator began using the runner's available CPU
parallelism.

This proves the complete Stage 8 contract:

1. deterministic package staging succeeds;
2. exact pinned Raspberry Pi Linux, CWU50 and OCP8178 inputs are fetched;
3. the real PKGBUILD `prepare()` path succeeds;
4. the real PKGBUILD `build()` path succeeds for `Image`, modules and DTBs;
5. all required uConsole, AXP20x and TI ADC modules are built;
6. the CM4 base DTB and uConsole DTBO are produced;
7. `fdtoverlay` successfully applies the built uConsole DTBO to the built CM4 DTB;
8. the real PKGBUILD `package()` path succeeds;
9. `/boot/kernel8.img` is installed and matches the built `Image`;
10. required DTBs/DTBOs and the `6.18.60-1-uconsole` module tree are installed;
11. module `pkgbase`, mkinitcpio preset and package-root leakage checks pass.

Stage 8 is complete.

## CI timeout policy

For long-running GitHub Actions jobs in this project:

- do not impose a project timeout lower than GitHub's current maximum unless
  there is a specific documented reason;
- verify the current platform limit before adding or changing a timeout;
- as of this Stage 8 completion, GitHub's standard job timeout maximum/default
  is 360 minutes, so long-running kernel/image jobs use
  `timeout-minutes: 360`.

This policy exists because the first Stage 8 build was healthy but was
artificially cancelled by the project's shorter 90-minute timeout.

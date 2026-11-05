# Stage 8 — full build-only validation

**Status:** implemented; full CI build pending.

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

CI sets `MAKEFLAGS=-j2` for a bounded hosted-runner build. A real Arch
`makepkg` build may supply a different MAKEFLAGS value from makepkg.conf.

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

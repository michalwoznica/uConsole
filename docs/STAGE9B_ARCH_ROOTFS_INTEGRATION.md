# Stage 9B — pacman-managed uConsole rootfs integration

**Status:** workspace-permission correction applied; CI validation pending.

## Goal

Take the authenticated Stage 9A Arch Linux ARM 2026.08 Raspberry Pi AArch64
rootfs and prove the custom uConsole kernel can replace the stock boot path
while keeping pacman's package database consistent.

This remains a build/integration checkpoint. It does not create a partitioned
microSD image.

## Exact stock transition

Stage 9A observed:

- `linux-aarch64`;
- `uboot-raspberrypi`;
- `firmware-raspberrypi`;
- `raspberrypi-bootloader`;
- `mkinitcpio`;
- the normal `linux-firmware*` packages.

The project `linux-uconsole` package follows Arch Linux ARM's `linux-rpi`
packaging shape and conflicts with both `linux-aarch64` and
`uboot-raspberrypi`.

Stage 9B therefore removes exactly:

- `linux-aarch64`;
- `uboot-raspberrypi`.

It retains:

- `firmware-raspberrypi`;
- `raspberrypi-bootloader`;
- `mkinitcpio`;
- `linux-firmware*`.

The result boots the Raspberry Pi firmware directly into `/boot/kernel8.img`;
U-Boot is no longer part of the intended uConsole boot chain.

## Rootfs authenticity

Stage 9B independently rechecks:

- versioned filename;
- exact byte size;
- published MD5;
- locked SHA-256;
- detached signature;
- exact Arch Linux ARM signing fingerprint.

The authenticated SHA-256 is:

`f10903be472e2662e110f0f7bae2750a30914ce3dc0fcd38ec85d3405d8c8967`

## Rootfs extraction

Unlike Stage 9A's read-only archive audit, Stage 9B needs a real filesystem
tree.

The validation job runs inside a disposable Arch Linux container as root and
extracts the authenticated archive with:

`bsdtar -xpf`

This matches Arch Linux ARM's guidance to extract rootfs archives as root so
ownership, ACLs and extended attributes can be preserved.

## Real pacman package

Stage 9B does not copy the Stage 8 package root by hand.

It stages the authoritative `linux-uconsole` PKGBUILD and runs real Arch
`makepkg` on x86_64 with:

- `CARCH=aarch64`;
- `ARCH=arm64`;
- `CROSS_COMPILE=aarch64-linux-gnu-`;
- all available runner CPUs by default.

The resulting package must be a real:

`linux-uconsole-6.18.60-1-aarch64.pkg.tar.*`

Its `.PKGINFO` must declare the expected architecture, dependencies and
conflicts before it can touch the rootfs.

## Pacman target mutation

The host/container pacman operates on the extracted ARM rootfs with:

- `--sysroot <rootfs>`;
- `--arch aarch64`.

Pacman documents `--sysroot` specifically for operating on mounted/guest
systems and `--arch` for overriding the target architecture.

AArch64 package scriptlets and ALPM hooks are intentionally not executed in
Stage 9B:

- package scriptlets are disabled with `--noscriptlet`;
- target hook directories are temporarily moved aside for the two
  transactions and restored afterward.

This means Stage 9B validates package files/database composition without
requiring QEMU user emulation.

Initramfs generation, if required by the final boot design, belongs to the
later image/boot checkpoint.

## Package transaction

1. remove `linux-aarch64` and `uboot-raspberrypi`;
2. install the real `linux-uconsole` package as explicit;
3. restore target ALPM hook directories;
4. install the project-owned `/boot/config.txt` from
   `config-uconsole-cm4.txt`.

The boot config remains image policy and is deliberately not owned by
`linux-uconsole`.

## Validation

Stage 9B requires:

- `linux-uconsole 6.18.60-1` registered;
- `linux-aarch64` absent;
- `uboot-raspberrypi` absent;
- firmware, Raspberry Pi bootloader, mkinitcpio and linux-firmware retained;
- `pacman -Dk` local database consistency;
- `pacman -Qk linux-uconsole`;
- `/boot/kernel8.img`;
- CM4 DTB;
- uConsole DTBO;
- `6.18.60-1-uconsole` modules;
- mkinitcpio preset;
- project boot config byte-for-byte installed as `/boot/config.txt`;
- `/boot/kernel8.img` owned by `linux-uconsole`;
- `/boot/config.txt` not package-owned;
- U-Boot `boot.txt`/`boot.scr` absent.

## Boundary

Stage 9B does not:

- generate an initramfs under AArch64 emulation;
- choose a final root partition UUID;
- create filesystems or partition tables;
- create a disk image;
- flash microSD;
- boot physical hardware.

Those remain later stages.

## Completion criterion

Stage 9B is complete only when:

`Validate Arch rootfs uConsole integration`

passes.

## First Stage 9B CI failure

The first Stage 9B run successfully reached the real `makepkg` invocation.

Passed before the failure:

- rootfs policy checks;
- rootfs fetch/authentication;
- rootfs extraction as container root;
- stock package-state validation;
- deterministic `linux-uconsole` package staging.

Failure:

`makepkg` running as the unprivileged `uconsole-build` user could not change
directory into the staged package workspace:

`cd: .../linux-uconsole-package: Permission denied`

Root cause:

`mktemp -d` creates the top-level Stage 9B workspace with mode `0700`. The
package directory itself was correctly chowned to `uconsole-build`, but the
build user still could not traverse the root-owned parent directory.

Correction:

- set the disposable top-level Stage 9B work directory to mode `0755`;
- keep ownership of sensitive/rootfs content unchanged;
- continue to chown only the build workspace, package destination and build
  home to `uconsole-build`;
- change `useradd` to `--no-create-home` because the build home is created
  explicitly before user creation.

No kernel source, PKGBUILD, rootfs input, package transition, pacman policy or
boot policy changed.

Stage 9B remains open until the corrected workflow completes successfully.

## Cross-architecture pacman final-validation correction

The next Stage 9B run completed the expensive real aarch64 makepkg build and
produced:

`linux-uconsole-6.18.60-1-aarch64.pkg.tar.zst`

The target package transactions also completed and `pacman -Dk` plus
`pacman -Qk linux-uconsole` passed with 2765 files and zero missing files.

Two validator issues remained:

1. libalpm automatically attempted to execute the target rootfs's AArch64
   `ldconfig` after each transaction, producing `Exec format error` on the
   x86_64 CI host. This is separate from package scriptlets and ALPM hooks.
2. `pacman --sysroot ... -Qo /boot/kernel8.img` queried the literal path
   target rather than rewriting it under the sysroot, so the ownership check
   incorrectly inspected the CI host path.

Correction:

- temporarily remove execute permission from target `/usr/bin/ldconfig` only
  for the kernel/U-Boot pacman transactions;
- save and restore its exact original mode, including from the EXIT cleanup
  path;
- do not run a replacement ldconfig because these transactions change no
  shared libraries;
- verify kernel ownership using `pacman -Ql linux-uconsole`;
- verify project-owned `/boot/config.txt` is absent from all local pacman
  package file records.

No kernel rebuild settings, package contents, rootfs input, dependency policy,
boot policy or CPU parallelism changed.

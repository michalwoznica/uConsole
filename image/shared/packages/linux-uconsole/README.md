# linux-uconsole shared kernel package

This directory contains the package metadata only.

Do **not** duplicate kernel patches/drivers/config here. The authoritative
copies remain under `kernel/`.

Create a self-contained package workspace with:

```sh
scripts/stage-kernel-package.sh /path/to/output
```

Then run `makepkg` from that staged directory using the project's supported
aarch64 package-build environment.

Package responsibilities:

- build the exact pinned Raspberry Pi Linux source;
- apply the complete project patch series;
- merge the project config fragment onto `bcm2711_defconfig`;
- install `kernel8.img`, DTBs/overlays and kernel modules;
- integrate with the standard mkinitcpio package hook.

The package intentionally does **not** install `/boot/config.txt` or
`cmdline.txt`. Boot/image policy remains outside the kernel package and is
composed by each image target from shared and target-specific policy.

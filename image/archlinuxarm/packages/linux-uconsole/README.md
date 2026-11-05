# linux-uconsole Arch Linux ARM package

This directory contains the package metadata only.

Do **not** duplicate kernel patches/drivers/config here. The authoritative
copies remain under `kernel/`.

Create a self-contained package workspace with:

```sh
scripts/stage-arch-kernel-package.sh /path/to/output
```

Then, on an Arch Linux ARM aarch64 build host, run `makepkg` from that staged
directory.

Package responsibilities:

- build the exact pinned Raspberry Pi Linux source;
- apply the complete project patch series;
- merge the project config fragment onto `bcm2711_defconfig`;
- install `kernel8.img`, DTBs/overlays and kernel modules;
- integrate with Arch's mkinitcpio hook.

The package intentionally does **not** install `/boot/config.txt` or
`cmdline.txt`. Boot/image policy belongs to `image/archlinuxarm/boot/` and is
composed by the image-building stage.

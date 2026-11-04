# Arch Linux ARM image target

This is the first userspace/image target.

Planned responsibilities:

- obtain and prepare the Arch Linux ARM aarch64 rootfs;
- install the project's uConsole kernel package;
- configure Raspberry Pi boot files;
- configure networking and userspace packages;
- provide Arch/systemd-specific service integration;
- produce a flashable microSD image.

The existing `fabiiw05/uconsole-archlinux` project will be audited for reusable image-building concepts, but its 6.12 kernel path will be replaced.

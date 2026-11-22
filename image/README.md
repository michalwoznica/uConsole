# Image targets

The hardware/kernel layer is intentionally distro-neutral.

Image assembly is split by userspace target:

- `archlinuxarm/` — first implementation target
- `artix-openrc/` — planned later target

Shared hardware support must not acquire systemd-specific assumptions merely because Arch Linux ARM is implemented first.

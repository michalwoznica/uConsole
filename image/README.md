# Image targets

The hardware/kernel layer is intentionally distro-neutral.

Image assembly is split by userspace target:

- `shared/` — distro-neutral image policy consumed by multiple userspace targets
- `archlinuxarm/` — first implementation target
- `artix-openrc/` — Artix Linux / OpenRC implementation target

Shared hardware support must not acquire systemd-specific assumptions merely because Arch Linux ARM is implemented first.

# Shared image policy

This directory contains image policy that is genuinely distro-neutral and is consumed by more than one userspace target.

Only move content here after verifying that its behavior is independent of the target distribution and init system. Target-specific package, service, filesystem identity, and userspace policy remain under their respective image target directories.

Current shared assets:

- `boot/config-uconsole-cm4.txt` — Raspberry Pi firmware/uConsole hardware boot policy.
- `rootfs/sysctl-uconsole.conf` — distro-neutral console kernel logging policy.
- `rootfs/uconsole-brightness-keys` — distro-neutral console brightness-key handler for the uConsole input/backlight interfaces.
- `packages/linux-uconsole/` — shared pacman package definition for the uConsole kernel, DTBs, overlays and modules.

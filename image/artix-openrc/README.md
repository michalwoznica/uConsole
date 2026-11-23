# Artix / OpenRC image target

This target will provide an Artix Linux userspace with OpenRC for the uConsole.

The target reuses the same shared uConsole kernel, device-tree, boot policy,
hardware support, and distro-neutral image-building helpers as the Arch Linux
ARM target. Artix-specific code is limited to userspace integration that
genuinely differs from Arch/systemd.

## Upstream userspace source

The aarch64 userspace bootstrap comes from the ARMtix OpenRC rootfs. ARMtix is
an implementation/provenance detail of the ARM target; the public-facing image
name remains **Artix Linux / OpenRC**.

The exact audited upstream archive is pinned in `rootfs.lock`:

```text
armtix-openrc-20260921.tar.xz
SHA-256: 250abf136930f5c7d4ba1a6d2b9b56f6b32acb072e05ccb4b6ab7aa23b834699
```

The archive must be verified against the publisher's `sha256sums` metadata
before extraction.

## Current status

Only source provenance is pinned at this point. The Artix rootfs composer and
image builder have not yet been implemented.

Before package transactions are introduced, the target still needs explicit
decisions for:

- ARMtix repository trust/signature handling;
- removal/replacement of the upstream generic ARM kernels and headers;
- NetworkManager + OpenRC service integration;
- DNS/resolver integration;
- Bluetooth/OpenRC service integration;
- elogind/power-button policy;
- default account and SSH policy.

Those decisions must be based on the actual ARMtix packages/configuration, not
on assumptions from x86_64 Artix or Arch Linux ARM.

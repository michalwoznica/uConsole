# Changelog

This project uses conventional project release versions. Version numbers refer
to this repository/image project and are independent of Arch Linux ARM release
naming.

## v1.0.0 — 2026-11-22

First stable public Arch Linux ARM release for the ClockworkPi uConsole CM4.

- Raspberry Pi Linux `6.18.64-1-uconsole`.
- Exact kernel commit `a40f735325391b1705161b07f36ed45e1bf04521`.
- Pinned Arch Linux ARM `2026.08` rootfs lineage.
- Physical validation on the original/2024 uConsole display revision.
- Working display/backlight/brightness controls, keyboard, Wi-Fi/DNS,
  Bluetooth discovery, USB storage, battery reporting, speaker/headphone audio
  with live switching, power-button policy, reboot and shutdown.
- Reproducible Stage 12 update workflow with explicit promotion and offline
  locked-rebuild proof.
- Public release artifact is the exact physically validated image, not a later
  rebuild.

Release image:

```text
uconsole-archlinuxarm-v1.0.0-cm4.img.zst
SHA-256 d90cf0db8862d301a1f0ba012284cd4ad862d2c11c9603b0369ee66cef0ccc19
```

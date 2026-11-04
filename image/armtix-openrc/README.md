# ARMtix / OpenRC image target

This is a planned later userspace/image target.

It should reuse the same uConsole kernel, device-tree, boot assets, and as much common image-building logic as practical, while replacing Arch/systemd-specific userspace integration with ARMtix/OpenRC equivalents.

No implementation work should begin here until the Arch Linux ARM target and shared hardware/kernel layer are proven on physical hardware.

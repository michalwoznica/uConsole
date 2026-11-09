# uConsole Arch Linux Project Handoff

**Project:** Linux for ClockworkPi uConsole (Raspberry Pi CM4 Lite, original 2024 display)
**Status date:** 2026-11-09
**Document revision:** 5.6
**Current phase:** Stage 11 console-usability image rebuild correction; CI pacman sysroot keyring path fix pending validation, then broader hardware validation resumes

---

## 1. Project goal

Build and maintain a reproducible Linux system for a ClockworkPi uConsole using:

- Raspberry Pi Compute Module 4 Lite (`104000`; no eMMC)
- Original/older uConsole display revision from 2024
- microSD boot/storage
- Arch Linux ARM as the first userspace target
- ARMtix/Artix with OpenRC as a later userspace target
- Raspberry Pi Linux `rpi-6.18.y` as the shared kernel base
- A minimal uConsole-specific patchset rather than a permanently forked kernel tree
- Normal Arch-style packaging so the kernel can be rebuilt and upgraded later
- A deterministic image-building path

The project should remain understandable and reproducible months later, not merely produce one working image.

---

## 2. Reproducibility and project-history policy

The project is maintained in the user's own GitHub repository.

Every completed implementation stage should:

1. have one narrow goal;
2. produce independently reviewable changes;
3. be validated before moving on;
4. be committed to Git;
5. update this handoff document;
6. record what is proven, what remains assumed, and what comes next.

The handoff filename must remain exactly:

`UCONSOLE_ARCH_PROJECT_HANDOFF.md`

Version/revision information belongs inside the file so Git tracks it as one evolving document.

Checkpoint workflow:

- Git repository is authoritative.
- Assistant supplies complete checkpoint ZIPs without `.git/`.
- User overlays/extracts them into the local repository.
- User reviews `git diff`, commits, and pushes.
- Deletions/renames must be explicitly called out because ZIP overlay alone does not remove old files.

---

## 3. Multi-distro architecture policy

Arch Linux ARM is the **first implementation target**, but the project is deliberately shaped so that **ARMtix/Artix with OpenRC can be added later** without redesigning the hardware-support layer.

```text
shared uConsole hardware/kernel support
                |
        +-------+-------+
        |               |
        v               v
 Arch Linux ARM    ARMtix / OpenRC
   first target      later target
```

Therefore:

- kernel patches remain distro-neutral;
- device-tree and boot-hardware logic remain distro-neutral;
- shared build scripts avoid systemd assumptions;
- distro/init-specific userspace logic lives under separate image-target directories;
- systemd-specific integration belongs only in the Arch Linux ARM image layer;
- OpenRC-specific integration will later live in the ARMtix target.

Planned image layout:

```text
image/
├── archlinuxarm/
└── armtix-openrc/
```

The Arch target will be completed and physically validated first.

---

## 4. Hardware facts

### uConsole

- ClockworkPi uConsole
- 2024 generation
- Original/older screen revision

### Compute Module

- Raspberry Pi Compute Module 4 Lite
- Module code: `104000`
- No onboard eMMC
- Boots from the uConsole microSD slot

---

## 5. Starting repository investigated

Initial project:

- https://github.com/fabiiw05/uconsole-archlinux

This is best understood as a complete image builder rather than merely a kernel patch collection.

Useful parts likely worth retaining or adapting later:

- Arch Linux ARM rootfs handling
- partition and image creation
- first-boot root filesystem expansion
- NetworkManager setup
- general boot-image assembly
- some uConsole-specific userspace setup

Its 6.12 kernel builder should not be treated as our long-term kernel architecture.

---

## 6. Kernel lineage investigation

Relevant projects investigated:

- ClockworkPi uConsole:
  https://github.com/clockworkpi/uConsole
- AK-Rex:
  https://github.com/ak-rex/rpi-linux
- OuinOuin74:
  https://github.com/OuinOuin74/linux-clockwork-arch
- KondratokGK:
  https://github.com/KondratokGK/linux-clockwork-arch
- ClusterM:
  https://github.com/ClusterM/ClockworkPi-linux
- PotatoMania:
  https://github.com/PotatoMania/uconsole-cm3
- Raspberry Pi kernel:
  https://github.com/raspberrypi/linux
- postmarketOS packages:
  https://pkgs.postmarketos.org/

Main conclusion:

```text
official raspberrypi/linux
        rpi-6.18.y
             +
small auditable uConsole patchset
             +
distro-neutral kernel package
```

Linux 6.18 LTS is preferred over 6.12 and short-lived 7.x branches for long-term maintainability.

---

## 7. Intended uConsole-specific delta

### Required

1. CWU50 LCD panel driver
2. OCP8178 backlight driver
3. uConsole CM4 device-tree overlay

### Strongly desirable

4. small AXP20x battery/fuel-gauge improvements
5. headphone/speaker amplifier switching

### Keep stock unless testing proves otherwise

- CM4 CPU/platform support
- VC4/KMS GPU
- Wi-Fi
- Bluetooth
- SD
- USB
- I2C
- SPI
- UART
- GPIO
- TI ADC driver
- generic AXP20x support
- VC4 DSI internals

---

## 8. Provenance decisions

### CWU50 panel

Preferred source: modern AK-Rex unified CWU50 lineage.

Reasons:

- supports old and new panel revisions;
- retains original-panel initialization;
- includes DSI diagnostics;
- avoids adopting an entire kernel fork.

### OCP8178 backlight

Preferred design:

- AK-Rex behavior/state handling as base;
- evaluate ClusterM's 22-level brightness map.

### CM4 device tree

Create a cleaned project-specific overlay:

- conservative AK-Rex structure;
- selected useful modern OuinOuin74 properties;
- avoid unrelated policy such as forced PCIe/Ethernet disablement and SD overclocking;
- make battery capacity configurable where practical.

### AXP20x battery

Start from stock Raspberry Pi 6.18.

Add only small proven improvements, potentially:

- correct design capacity;
- correct design energy;
- fuel-gauge capacity handling.

Do not import an entire alternate AXP subsystem.

### Power button

Use stock 6.18 `axp20x-pek` initially.

### Audio/headphone switching

Prefer PotatoMania's simple amplifier-switch design.

### DSI recovery

Use stock Raspberry Pi 6.18 VC4/DSI plus modern CWU50 diagnostics first.

Do not carry old invasive VC4 DSI workarounds unless physical testing demonstrates a real failure.

---

## 9. Target repository architecture

```text
.
├── README.md
├── LICENSE
├── docs/
│   ├── PROVENANCE.md
│   └── UCONSOLE_ARCH_PROJECT_HANDOFF.md
├── kernel/
│   ├── README.md
│   ├── config/
│   └── patches/
├── image/
│   ├── README.md
│   ├── archlinuxarm/
│   └── armtix-openrc/
└── scripts/
```

The repository should be a build recipe, not a snapshot of a modified Linux source tree.

---

## 10. Planned stages

### Stage 0 — Repository bootstrap

Create:

- README
- license
- `.gitignore`
- handoff
- provenance document
- shared kernel structure
- Arch Linux ARM image target
- reserved ARMtix/OpenRC image target

### Stage 1 — Pin exact Raspberry Pi 6.18 baseline

Record:

- repository
- branch
- exact commit hash
- kernel version
- selection rationale

### Stage 2 — Dry-port CWU50 panel

### Stage 3 — Dry-port OCP8178 backlight

### Stage 4 — Create cleaned CM4 overlay

### Stage 5 — Minimal AXP20x battery patch

### Stage 6 — Audio/headphone switching

### Stage 7 — Kernel config and Arch-style packaging

### Stage 8 — Build-only validation

### Stage 9 — Arch Linux ARM image-builder integration

### Stage 10 — First microSD image

### Stage 11 — Physical hardware validation

Validate at minimum:

- boot
- LCD
- backlight
- keyboard
- Wi-Fi
- Bluetooth
- audio
- headphone switching
- battery
- charging
- power button
- USB
- SD
- GPU/KMS
- reboot/shutdown

### Stage 12 — Reproducible update/rebuild path

### Later milestone — ARMtix/OpenRC image target

Reuse the proven shared kernel/hardware layer and replace Arch/systemd-specific userspace integration with ARMtix/OpenRC equivalents.

---

## 11. Proven vs unproven

### Proven through investigation

- Existing Arch/uConsole image builders exist.
- Modern uConsole support exists beyond 6.12.
- Raspberry Pi maintains a 6.18 kernel branch.
- The required uConsole-specific delta is much smaller than the original ClockworkPi monolithic patch.
- Patch-based packaging is practical.
- Arch-first / ARMtix-later can share the same kernel/hardware layer.

### Proven by this project

- CWU50 compile compatibility against the pinned 6.18.60 baseline;
- OCP8178 compile compatibility against that baseline;
- cleaned CM4 DT overlay compilation/application;
- minimum AXP20x battery delta integration;
- audio-switch driver integration;
- full kernel/modules/DTB build and package construction;
- authenticated Arch Linux ARM rootfs integration;
- deterministic partition/boot contract;
- first physical uConsole boot into Arch Linux ARM userspace;
- physical CWU50 display output after correcting Stage 10 backlight/module
  integration;
- physical OCP8178 backlight operation;
- VC4/DRM with a live DSI connector on the physical device;
- built-in keyboard sufficient for local console login and commands.
- Wi-Fi hardware/driver can associate and pass IPv4 traffic on the physical device;
- pacman 7 download sandbox works when Landlock is activated;
- console printk level 3 prevents routine kernel/device messages from overwriting tty1.

### Still unproven / incomplete

- full Wi-Fi throughput/reliability validation and Bluetooth validation;
- audio output and headphone/speaker switching validation;
- battery/charging/fuel-gauge validation;
- power-button behavior;
- broader USB/SD/GPU functional and reliability testing;
- reboot/shutdown reliability beyond the diagnostic shutdown test;
- long-duration hardware reliability;
- byte-for-byte image reproducibility across independent builds;
- ARMtix/OpenRC image target.

---

## 12. Current step

### Stage 0 — repository bootstrap: COMPLETE
### Stage 1 — Raspberry Pi Linux 6.18.60 baseline: COMPLETE
### Stage 2 — CWU50 panel dry-port: COMPLETE
### Stage 3 — OCP8178 backlight dry-port: COMPLETE
### Stage 4 — cleaned uConsole CM4 device-tree overlay: COMPLETE
### Stage 5 — minimal AXP20x/AXP221 battery delta: COMPLETE
### Stage 6 — audio/headphone speaker switching: COMPLETE
### Stage 7 — kernel configuration and Arch packaging: COMPLETE
### Stage 8 — full build-only validation: COMPLETE
### Stage 9A — pin/authenticate Arch Linux ARM rootfs: COMPLETE
### Stage 9B — pacman-managed uConsole rootfs integration: COMPLETE
### Stage 9C — final boot command line/initramfs policy: COMPLETE

### Stage 10 — first partitioned microSD image: COMPLETE

Final Stage 10 evidence:

- authenticated rootfs preparation: PASS;
- real aarch64 `linux-uconsole` build: PASS;
- pacman-managed stock kernel/U-Boot replacement: PASS;
- final boot/root policy installation: PASS;
- 8 GiB raw image creation: PASS;
- explicit 512-byte logical-sector loop device: PASS;
- deterministic DOS/MBR partition table: PASS;
- disk ID `0x55434f4e`: PASS;
- boot partition: 512 MiB FAT32, PARTUUID `55434f4e-01`;
- root partition: ext4, PARTUUID `55434f4e-02`;
- boot FAT label `UCONBOOT`: PASS;
- root label `UCONSOLEROOT`: PASS;
- fixed root filesystem UUID: PASS;
- rootfs capacity/headroom gate: PASS;
- ext4 root population with Unix metadata: PASS;
- FAT boot population: PASS;
- kernel/DTB/uConsole DTBO/modules validation: PASS;
- final config/cmdline/fstab validation: PASS;
- `linux-uconsole` local package DB validation: PASS;
- no stock kernel/U-Boot DB residue: PASS;
- no U-Boot boot-script residue: PASS;
- FAT fsck: PASS;
- ext4 fsck: PASS;
- raw image SHA-256: generated;
- zstd compression/integrity: PASS;
- compressed image SHA-256: generated;
- manifest: generated;
- exact `linux-uconsole` package: preserved;
- workflow artifact upload: PASS.

Workflow artifact name:

`uconsole-archlinuxarm-stage10`

Expected artifact contents include the compressed `.img.zst`, raw/compressed
SHA-256 files, Stage 10 manifest and exact `linux-uconsole` package.

### Stage 10 physical display/module integration correction: COMPLETE / PHYSICALLY VALIDATED

The first physical boot of the untouched Stage 10 artifact produced a brief
backlight flash followed by a black panel. A current official ClockworkPi CM4
image was tested repeatedly on the same uConsole and displayed normally,
ruling out a basic hardware/display fault.

The investigation proved that the Stage 10 image itself reached Linux and
userspace, and that the uConsole DT overlay applied, but the display modules
were not autoloaded. The installed target module directory contained
`panel-cwu50.ko.xz` and `ocp8178_bl.ko.xz` but lacked the depmod-generated
`modules.dep`, `modules.alias`, `modules.devname` and related metadata. This
was caused by the intentional suppression of target ALPM hooks/scriptlets in
the cross-architecture pacman transaction; the normal kernel depmod hook was
therefore skipped as a side effect.

The manually repaired test card proved the required correction:

1. adding `gpio=9=op,dh` to `config.txt` made the backlight remain asserted;
2. running host-side `depmod -b <target-root> 6.18.60-1-uconsole` generated the
   missing module metadata;
3. `modinfo` then resolved both `panel_cwu50` and `ocp8178_bl` with their DT
   aliases;
4. the same card booted to the Arch login prompt with visible console output;
5. live inspection showed CWU50/OCP8178 loaded, VC4/DRM active, a DSI connector
   present and the backlight class device created.

The repository correction now:

- asserts GPIO9 in the generated boot config;
- runs host-side `depmod` explicitly after the cross-architecture kernel
  package transaction;
- validates the generated kmod metadata and CWU50/OCP8178 module aliases;
- validates that the metadata survives into the populated image.

No kernel source/patch, DT overlay, package version, rootfs pin, partition
geometry, PARTUUID, filesystem identity or direct-root boot policy changed.

Fresh corrected-image revalidation subsequently passed end to end:

- corrected Stage 10 CI workflows: PASS;
- workflow artifact ZIP SHA-256:
  `27919add8106ca637ae0416f1b473e014734aa1b77300bac50c2c3e1b8c88051`;
- compressed image checksum verification: PASS;
- kernel package SHA-256:
  `ca53afee2b42af14dab64fc31de2f283cd10051867a8d25a05b8069f1dbca1fb`;
- raw image SHA-256:
  `e2ca929b5cf4e9d263ea9fe2705d49e71e2133e463735dc6127a7017fcda8721`;
- compressed image SHA-256:
  `b75f6284503dc7f0ea6266006fb0a8ef18fb162ed1bc81da2e4a107a2821ce99`;
- freshly flashed untouched media booted with no manual repair: PASS;
- visible boot output and Arch login console: PASS;
- interactive login as the stock Arch Linux ARM user: PASS;
- live CWU50/OCP8178 module loading: PASS;
- VC4/DRM DSI connector and backlight class presence: PASS.

The early old-panel/regulator retry messages observed from CWU50 resolve during
probe; the panel subsequently binds and renders the console. They are recorded
as non-blocking runtime behavior rather than a Stage 10 failure.

### Repository privacy/publication policy

Treat Git history as permanently public. Never commit user/host identifiers,
usernames, account IDs, machine-specific absolute paths or other PII. Continue
privacy audits before every checkpoint and before publication.

### Stage 11 — physical hardware validation: IN PROGRESS

Already physically proven:

- kernel/rootfs boot to Arch Linux ARM login console;
- CWU50 panel output;
- OCP8178 backlight;
- VC4/DRM DSI path;
- built-in keyboard sufficient for login and shell commands;
- controlled systemd shutdown from the diagnostic service.

### NEXT — rebuild once with Stage 11 usability fixes, then resume hardware validation

Physical testing exposed base-image usability gaps that unnecessarily slowed
validation. The next image revision folds those findings into the build:

- activate Landlock by default with `CONFIG_LSM="landlock"` so pacman 7's
  download sandbox works without a boot-time workaround;
- use console log level 3 so routine kernel/device messages stay out of tty1;
- install a compact console-first administration/validation package set,
  including NetworkManager (`nmcli`/`nmtui`), USB, ALSA, Bluetooth, input,
  I2C, Ethernet, thermal, stress, Raspberry Pi, throughput and memory tools;
- make NetworkManager the default manager for normal interfaces;
- keep `systemd-resolved` and explicitly wire `/etc/resolv.conf` to its stub;
- disable systemd-networkd services so two network managers do not compete;
- initialize a unique pacman keyring automatically on first boot so package
  signature verification works without any manual bootstrap command.

After the rebuilt image boots and networking/package management are usable,
continue the remaining Stage 11 hardware matrix directly rather than spending
more time bootstrapping diagnostic tools.

---

## 13. Continuation instructions

In a fresh ChatGPT conversation:

1. provide this handoff file;
2. provide/link the current GitHub repository;
3. ask the assistant to inspect repository state before changing anything;
4. continue from **Current step**;
5. do not redo completed stages without evidence of a problem;
6. preserve the small-patch, upstream-first, distro-neutral architecture;
7. update this exact handoff filename whenever a stage completes.

---

## 14. Change log

### 2026-11-09 — Revision 5.6 / CI pacman sysroot keyring path correction

- Recorded the next console-usability image-build failure: the temporary pacman
  keyring was initialized successfully outside the target root, but the
  subsequent `pacman --sysroot` transaction still reported `Public keyring not
  found`, `keyring is not writable`, and `required key missing from keyring`.
- Root cause: the build keyring lived under the outer Docker work directory,
  while `pacman --sysroot` operates from the staged target root. The explicitly
  supplied external GPG path was therefore not the correct keyring location for
  the target-root transaction.
- Moved the temporary verification keyring to the staged target's normal
  `/etc/pacman.d/gnupg` location, initialize/populate it there before package
  operations, and let `pacman --sysroot` use its normal target GPGDir. Package
  signature verification remains enabled.
- Added pre-transaction checks for the generated public keyring/trust database.
- After all pacman operations and package-database validation complete, the
  builder removes the temporary target GPG directory so no CI-generated private
  key ships in the image. The existing first-boot service remains responsible
  for creating a unique pacman keyring on each installed uConsole.
- No package-set, NetworkManager, DNS, Landlock kernel, console logging, boot,
  partition, or hardware-support policy changed in this correction.

### 2026-11-09 — Revision 5.5 / CI pacman keyring initialization ordering fix

- Recorded the next console-usability image-build failure: the kernel package
  built successfully, but CI stopped while preparing the build-host pacman
  keyring because `pacman-key --populate` was invoked before a local key had
  been created. Pacman reported `There is no secret key available to sign
  with` and explicitly required `pacman-key --init`.
- Corrected the build-only keyring sequence to create an isolated temporary
  GnuPG directory under the rootfs-builder work directory, run `pacman-key
  --init`, then populate both the Arch and Arch Linux ARM distribution trust
  roots before any target-rootfs package transaction.
- Kept this keyring strictly build-local. The generated image continues to
  create its own unique pacman keyring on first boot through
  `uconsole-pacman-keyring-init.service`; no CI private key is copied into the
  image.
- No target package set, NetworkManager policy, Landlock kernel policy, or
  console logging policy changed in this correction.

### 2026-11-09 — Revision 5.4 / CI pacman keyring and first-boot trust correction

- Recorded the second Stage 11 console-usability image-build failure after the
  Landlock builder correction: repository synchronization and package downloads
  succeeded, but the target `--sysroot` had no initialized pacman keyring and
  signature verification stopped with `keyring is not writable` /
  `required key missing from keyring`.
- Kept package signature verification enabled. The disposable x86_64 builder
  now imports the authenticated rootfs's `archlinuxarm` distribution keyring
  into the builder's own initialized pacman keyring and explicitly points the
  cross-architecture pacman transaction at that host keyring.
- Deliberately do not copy the builder's local/private signing material into
  the published image. Added `uconsole-pacman-keyring-init.service`, enabled in
  the image, to run `pacman-key --init` and populate the packaged Arch + Arch
  Linux ARM trust roots once on first boot before the login console. Each
  flashed installation therefore creates its own local pacman keyring.
- Excluded `linux-aarch64` and `uboot-raspberrypi` from the full userspace
  upgrade because the build removes them immediately afterward when installing
  `linux-uconsole`; this avoids needless download/installation work without
  weakening the rest of the rolling userspace update.

### 2026-11-09 — Revision 5.3 / CI pacman Landlock sysroot correction

- Recorded the first Stage 11 console-usability image-build failure after the
  kernel package completed successfully.
- Isolated the failure to host-side pacman running inside the disposable
  GitHub Actions Docker container: its download process could not apply a
  Landlock filesystem ruleset to the target `--sysroot`.
- Distinguished this from the target uConsole Landlock fix: the target kernel
  is not running during rootfs composition, so its `CONFIG_LSM="landlock"`
  cannot affect the builder's pacman process.
- Added `--disable-sandbox-filesystem` only to the rootfs builder's host-side
  pacman wrapper. This preserves syscall sandboxing where available and leaves
  the generated target `/etc/pacman.conf` unchanged.
- Retained normal pacman sandboxing on the booted image, backed by the uConsole
  kernel's enabled Landlock LSM.

### 2026-11-08 — Revision 5.2 / Stage 11 console-usability image correction

- Recorded that physical Wi-Fi association and IPv4 connectivity work.
- Identified missing persistent DNS/network-management ergonomics in the bare
  image as a userspace-image gap rather than a uConsole Wi-Fi driver failure.
- Added NetworkManager as the default console-friendly network manager while
  retaining `systemd-resolved` and disabling systemd-networkd services.
- Added the 13-package console/validation baseline: `networkmanager`,
  `usbutils`, `alsa-utils`, `bluez`, `bluez-utils`, `evtest`, `i2c-tools`,
  `ethtool`, `lm_sensors`, `stress-ng`, `raspberrypi-utils`, `iperf3` and
  `memtester`.
- Changed rootfs construction to perform a full `pacman -Syu` transaction when
  installing that package set, avoiding unsupported partial upgrades against
  the pinned rootfs's aging repository metadata.
- Recorded the pacman 7 sandbox failure and physical proof that Landlock works
  when activated; added `CONFIG_LSM="landlock"` to the kernel configuration.
- Made console log level 3 part of the image policy to keep routine kernel
  messages from overwriting tty1 while preserving them in logs.
- No graphical environment or GUI-only management package was added; the image
  remains a console-first starting point.

### 2026-11-06 — Revision 5.1 / corrected Stage 10 physical revalidation PASS

- Recorded successful corrected Stage 10 CI workflows.
- Preserved and independently verified the corrected artifact ZIP, kernel
  package, raw image and compressed-image SHA-256 values.
- Recorded a fresh flash to clean media with no post-build modification.
- Confirmed untouched physical boot to visible Arch Linux ARM login console.
- Confirmed interactive login succeeded.
- Confirmed live `panel_cwu50`, `ocp8178_bl`, VC4/DRM, DSI connector and
  backlight-class state.
- Closed the Stage 10 display/module-integration correction as physically
  validated and moved the immediate project focus to the broader Stage 11
  hardware matrix.
- Added no photos, captured device logs, user/host identifiers or other PII to
  the repository; only textual validation conclusions and non-personal
  artifact identities were recorded.


### 2026-11-06 — Revision 5.0 / Stage 10 physical display/module correction

- Recorded the first physical Stage 10 boot and official-image control test.
- Confirmed hardware/display path works with the official ClockworkPi image.
- Confirmed the custom Stage 10 image boots Linux/userspace despite the black
  display.
- Diagnosed missing target kmod metadata after the intentionally hook-suppressed
  cross-architecture pacman transaction.
- Confirmed `panel-cwu50.ko.xz` and `ocp8178_bl.ko.xz` were present but could
  not be resolved before `depmod`.
- Physically proved that `gpio=9=op,dh` plus target-root `depmod` restores the
  visible CWU50/OCP8178/VC4/DRM display stack and reaches the Arch login prompt.
- Folded GPIO9 assertion and explicit host-side `depmod` into the Stage 10
  builders.
- Added rootfs/image gates for generated module metadata and module aliases.
- Marked Stage 11 physical validation in progress, with fresh corrected-image
  CI/physical revalidation as the immediate bounded next step.
- Preserved kernel/overlay/package/rootfs/partition identities and public-history
  privacy policy.


### 2026-11-06 — Revision 4.9 / Stage 10 complete

- Recorded successful completion of the first real partitioned microSD image.
- Confirmed deterministic MBR/PARTUUID and FAT/ext4 construction.
- Confirmed populated root/boot filesystems and package/boot integrity.
- Confirmed FAT/ext4 filesystem checks.
- Confirmed zstd compression and compressed-image integrity.
- Confirmed raw/compressed SHA-256 generation, manifest generation and exact
  kernel-package preservation.
- Confirmed workflow artifact upload.
- Marked Stage 10 complete.
- Set bounded physical uConsole validation as next.
- Preserved privacy/public-history policy.


### 2026-11-06 — Revision 4.8 / Stage 10 FAT label correction

- Recorded successful deterministic partition-table construction.
- Confirmed exact boot/root partition geometry.
- Recorded the non-fatal sfdisk reread warning followed by successful explicit detach/reattach with partition scanning.
- Diagnosed FAT label-length failure: `UCONSOLEBOOT` was 12 characters.
- Changed boot FAT label to `UCONBOOT` (8 characters).
- Changed no partition/PARTUUID/rootfs/kernel/package/boot behavior.
- Stage 10 remains CI-pending.


### 2026-11-06 — Revision 4.7 / Stage 10 sfdisk compatibility correction

- Recorded first Stage 10 host image-builder failure.
- Diagnosed unsupported sfdisk `--sector-size` option on the Ubuntu 24.04 runner.
- Moved explicit 512-byte logical-sector configuration to the loop device via `losetup --sector-size`.
- Added pre/post partition-scan sector-size verification with `blockdev`.
- Kept all partition geometry, disk/PARTUUID identity and image policy unchanged.
- Stage 10 remains CI-pending.


### 2026-11-06 — Revision 4.6 / Stage 10 image candidate

- Added concrete 8 GiB image geometry to the deterministic layout contract.
- Added fixed filesystem labels/IDs.
- Added Stage 10 authenticated integrated-rootfs builder.
- Added host-VM raw image constructor using loop devices, FAT32 and ext4.
- Added package/boot/partition/filesystem validation.
- Added zstd image artifact, raw/compressed checksums and manifest.
- Added exact linux-uconsole package to workflow artifact.
- Preserved dynamic `nproc` parallelism and 360-minute timeout.
- Added explicit statement that Stage 10 is structurally reproducible but does
  not yet claim byte-identical image checksums across independent builds.
- Stage 10 remains CI-pending.


### 2026-11-06 — Revision 4.5 / Stage 9C complete

- Recorded successful completion of all corrected Stage 9C workflows.
- Marked deterministic image identity, cmdline, fstab, firmware boot policy and direct-root kernel prerequisites as proven.
- Confirmed no U-Boot and no firmware-loaded initramfs for the first image.
- Preserved expansion-UART/no-serial-console policy.
- Set Stage 10 first partitioned microSD image construction as next.
- Retained dynamic `nproc` parallelism, maximum CI timeout and public-history privacy policy.


### 2026-11-05 — Revision 4.4 / Stage 9C PARTUUID validator correction

- Recorded the first Stage 9C CI failure.
- Diagnosed raw `UUID=` substring matching as a false positive against valid
  `PARTUUID=` entries.
- Made unstable-addressing validation token-boundary aware.
- Changed no boot policy, PARTUUID, cmdline, fstab, kernel config or package
  input.
- Stage 9C remains CI-pending.


### 2026-11-05 — Revision 4.3 / Stage 9C candidate

- Defined deterministic DOS/MBR image identity `0x55434f4e`.
- Defined stable boot/root PARTUUIDs.
- Added final one-line Raspberry Pi kernel command line.
- Selected direct ext4 microSD root boot without firmware-loaded initramfs.
- Preserved `8250.nr_uarts=1` as explicit boot policy while leaving the
  expansion UART free of serial-console use.
- Added deterministic `/etc/fstab` policy.
- Added exact pinned-kernel checks for built-in microSD/ext4 root support.
- No kernel source or PKGBUILD changed.
- Stage 9C remains CI-pending.


### 2026-11-05 — Revision 4.2 / Stage 9B complete

- Recorded successful final Stage 9B workflow.
- Confirmed real aarch64 package build and complete target pacman transition.
- Confirmed `pacman -Dk`.
- Confirmed `pacman -Qk linux-uconsole`: 2765 files, 0 missing.
- Confirmed `boot/kernel8.img` in authoritative local package file records.
- Confirmed `boot/config.txt` is deliberately unowned by packages.
- Marked Stage 9B complete.
- Set Stage 9C boot-command-line/initramfs policy as next.
- Retained dynamic `nproc` CPU parallelism and maximum CI timeout policy.


### 2026-11-05 — Revision 4.1 / Stage 9B local-database ownership correction

- Recorded successful real package build and complete target package
  transaction through `pacman -Dk` and `pacman -Qk`.
- Recorded `linux-uconsole`: 2765 files, 0 missing.
- Removed dependence on exact human-readable `pacman -Ql` formatting.
- Validate `boot/kernel8.img` directly in the installed linux-uconsole local
  package `files` record.
- Continue proving `boot/config.txt` is image-policy-owned by requiring it to
  be absent from all package `files` records.
- No functional build, package, rootfs, boot or parallelism behavior changed.
- Stage 9B remains CI-pending.


### 2026-11-05 — Revision 4.0 / Stage 9B cross-architecture pacman correction

- Recorded successful real aarch64 package build and target package
  transaction evidence.
- Diagnosed foreign-architecture `ldconfig` as the source of transaction-end
  `Exec format error` messages.
- Temporarily suppress target ldconfig execution only during the two kernel
  package transactions and restore its exact mode afterward.
- Replaced incorrect `--sysroot -Qo` path ownership checks with package/local
  DB file-record checks.
- Confirmed no build parallelism restriction was introduced.
- Strengthened public-repository privacy/Git-history policy.
- Stage 9B remains CI-pending.


### 2026-11-05 — Revision 3.9 / Stage 9B workspace-permission correction

- Corrected the previous premature Stage 9B completion status.
- Recorded that the first Stage 9B run reached the real unprivileged makepkg
  invocation.
- Diagnosed `Permission denied` as `mktemp -d` parent mode `0700`, not a
  package/kernel failure.
- Made the disposable top-level work directory traversable (`0755`).
- Changed build-user creation to `--no-create-home` to avoid the harmless
  existing-home warning.
- No functional build/package/rootfs policy changed.
- Stage 9B remains validation-pending.


### 2026-11-05 — Revision 3.8 / Stage 9B complete

- Recorded successful `Validate Arch rootfs uConsole integration` workflow.
- Confirmed real aarch64 `linux-uconsole` makepkg build.
- Confirmed pacman-managed replacement of `linux-aarch64` and
  `uboot-raspberrypi`.
- Confirmed retained Raspberry Pi firmware/bootloader, mkinitcpio and
  linux-firmware packages.
- Confirmed target pacman DB and package-file integrity.
- Confirmed direct-firmware boot layout and project-owned `/boot/config.txt`.
- Marked Stage 9B complete.
- Set Stage 9C boot-command-line/initramfs policy as next.


### 2026-11-05 — Revision 3.7 / Stage 9A complete, Stage 9B candidate

- Marked Stage 9A complete after successful archive-native provenance and
  inventory validation.
- Promoted authenticated rootfs SHA-256 into `rootfs.lock`.
- Recorded the exact successful stock kernel/boot package inventory.
- Corrected the Stage 9B replacement set to include both `linux-aarch64` and
  `uboot-raspberrypi`, matching `linux-uconsole`/`linux-rpi` conflict policy.
- Added a real cross-architecture Arch `makepkg` package build.
- Added pacman-managed target-rootfs replacement using `--sysroot` and
  `--arch aarch64`.
- Added direct-firmware boot-policy installation and package/database checks.
- Stage 9B remains validation-pending.


### 2026-11-05 — Revision 3.6 / Stage 9A archive-native audit correction

- Recorded successful cryptographic authentication of the pinned 2026.08
  rootfs with the exact official Arch Linux ARM signing fingerprint.
- Recorded SHA-256
  `f10903be472e2662e110f0f7bae2750a30914ce3dc0fcd38ec85d3405d8c8967`.
- Diagnosed the remaining failure as unprivileged restoration of Linux
  capability xattrs during full extraction.
- Removed full rootfs extraction from Stage 9A.
- Added archive-native structure, pacman database and boot inventory audit.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.5 / Stage 9A keyring-format correction

- Recorded that `gpgv` reached the detached signature and identified the exact
  expected Arch Linux ARM signing key.
- Diagnosed `invalid packet (ctb=2d)` as keyring representation mismatch.
- Added ASCII-armored keyring detection and `gpg --dearmor` normalization.
- Binary keyrings remain supported unchanged.
- Retained exact `VALIDSIG` signer/primary-key fingerprint validation.
- No rootfs input or trust anchor changed.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.4 / Stage 9A direct-gpgv correction

- Recorded the second Stage 9A failure as a GnuPG keyring-inspection invocation
  issue.
- Removed the redundant direct keyring-membership gate.
- Made detached `gpgv` verification authoritative.
- Required machine-readable `VALIDSIG` identity to match the official Arch
  Linux ARM fingerprint as signer or primary key.
- Added diagnostics for both gpgv status and logger output.
- No rootfs version, checksum, size, mirror, or trust anchor changed.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.3 / Stage 9A signature-validator correction

- Recorded that rootfs download, exact size, MD5 and keyring extraction passed.
- Kept the official Arch Linux ARM signing fingerprint unchanged.
- Replaced brittle GnuPG colon-output matching with explicit `fpr` field
  extraction.
- Added `gpgv --status-fd` verification and require `VALIDSIG` to report the
  exact official signing fingerprint.
- No rootfs input or trust-policy decision changed.
- Stage 9A remains validation-pending.


### 2026-11-05 — Revision 3.2 / Stage 9A candidate

- Split Stage 9 into bounded rootfs-provenance and rootfs-integration
  checkpoints.
- Selected the versioned Arch Linux ARM Raspberry Pi AArch64 2026.08 rootfs.
- Explicitly prohibited the moving `-latest` alias as a build input.
- Added exact size, published MD5 and detached-signature validation.
- Anchored signature verification to Arch Linux ARM's official full signing
  fingerprint.
- Added structural and pacman-database inventory audit without executing
  AArch64 target binaries.
- Kept the Stage 9A workflow at GitHub's 360-minute job timeout.
- Stage 9A remains open until CI passes and reports the stock kernel/boot
  package inventory.


### 2026-11-05 — Revision 3.1 / Stage 8 complete

- Recorded successful full Stage 8 kernel/package build in approximately
  1 hour 19 minutes.
- Confirmed complete PKGBUILD `prepare()`, `build()` and `package()` paths.
- Confirmed Image, required modules, DTBs/DTBOs, overlay composition and
  package-root layout.
- Standardized long-running GitHub workflow timeout on the current platform
  maximum/default of 360 minutes.
- Added project policy to avoid lower CI timeouts unless specifically
  justified.
- Marked Stage 8 complete.
- Set Stage 9 Arch Linux ARM rootfs/image-builder integration as next.


### 2026-11-05 — Revision 3.0 / Stage 8 timeout correction

- Recorded the first Stage 8 run as a project-timeout cancellation rather than
  a compile failure.
- Increased the full-build workflow timeout from 90 to 240 minutes.
- Changed default CI build parallelism from fixed `-j2` to the runner's
  `nproc` CPU count.
- Retained an explicit positive `JOBS` override.
- No kernel source, config, patch, PKGBUILD, packaging, or validation contract
  changed.
- Stage 8 remains validation-pending.


### 2026-11-05 — Revision 2.9 / Stage 8 candidate

- Added the first complete build-only validation of the Stage 7 composition.
- Reused the actual staged PKGBUILD `prepare()`, `build()` and `package()`
  functions instead of adding a parallel build recipe.
- Added checks for kernel Image, uConsole modules, AXP20x modules, TI ADC,
  CM4 DTB and uConsole DTBO.
- Added built-DTB overlay application with `fdtoverlay`.
- Added package-root verification for kernel8.img, DTBs/DTBO, modules and
  mkinitcpio preset.
- Stage 8 remains open until the full-build workflow passes.


### 2026-11-05 — Revision 2.8 / Stage 7 complete

- Recorded successful `Validate kernel config and Arch package` workflow.
- Confirmed deterministic package staging and policy checks.
- Confirmed actual PKGBUILD `prepare()` composition against the pinned source.
- Confirmed patches 0001-0005 all apply with `--fuzz=0`.
- Confirmed the uConsole config resolves and kernel release is
  `6.18.60-1-uconsole`.
- Confirmed the composed tree passes `make prepare`.
- Marked Stage 7 complete.
- Set Stage 8 full build-only validation as the next step.


### 2026-11-05 — Revision 2.7 / Stage 7 static-assertion correction

- Diagnosed the post-staging exit as a stale validator assertion.
- Updated Stage 7 PKGBUILD checks for the corrected `ARCH=arm64` Kbuild
  commands.
- Added named assertion failures so future static-policy errors are explicit.
- No PKGBUILD, kernel config, boot policy, source pin, patch, or package
  behavior changed.
- Stage 7 remains validation-pending.


### 2026-11-05 — Revision 2.6 / Stage 7 Kbuild architecture correction

- Recorded that all five Stage 7 patches successfully composed in the actual
  PKGBUILD `prepare()` path.
- Diagnosed `ARCH=aarch64` as a shell-variable collision between the
  validator and the PKGBUILD's standard `arch=('aarch64')` declaration.
- Renamed the validator variable to `kernel_arch`.
- Made every PKGBUILD kernel `make` invocation explicitly use `ARCH=arm64`.
- No source, patch, config, boot-policy, or package-layout behavior changed.
- Stage 7 remains validation-pending.


### 2026-11-05 — Revision 2.5 / Stage 7 validator correction

- Diagnosed the initial Stage 7 CI failure as a validator false positive.
- Confirmed the only init-system match in the PKGBUILD was an explanatory
  comment.
- Changed the policy check to ignore comment-only lines while preserving the
  same ban on init-system references in executable package content.
- No package, kernel, boot-policy, source-pin, or patch behavior changed.
- Stage 7 remains validation-pending.


### 2026-11-05 — Revision 2.4 / Stage 7 candidate

- Defined the uConsole CM4 config fragment on top of `bcm2711_defconfig`.
- Added a pacman-managed `linux-uconsole` Arch Linux ARM package definition.
- Added deterministic package-workspace staging without duplicating
  authoritative kernel inputs in Git.
- Added the first Arch CM4 boot-policy fragment with KMS, uConsole overlay,
  USB host and PWM audio settings.
- Kept boot/image policy out of the kernel package and kept init-system policy
  out of the shared kernel layer.
- Added Stage 7 composition/config/package CI.
- Stage 7 remains open until that workflow passes.


### 2026-11-05 — Revision 2.3 / Stage 6 complete

- Recorded successful `Validate uConsole audio switch` workflow.
- Confirmed exact-source Kconfig/Makefile integration applies with
  `--fuzz=0`.
- Confirmed `CONFIG_UCONSOLE_AMP_SWITCH=m` resolves successfully.
- Confirmed `drivers/misc/uconsole-amp-switch.o` cross-compiles for ARM64.
- Confirmed the shared CM4 overlay remains green with the Stage 6 audio node.
- Marked Stage 6 complete.
- Set Stage 7 kernel configuration and Arch packaging as the next step.


### 2026-11-05 — Revision 2.2 / Stage 6 integration-patch correction

- Recorded that Stage 6 driver/overlay policy checks passed.
- Rebuilt Kconfig integration from exact CI-emitted lines.
- Narrowed the Makefile hunk to the exact two adjacent lines shown by CI,
  removing the mismatching `CONFIG_ATMEL_SSC` context.
- Improved validator diagnostics for the integration anchors.
- No driver, overlay, or functional design changes were made.
- Stage 6 remains validation-pending.


### 2026-11-04 — Revision 2.1 / Stage 6 candidate

- Audited uConsole CM4 audio routing and PotatoMania's automatic amplifier
  switch.
- Confirmed GPIO10 HP_DET, GPIO11 PA_EN and GPIO12/13 PWM audio roles.
- Kept stock Raspberry Pi `audremap,pins_12_13` for signal routing.
- Added a narrow project-owned threaded-IRQ amplifier-switch driver.
- Added semantic GPIO properties to the cleaned uConsole overlay.
- Avoided firmware GPIO11 forcing, userspace polling and the historical
  hard-IRQ `*_cansleep()` pattern.
- Added Stage 6 provenance, CI validation and design documentation.
- Stage 6 remains open until driver and overlay CI pass.


### 2026-11-04 — Revision 2.0 / Stage 5 complete

- Recorded successful `Validate AXP20x battery delta` workflow.
- Confirmed the final exact-block patch applies with `--fuzz=0` to the pinned
  Raspberry Pi Linux 6.18.60 source.
- Confirmed the minimal inline AXP221 design-capacity logic compiles for ARM64.
- Retained the zero replaceable-pack defaults and narrow Stage 5 scope.
- Marked Stage 5 complete.
- Set Stage 6 audio/headphone switching as the next step.


### 2026-11-04 — Revision 1.9 / Stage 5 exact-block correction

- Replaced reconstructed probe-function context with the exact four-line block
  emitted by CI from the pinned source.
- Generated unified-diff line counts programmatically to avoid malformed
  patch metadata.
- Removed the helper function and kept the design-capacity write inline.
- Reconfirmed no MFD change is required.
- Stage 5 remains validation-pending.


### 2026-11-04 — Revision 1.8 / Stage 5 single-hunk correction

- Removed cross-hunk offset dependence entirely.
- Colocated the design-capacity helper with the probe function.
- Rebuilt Stage 5 as exactly one contiguous patch hunk.
- Added validator enforcement that the patch contains exactly one hunk.
- Functional scope is unchanged; validation remains pending.


### 2026-11-04 — Revision 1.7 / Stage 5 probe-hunk correction

- Recorded that the Stage 4 overlay workflow remains green.
- Isolated the remaining Stage 5 failure to line-location metadata for the
  probe insertion hunk.
- Regenerated both hunks using real pinned 6.18.60 source-scale positions.
- Added exact helper/probe diagnostics to the validator.
- Stage 5 functional scope is unchanged and remains validation-pending.


### 2026-11-04 — Revision 1.6 / Stage 5 CI correction

- Fixed the Stage 4 overlay validator to expect the Stage 5 zero-capacity
  defaults.
- Rebuilt the AXP221 design-capacity patch from exact pinned 6.18.60 source
  neighborhoods.
- Removed the unnecessary MFD/regmap modification after confirming stock
  AXP22x already allows E0/E1 writes.
- Reduced Stage 5 to a single changed kernel source/object:
  `drivers/power/supply/axp20x_battery.c`.
- Stage 5 remains validation-pending until both workflows pass.


### 2026-11-04 — Revision 1.5 / Stage 5 candidate

- Audited stock 6.18.60 against AK-Rex, ClusterM, historical ClockworkPi and
  AXP228 fuel-gauge behavior.
- Selected only AXP221 design-capacity register programming as the justified
  kernel delta.
- Kept calibration, synthetic energy reporting, writable charge controls and
  unrelated PMIC policy side effects out of scope.
- Changed replaceable-pack design capacity/energy defaults to zero.
- Updated the Stage 4 validator for the refined shared-overlay policy.
- Added Stage 5 provenance, validator, CI workflow and design report.
- Stage 5 remains open until ARM64 object compilation passes.


### 2026-11-04 — Revision 1.4 / Stage 4 complete

- Recorded successful `Validate uConsole CM4 overlay` workflow.
- Confirmed the project-owned overlay compiles to a DTBO against the pinned
  Raspberry Pi Linux 6.18.60 tree.
- Confirmed the compiled overlay applies successfully to the compiled CM4 base
  DTB using `fdtoverlay`.
- Confirmed the compiled overlay retains the expected CWU50 and OCP8178
  structure.
- Marked Stage 4 complete.
- Set Stage 5 minimal AXP20x battery/fuel-gauge work as the next step.


### 2026-11-04 — Revision 1.3 / Stage 4 candidate

- Added a project-owned cleaned CM4 uConsole device-tree overlay.
- Pinned AK-Rex structural provenance and an immutable postmarketOS regulator
  mapping reference.
- Kept OuinOuin74 as a design reference rather than a build dependency.
- Selected panel supply semantics IOVCC=1.8 V DCDC3 and VCI=3.3 V ALDO2.
- Rejected non-standard `nominal-microvolt` and exposed only standard battery
  property overrides.
- Adjusted default OCP8178 brightness to preserve the pre-Stage-3 startup
  hardware index.
- Excluded PCIe/Ethernet disablement, SD overclock, deferred audio switching
  and boot-command-line policy from the hardware overlay.
- Added overlay Makefile integration, CI validation and design documentation.
- Stage 4 remains open until the compiled overlay applies successfully to the
  compiled CM4 base DTB.


### 2026-11-04 — Revision 1.2 / Stage 3 complete

- Recorded successful corrected `Validate OCP8178 port` workflow.
- Confirmed the real-source OCP8178 patch dry-runs and applies with
  `--fuzz=0`.
- Confirmed the selected 22-entry brightness refinement and AK-Rex
  `onewire_ready` behavior coexist as intended.
- Confirmed `CONFIG_BACKLIGHT_OCP8178=m` resolves and `ocp8178_bl.o`
  cross-compiles successfully for ARM64.
- Marked Stage 3 complete.
- Retained narrowed CWU50/OCP8178 workflow path filters.
- Set Stage 4 cleaned uConsole CM4 device-tree overlay as the next step.


### 2026-11-04 — Revision 1.1 / Stage 3 real-source patch correction

- Corrected the project record: Stage 3 was not actually complete.
- Diagnosed the OCP8178 CI failure as a locally generated patch-context error,
  not a kernel API failure.
- Rebuilt all OCP8178 hunks around exact minimal anchors from the real pinned
  Raspberry Pi 6.18.60 and AK-Rex source files.
- Added patch dry-run validation before actual application.
- Tightened CWU50/OCP8178 workflow path filters so unrelated kernel-stage
  changes do not repeatedly run both jobs.
- Stage 3 remains validation-pending until the corrected OCP8178 workflow
  reaches and passes ARM64 compilation.


### 2026-11-04 — Revision 1.0 / Stage 3 complete

- Recorded successful `Validate OCP8178 port` GitHub Actions run.
- Proved that the pinned AK-Rex OCP8178 driver plus the selected 22-entry
  brightness refinement cross-compiles for ARM64 against the pinned Raspberry
  Pi Linux 6.18.60 baseline.
- Confirmed AK-Rex one-wire readiness behavior remains present.
- Closed the CI executable-bit regression by retaining executable script modes
  and invoking validators explicitly with `bash`.
- Marked Stage 3 complete.
- Set Stage 4 cleaned uConsole CM4 device-tree overlay as the next step.


### 2026-11-04 — Revision 0.9 / CI executable-bit regression fix

- Diagnosed repeated GitHub Actions `Permission denied` failures for
  `scripts/validate-cwu50-port.sh`.
- Root cause: an internal ZIP extract/repack step used during checkpoint
  generation dropped the shell script executable bit, causing Git to record
  `100755 -> 100644` in the Stage 2 completion checkpoint; Stage 3 inherited
  that mode regression.
- Restored executable mode on all project shell scripts.
- Changed both CWU50 and OCP8178 GitHub Actions workflows to invoke validators
  explicitly with `bash`, so CI correctness no longer depends on ZIP-preserved
  Unix mode bits.
- Added the executable-bit/checkpoint policy to `scripts/README.md`.
- Stage 3 remains pending until the OCP8178 ARM64 validation workflow passes.


### 2026-11-04 — Revision 0.8 / Stage 3 candidate

- Pinned OCP8178 behavioral source to AK-Rex commit
  `0234e320bec7748fc6f1fb6904a055de10f0a727`.
- Preserved AK-Rex one-wire readiness handling.
- Audited ClusterM's 22-entry brightness map and froze only that narrow
  semantic delta locally.
- Kept ClusterM outside the build dependency chain.
- Added OCP8178 integration patch, source lock, validator, CI workflow, and
  Stage 3 report.
- Stage 3 remains open until ARM64 CI compilation passes.


### 2026-11-04 — Revision 0.7 / Stage 2 complete

- Recorded successful replacement GitHub Actions run for the CWU50 dry-port.
- Proved that the pinned AK-Rex CWU50 driver cross-compiles for ARM64 against
  the pinned Raspberry Pi Linux 6.18.60 baseline.
- Confirmed no functional CWU50 source adaptation is required at this stage.
- Preserved physical display validation for the later hardware-testing phase.
- Set Stage 3 OCP8178 backlight dry-port as the next project step.


### 2026-11-04 — Revision 0.6 / Stage 2 validation correction

- Recorded the first Stage 2 CI failure before compilation.
- Confirmed Raspberry Pi and AK-Rex source downloads succeeded.
- Confirmed the Makefile integration hunk applied.
- Isolated failure to the Kconfig integration hunk.
- Rewrote the Kconfig hunk to use the unique following EBBG panel config as a
  minimal stable anchor.
- Made patch validation strict with `--fuzz=0` and added failure diagnostics.
- Passed a synthetic application test against the relevant pinned 6.18.60
  Kconfig/Makefile context.
- Kept Stage 2 open pending the corrected ARM64 compile-validation run.

### 2026-11-04 — Revision 0.5 / Stage 2 candidate

- Pinned AK-Rex CWU50 source commit
  `0234e320bec7748fc6f1fb6904a055de10f0a727`.
- Chose the independently hardware-verified 6.12.94 unified driver rather than
  a moving/EOL 7.x source branch.
- Added immutable source lock for the GPL-2.0+ third-party driver.
- Added a narrow 6.18 Kconfig/Kbuild integration patch.
- Added reproducible ARM64 compile-validation script and GitHub Actions job.
- Reviewed Raspberry Pi 6.18 panel APIs; no speculative driver rewrite was
  introduced before compilation.
- Investigated but deferred merging CWU50 into the generic JD9365DA-H3 driver.
- Kept all repository paths relative/neutral and added no user-identifying
  information.


### 2026-11-04 — Revision 0.4 / Stage 1

- Marked Stage 0 complete after the initial repository checkpoint was committed
  and pushed.
- Pinned Raspberry Pi Linux `rpi-6.18.y` at
  `0b41724521c9adf5399409d02aece6c1df0a4432`.
- Recorded kernel version `6.18.60`.
- Added `kernel/BASELINE.md` with selection rationale and source policy.
- Added `kernel/source.lock` as the canonical machine-readable baseline input.
- Recorded independent source provenance and CI evidence.
- Set Stage 2 CWU50 dry-port as the next project step.
- Reaffirmed privacy policy: project files use only neutral/relative paths and
  contain no user-identifying information unless explicitly approved first.


### 2026-11-04 — Revision 0.3

- Added Arch-first / ARMtix-OpenRC-later multi-distro policy.
- Required shared kernel/hardware support to remain distro-neutral.
- Split image targets into `image/archlinuxarm/` and `image/armtix-openrc/`.
- Kept handoff filename permanently fixed.

### 2026-11-04 — Initial investigation

- Recorded hardware.
- Investigated `fabiiw05/uconsole-archlinux`.
- Traced kernel-support lineage.
- Selected Raspberry Pi Linux 6.18 LTS architecture.
- Defined minimal uConsole patch strategy.
- Defined staged implementation and validation plan.

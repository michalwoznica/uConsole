# Stage 9A — pin and authenticate Arch Linux ARM rootfs

**Status:** implemented; CI validation pending.

## Why Stage 9 is split

Stage 9 combines a large external root filesystem, package-database changes,
custom-kernel integration and image composition. To keep failures bounded,
Stage 9 is split into smaller checkpoints.

Stage 9A does only rootfs provenance and structural validation.

Stage 9B will integrate `linux-uconsole` into the authenticated rootfs tree.

## Selected rootfs

Target:

`ArchLinuxARM-2026.08-rpi-aarch64-rootfs.tar.gz`

This is the versioned Raspberry Pi AArch64 rootfs archive from Arch Linux ARM.

The project intentionally does **not** build from the moving
`ArchLinuxARM-rpi-aarch64-latest.tar.gz` alias.

The archive was published on 2026-08-05 and mirrored with an exact size of
850,215,189 bytes.

## Authenticity model

Arch Linux ARM publishes:

- the rootfs archive;
- an MD5 sidecar;
- a detached OpenPGP signature.

Arch Linux ARM states that release archives use the same build-system signing
key as packages:

`68B3537F39A313B3E574D06777193F152BDBE6A6`

Stage 9A verifies:

1. the versioned filename;
2. exact expected byte size;
3. the published MD5 sidecar;
4. the detached signature;
5. that the keyring used for verification contains the official full
   fingerprint.

The validator extracts the Arch Linux ARM public keyring from the downloaded
archive, then independently requires the exact official fingerprint before
using that keyring with `gpgv`. A modified archive cannot pass the detached
signature without the corresponding private signing key.

The validator also prints a SHA-256 digest for diagnostic/audit purposes.

## Mirror policy

The rootfs lock uses a versioned archive path.

Primary mirror:

`https://ca.us.mirror.archlinuxarm.org/os/rpi`

Fallback mirror:

`https://mirror.yandex.ru/archlinux-arm/os/rpi`

Because the filename is versioned and the content is signature-checked,
mirrors are transport sources rather than authorities.

## Structural audit

After authentication the validator extracts the rootfs and requires:

- pacman;
- systemd tooling;
- pacman configuration;
- Arch Linux ARM keyring;
- pacman local package database;
- boot directory.

It reads installed package names directly from pacman's local database without
executing target-AArch64 binaries.

The workflow prints the installed kernel/boot package subset so Stage 9B can
remove/replace the exact stock packages observed in this pinned rootfs rather
than guessing.

## Explicit non-goals

Stage 9A does not:

- build the uConsole kernel again;
- modify the rootfs;
- remove stock packages;
- run AArch64 binaries through QEMU;
- create partitions/filesystems;
- create an SD-card image;
- flash hardware.

## Completion criterion

Stage 9A is complete when `Validate pinned Arch Linux ARM rootfs` passes and
its stock kernel/boot package inventory is recorded in the handoff for Stage
9B.

## Signature-validator correction

The first Stage 9A CI run passed:

- versioned rootfs selection;
- archive download;
- exact expected byte size;
- published MD5;
- extraction of the Arch Linux ARM keyring.

It then failed at the project's fingerprint-presence parser before detached
signature verification.

The official signing fingerprint itself was not changed. Arch Linux ARM
documents the release/package signing key as:

`68B3537F39A313B3E574D06777193F152BDBE6A6`

The original validator relied on one exact textual layout from
`gpg --with-colons --fingerprint`. That was unnecessarily brittle.

The corrected validator now:

1. lists all fingerprints from the extracted keyring and compares field 10
   from `fpr` records exactly;
2. runs `gpgv --status-fd=1` on the detached rootfs signature;
3. requires the resulting `VALIDSIG` fingerprint to be exactly the official
   Arch Linux ARM build-system fingerprint.

The second condition is stronger than merely checking keyring membership: it
proves the downloaded archive was actually validated by the expected key.

No rootfs release, mirror, expected size, checksum, signing fingerprint, or
Stage 9A trust policy changed.

## Direct gpgv trust-path correction

The second Stage 9A CI run again reached the signing-key validation step and
then exited with code 2 while trying to inspect the extracted pacman keyring
through `gpg --keyring ... --list-keys`.

That pre-check was unnecessary.

The validator now uses one authoritative verification path:

1. pass the extracted `archlinuxarm.gpg` keyring directly to `gpgv`;
2. require `gpgv` to verify the detached rootfs signature successfully;
3. parse the machine-readable `VALIDSIG` status;
4. accept the signature only if the official Arch Linux ARM fingerprint is
   either:
   - the actual signing-key fingerprint; or
   - the primary-key fingerprint associated with that signing key.

GnuPG documents `VALIDSIG` as containing the signing fingerprint and, for
OpenPGP signatures, the corresponding primary-key fingerprint. This correctly
handles signatures produced by a signing subkey.

The separate keyring-membership inspection is removed. Successful `gpgv`
verification plus the exact `VALIDSIG` identity check already proves that the
keyring contained a usable key rooted at the expected Arch Linux ARM signing
identity.

No rootfs release, checksum, size, mirror, fingerprint, or trust decision
changed.

## Keyring-format correction

The third Stage 9A CI run reached the actual detached-signature verification.

`gpgv` reported:

- the signature timestamp correctly;
- the exact expected signing key
  `68B3537F39A313B3E574D06777193F152BDBE6A6`;
- `invalid packet (ctb=2d)`;
- `NO_PUBKEY` because it could not parse the supplied keyring.

The packet byte `0x2d` is ASCII `-`, consistent with an ASCII-armored
`-----BEGIN PGP PUBLIC KEY BLOCK-----` file being passed directly to
`gpgv --keyring`, which expects a binary OpenPGP keyring.

The validator is now format-aware:

1. extract `/usr/share/pacman/keyrings/archlinuxarm.gpg` from the authenticated
   archive candidate;
2. detect an ASCII-armored public-key block;
3. if armored, convert it with `gpg --dearmor` into a temporary binary
   keyring;
4. if already binary, copy it unchanged;
5. pass only the normalized binary keyring to `gpgv`;
6. continue to require `VALIDSIG` to identify the official Arch Linux ARM
   signing fingerprint as signer or primary key.

This changes only keyring representation handling. The rootfs release,
checksum, expected size, signature, signing fingerprint and trust policy are
unchanged.

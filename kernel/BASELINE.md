# Raspberry Pi Linux baseline

Stage 1 pins the exact upstream kernel source used by this project before any
uConsole-specific patch is introduced.

## Selected baseline

- Upstream repository: `https://github.com/raspberrypi/linux.git`
- Upstream branch family: `rpi-6.18.y`
- Exact commit: `0b41724521c9adf5399409d02aece6c1df0a4432`
- Kernel version at that commit: `6.18.60`
- Commit subject: `Merge remote-tracking branch 'stable/linux-6.18.y' into rpi-6.18.y`

## Why this commit

This commit is intentionally pinned instead of following the moving
`rpi-6.18.y` branch.

It is a clean stable-version boundary: the Raspberry Pi branch merges Linux
6.18.60 at this commit. That makes the starting point easier to audit than an
arbitrary later branch tip containing unrelated configuration changes.

The baseline is immutable for the current porting series. Future kernel
updates should be performed as explicit rebase/update stages rather than by
silently following the branch.

## Verification evidence recorded during Stage 1

- Raspberry Pi's device-tree overlay CI completed successfully for this merge.
- Linux 6.18.60 is a maintained 6.18 longterm point release.
- LibreELEC independently pinned the same Raspberry Pi commit for its
  Raspberry Pi Linux 6.18.60 package.

LibreELEC also recorded the GitHub source-archive SHA-256 at the time as:

`2222853d86d1e60b2c11c1f024ee42cdadb57d84362e961cbeaa609f01754f9a`

That archive checksum is recorded as corroborating provenance, not as the
project's primary source identity. The Git commit hash is canonical.

## Source policy

Do not replace this commit with `rpi-6.18.y`, `HEAD`, or another moving
reference in build scripts.

Any future baseline change must:

1. be a deliberate project stage;
2. document the old and new commits;
3. re-validate the uConsole patch series;
4. update the handoff and provenance records.

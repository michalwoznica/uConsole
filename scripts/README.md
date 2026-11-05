# Project scripts

Automation added here should support reproducible source verification, building, validation, packaging, or image creation.

Shared scripts should avoid distro- or init-system-specific assumptions where practical.

Scripts should fail clearly and must not hide important build inputs such as source commit hashes.

## Executable-bit policy

Shell scripts should be committed executable (`100755`) for normal local use.

Checkpoint ZIP handling can lose Unix mode bits in some extraction/repackaging
paths. CI workflows therefore invoke project shell validators explicitly with
`bash ./scripts/<name>.sh` rather than relying on the executable bit. This
prevents archive metadata loss from turning a valid source checkpoint into a
spurious CI `Permission denied` failure.

Stage 7 adds:

- `stage-arch-kernel-package.sh` — create a self-contained Arch makepkg
  workspace without duplicating authoritative project sources in Git;
- `validate-kernel-config-package.sh` — compose the full pinned source tree,
  execute the actual PKGBUILD `prepare()` path, resolve the uConsole kernel
  config, and stop before the Stage 8 full build.

Stage 8 adds:

- `validate-full-kernel-build.sh` — execute the real staged PKGBUILD
  `prepare()`, `build()` and `package()` paths, validate the built kernel
  image/modules/DTBs, apply the uConsole DTBO to the CM4 DTB, and inspect the
  temporary package root.

## CI timeout policy

Long-running kernel/image workflows should use the hosting platform's current
maximum job timeout unless a lower limit is specifically justified.

For GitHub Actions, verify the platform limit before changing workflow
timeouts. At Stage 8 completion, the maximum/default job timeout is 360
minutes, so full kernel/image jobs use `timeout-minutes: 360`.

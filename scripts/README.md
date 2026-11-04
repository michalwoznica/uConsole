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

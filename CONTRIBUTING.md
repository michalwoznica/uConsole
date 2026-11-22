# Contributing to uConsole

Thank you for considering a contribution.

This repository is a reproducible Linux image and kernel-support project for the ClockworkPi uConsole with Raspberry Pi CM4. Contributions should preserve the project's emphasis on narrow changes, explicit provenance, reproducibility, and clear separation between what has been tested and what remains unproven.

## Project scope

The current stable target is Arch Linux ARM on the ClockworkPi uConsole with Raspberry Pi CM4 Lite and the original/2024 display revision.

`main` is the stable/publication branch. Development that changes an accepted baseline, introduces a new distro target, or substantially changes hardware support should normally happen on a dedicated development branch and should not be treated as accepted until the relevant validation has passed.

Before making a substantial change, read:

- `README.md`
- `docs/PROVENANCE.md`
- `docs/UCONSOLE_ARCH_PROJECT_HANDOFF.md`
- `docs/STAGE12_UPDATE_REBUILD.md`
- `LICENSING.md`

## Bugs and security issues

For normal bugs, use the repository's **Bug report** issue form.

For security vulnerabilities, **do not open a public issue or pull request containing vulnerability details**. Follow `SECURITY.md` and use GitHub private vulnerability reporting when available.

## Before opening a pull request

Search existing issues and pull requests first.

For a small, self-contained fix, a pull request can be opened directly. For a large architectural change, new hardware target, new distro target, or change to the release/update model, opening an issue first is strongly recommended so the scope can be agreed before significant work is done.

## Development expectations

Keep contributions focused. Avoid unrelated cleanup or refactoring in the same change unless it is required for the contribution.

When a change affects build inputs, packaging, image construction, kernel sources, patches, or release state:

- preserve exact source provenance;
- prefer immutable source revisions over moving references;
- update checksums or lock data where the existing workflow requires them;
- do not silently replace an accepted baseline with newer upstream state;
- preserve the distinction between locked rebuilds and update candidates.

Do not commit generated disk images, package caches, build output, credentials, private keys, tokens, personal hostnames, SSIDs, or other environment-specific/private data.

## Validation

State exactly what you tested.

Documentation-only changes generally need review rather than a hardware test.

Build or packaging changes should include the relevant build/validation result.

Kernel, device-tree, driver, boot, power, networking, audio, display, battery, or other hardware-facing changes should identify the hardware used for testing. If physical validation was not performed, say so explicitly rather than presenting the change as proven.

A change may require maintainer-side physical validation before it can be promoted to the stable baseline.

## Documentation

Update documentation when a contribution changes user-visible behaviour, build/release procedure, accepted inputs, validation requirements, or the project's proven/unproven state.

Do not rewrite historical validation records merely to make them describe a newer state. Add or update the appropriate current-state documentation instead.

## Provenance and licensing

Original project material is licensed as described by `LICENSE` and `LICENSING.md`. Kernel code, imported patches, firmware, upstream snippets, and other third-party material may have different upstream licenses.

If a contribution adapts or imports third-party work:

- identify the upstream source;
- record the relevant commit/revision when practical;
- retain required copyright and license notices;
- ensure the contribution is compatible with the repository's licensing and provenance requirements.

Do not submit code or assets that you do not have the right to contribute.

## Pull requests

Use the pull request template and include:

- a concise description of the problem and change;
- the affected project area;
- validation performed;
- hardware validation status when relevant;
- provenance or lock-file changes when relevant;
- any known limitations or intentionally unproven behaviour.

A pull request should be reviewable as one coherent change.

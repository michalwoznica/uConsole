# Pinned third-party source inputs

Files in this directory pin immutable external source inputs that are required
by the uConsole kernel patch series but are not vendored into this repository.

Each lock records the upstream repository, exact commit, and source path/URL.
Build and validation tooling must use the exact pinned revision rather than a
moving branch name.

Current inputs:

- `cwu50.lock` — AK-Rex CWU50 DRM panel driver used by Stage 2.

- `ocp8178.lock` — immutable AK-Rex OCP8178 build input plus frozen metadata
  for the ClusterM brightness-map design reference.

- `uconsole-cm4-overlay.lock` — immutable AK-Rex/postmarketOS provenance plus
  OuinOuin74 design-reference metadata for Stage 4.

- `axp20x-battery.lock` — Stage 5 battery/fuel-gauge provenance.

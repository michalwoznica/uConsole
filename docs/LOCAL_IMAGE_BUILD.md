# Local Arch Linux ARM image build

The complete uConsole Arch Linux ARM image can be built locally with the same
host orchestration used by GitHub Actions.

The shared entry point is:

```bash
bash ./scripts/build-stage10-host.sh
```

## Arch Linux host prerequisites

The local path is designed for an Arch Linux host using Podman.

Install the required host tools once:

```bash
sudo pacman -S --needed \
  podman \
  dosfstools \
  e2fsprogs \
  rsync \
  util-linux \
  zstd
```

The build script uses **rootful Podman** (`sudo podman`) deliberately. Image
composition must preserve target numeric UID/GID ownership exactly; a rootless
container would place the build in a user namespace and remap those IDs.

For local Podman builds the container also uses host networking. This avoids
rootful Podman's bridge DNS path interfering with package retrieval while still
leaving GitHub Actions/Docker networking unchanged.

The source repository is mounted read-only into the disposable
`docker.io/library/archlinux:base-devel` container. The integrated ARM rootfs
and kernel package are emitted into an ignored `build/` workspace. The final
partitioned image is created on the host with loop devices and filesystem
tools through `sudo`.

## Build

From the repository root:

```bash
bash ./scripts/build-stage10-host.sh
```

Defaults:

- container runtime: `podman`;
- parallel jobs: all CPUs reported by `nproc`;
- work directory: `build/stage10-host/`;
- local kernel-package cache: `build/stage10-cache/`;
- final artifacts: `out/stage10/`.

The final compressed image is:

```text
out/stage10/uconsole-archlinuxarm-2026.08-cm4.img.zst
```

The same directory also contains the raw/compressed checksums, manifest and
exact `linux-uconsole` package used to compose the image.

## Kernel package cache

Kernel compilation is the expensive part of the image build. The local host
entry point hashes the kernel/package inputs and caches the resulting
`linux-uconsole` package under:

```text
build/stage10-cache/kernel-packages/<input-hash>/
```

If a later rootfs or image-composition step fails, rerunning the command reuses
that package as long as the kernel inputs have not changed. This allows rapid
iteration on image/userspace fixes without recompiling the kernel.

To force a kernel rebuild:

```bash
UCONSOLE_REBUILD_KERNEL=1 bash ./scripts/build-stage10-host.sh
```

## Optional overrides

The shared host entry point also supports:

```text
CONTAINER_RUNTIME
UCONSOLE_BUILD_DIR
UCONSOLE_ARTIFACT_DIR
UCONSOLE_CACHE_DIR
JOBS
UCONSOLE_REBUILD_KERNEL
```

GitHub Actions sets `CONTAINER_RUNTIME=docker` and runner-temporary paths, but
otherwise calls the same host entry point.

## Failure behavior

If the container/rootfs phase fails, the work directory is retained for
inspection. If the kernel package was completed before the failure, it is
copied into the input-keyed cache before the script exits.

A subsequent run therefore resumes with the cached kernel package while
rebuilding the authenticated rootfs and image-composition layers from source.

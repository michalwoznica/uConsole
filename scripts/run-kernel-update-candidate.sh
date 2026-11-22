#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidate_version="${1:-}"
candidate_commit="${2:-}"

if [[ -z "$candidate_version" || -z "$candidate_commit" ]]; then
    printf 'usage: %s VERSION COMMIT\n' "$0" >&2
    exit 2
fi
if [[ ! "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'ERROR: candidate kernel version must be numeric X.Y.Z: %s\n' \
        "$candidate_version" >&2
    exit 1
fi
if [[ ! "$candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'ERROR: candidate kernel commit must be a full 40-character lowercase SHA-1.\n' >&2
    exit 1
fi

container_runtime="${CONTAINER_RUNTIME:-podman}"
builder_image="${UCONSOLE_STAGE12E_BUILDER_IMAGE:-docker.io/library/archlinux:base-devel}"
candidate_id="kernel-${candidate_version}-${candidate_commit:0:12}"
candidate_root="$repo_root/build/update-candidate"
candidate_workdir="$candidate_root/$candidate_id"

case "$container_runtime" in
    podman)
        container_cmd=(sudo -n podman)
        image_exists_cmd=(sudo -n podman image exists "$builder_image")
        image_id_cmd=(sudo -n podman image inspect --format '{{.Id}}' "$builder_image")
        ;;
    docker)
        container_cmd=(docker)
        image_exists_cmd=(docker image inspect "$builder_image")
        image_id_cmd=(docker image inspect --format '{{.Id}}' "$builder_image")
        ;;
    *)
        printf 'ERROR: CONTAINER_RUNTIME must be podman or docker, got: %s\n' \
            "$container_runtime" >&2
        exit 1
        ;;
esac

for cmd in git sudo "$container_runtime"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'ERROR: required host command not found: %s\n' "$cmd" >&2
        exit 1
    fi
done

printf 'Authenticating sudo for Stage 12E candidate container...\n'
sudo -v

sudo_keepalive_pid=""
cleanup() {
    if [[ -d "$candidate_workdir" ]]; then
        sudo -n chown -R "$(id -u):$(id -g)" "$candidate_workdir" 2>/dev/null || true
    fi
    if [[ -n "$sudo_keepalive_pid" ]]; then
        kill "$sudo_keepalive_pid" 2>/dev/null || true
        wait "$sudo_keepalive_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
(
    while sleep 60; do
        sudo -n -v || exit 1
    done
) &
sudo_keepalive_pid=$!

if ! "${image_exists_cmd[@]}" >/dev/null 2>&1; then
    printf 'ERROR: Stage 12E requires the builder image to exist locally: %s\n' \
        "$builder_image" >&2
    printf 'Run the normal project builder/bootstrap path first; this validator will not silently pull a moving image tag.\n' >&2
    exit 1
fi
builder_image_id="$("${image_id_cmd[@]}")"

mkdir -p "$candidate_root"

git_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"

printf 'Stage 12E candidate: %s (%s)\n' "$candidate_version" "$candidate_commit"
printf 'Local builder image: %s\n' "$builder_image"
printf 'Local builder image ID: %s\n' "$builder_image_id"
printf 'Candidate workspace: %s\n' "$candidate_workdir"
printf 'Repository mount in container: read-only\n'
printf 'Container networking: enabled for candidate/toolchain fetches\n'

set +e
"${container_cmd[@]}" run --rm --pull=never \
    -e UCONSOLE_STAGE12E_CONTAINERIZED=yes \
    -e UCONSOLE_STAGE12E_BUILDER_IMAGE_ID="$builder_image_id" \
    -e UCONSOLE_UPDATE_CANDIDATE_DIR="/candidate-root/$candidate_id" \
    -v "$repo_root:/repo:ro" \
    -v "$candidate_root:/candidate-root" \
    "$builder_image" \
    bash -lc '
        set -euo pipefail
        pacman -Syu --noconfirm --needed \
            aarch64-linux-gnu-gcc \
            bc bison curl dtc flex git openssl pahole perl python rsync

        git config --global --add safe.directory /repo

        export UCONSOLE_STAGE12E_CROSS_GCC_VERSION="$(aarch64-linux-gnu-gcc --version | sed -n "1p")"
        export UCONSOLE_STAGE12E_CROSS_LD_VERSION="$(aarch64-linux-gnu-ld --version | sed -n "1p")"
        export UCONSOLE_STAGE12E_DTC_VERSION="$(dtc --version 2>&1 | sed -n "1p")"

        exec bash /repo/scripts/validate-kernel-update-candidate.sh "$1" "$2"
    ' _ "$candidate_version" "$candidate_commit"
container_status=$?
set -e

sudo -n chown -R "$(id -u):$(id -g)" "$candidate_workdir" 2>/dev/null || true

if [[ "$container_status" -ne 0 ]]; then
    printf 'ERROR: Stage 12E containerized candidate validation failed.\n' >&2
    printf 'Host workspace retained at: %s\n' "$candidate_workdir" >&2
    exit "$container_status"
fi

git_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
if [[ "$git_status_after" != "$git_status_before" ]]; then
    printf 'ERROR: Stage 12E changed tracked/unignored repository state on the host.\n' >&2
    printf '%s\n' '--- git status before ---' >&2
    printf '%s\n' "$git_status_before" >&2
    printf '%s\n' '--- git status after ---' >&2
    printf '%s\n' "$git_status_after" >&2
    exit 1
fi

printf 'PASS: host repository state unchanged after containerized Stage 12E validation.\n'

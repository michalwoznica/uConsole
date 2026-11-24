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
    printf 'ERROR: candidate kernel version must be numeric X.Y.Z: %s\n' "$candidate_version" >&2
    exit 1
fi
if [[ ! "$candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'ERROR: candidate kernel commit must be a full 40-character lowercase SHA-1.\n' >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$repo_root/image/archlinuxarm/release-baseline.lock"
# shellcheck disable=SC1091
source "$repo_root/kernel/source.lock"

candidate_release="${candidate_version}-1-uconsole"
candidate_pkgver="${candidate_version}-1"
candidate_id="kernel-${candidate_version}-${candidate_commit:0:12}"
candidate_root="$repo_root/build/update-candidate/$candidate_id"
stage12e_report="$candidate_root/candidate-report.txt"
workdir="$candidate_root/stage12f"
package_stage="$workdir/package-stage"
package_dir="$workdir/packages"
baseline_package_dir="$workdir/baseline-packages"
rootfs_dir="$workdir/rootfs"
final_inventory="$workdir/final-packages.txt"
metadata_file="$workdir/builder-metadata.txt"
artifact_dir="${UCONSOLE_STAGE12F_ARTIFACT_DIR:-$repo_root/out/update-candidate/$candidate_id}"
bundle_dir="${UCONSOLE_BASELINE_BUNDLE_DIR:-$repo_root/out/baselines/$BASELINE_ID}"
container_runtime="${CONTAINER_RUNTIME:-podman}"
builder_image="${UCONSOLE_STAGE12F_BUILDER_IMAGE:-docker.io/library/archlinux:base-devel}"
jobs="${JOBS:-$(nproc)}"

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'ERROR: JOBS must be a positive integer: %s\n' "$jobs" >&2
    exit 1
fi

case "$container_runtime" in
    podman)
        container_cmd=(sudo -n podman)
        image_exists_cmd=(sudo -n podman image exists "$builder_image")
        image_id_cmd=(sudo -n podman image inspect --format '{{.Id}}' "$builder_image")
        online_network=(--network=host)
        offline_network=(--network=none)
        ;;
    docker)
        container_cmd=(docker)
        image_exists_cmd=(docker image inspect "$builder_image")
        image_id_cmd=(docker image inspect --format '{{.Id}}' "$builder_image")
        online_network=()
        offline_network=(--network=none)
        ;;
    *)
        printf 'ERROR: CONTAINER_RUNTIME must be podman or docker, got: %s\n' "$container_runtime" >&2
        exit 1
        ;;
esac

required_commands=(
    sudo git sha256sum find sort awk grep sed nproc
    losetup blockdev sfdisk udevadm mkfs.vfat fsck.vfat mkfs.ext4 e2fsck
    mount umount mountpoint blkid rsync zstd
)
missing=()
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
command -v "$container_runtime" >/dev/null 2>&1 || missing+=("$container_runtime")
if (( ${#missing[@]} != 0 )); then
    printf 'ERROR: missing host commands: %s\n' "${missing[*]}" >&2
    exit 1
fi

if [[ "$candidate_version" == "$RPI_LINUX_VERSION" && "$candidate_commit" == "$RPI_LINUX_COMMIT" ]]; then
    printf 'ERROR: Stage 12F candidate is identical to the accepted kernel.\n' >&2
    exit 1
fi

printf 'Validating prerequisite Stage 12E report...\n'
if [[ ! -s "$stage12e_report" ]]; then
    printf 'ERROR: matching Stage 12E PASS report not found: %s\n' "$stage12e_report" >&2
    exit 1
fi
for expected in \
    "stage=12E" \
    "candidate_kernel_version=$candidate_version" \
    "candidate_kernel_commit=$candidate_commit" \
    "candidate_kernel_release=$candidate_release" \
    "kernel_prepare=pass" \
    "device_tree_build=pass" \
    "dt_overlay_application=pass" \
    "project_pins_changed=no" \
    "repository_mutated=no"
do
    if ! grep -Fxq "$expected" "$stage12e_report"; then
        printf 'ERROR: Stage 12E report does not contain required proof: %s\n' "$expected" >&2
        exit 1
    fi
done

printf 'Authenticating sudo for Stage 12F candidate build...\n'
sudo -v
sudo_keepalive_pid=""
cleanup() {
    if [[ -d "$workdir" || -d "$artifact_dir" ]]; then
        sudo -n chown -R "$(id -u):$(id -g)" "$workdir" "$artifact_dir" 2>/dev/null || true
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

printf 'Verifying accepted baseline bundle...\n'
bash "$repo_root/scripts/verify-release-baseline-bundle.sh" "$bundle_dir"

if ! "${image_exists_cmd[@]}" >/dev/null 2>&1; then
    printf 'ERROR: Stage 12F requires the builder image to exist locally: %s\n' "$builder_image" >&2
    exit 1
fi
builder_image_id="$("${image_id_cmd[@]}")"

git_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"

sudo -n rm -rf "$workdir" "$artifact_dir"
mkdir -p "$workdir" "$package_dir" "$baseline_package_dir" "$artifact_dir"
chmod 0755 "$workdir" "$package_dir" "$baseline_package_dir" "$artifact_dir"

printf 'Staging candidate-only PKGBUILD...\n'
bash "$repo_root/scripts/stage-kernel-package.sh" "$package_stage"
sed -i \
    -e "s/^pkgver=.*/pkgver=${candidate_version}/" \
    -e "s/^_commit=.*/_commit=${candidate_commit}/" \
    "$package_stage/PKGBUILD"
grep -Fxq "pkgver=${candidate_version}" "$package_stage/PKGBUILD"
grep -Fxq "_commit=${candidate_commit}" "$package_stage/PKGBUILD"

printf 'Building real Stage 12F candidate linux-uconsole package...\n'
set +e
"${container_cmd[@]}" run --rm --pull=never \
    "${online_network[@]}" \
    -e "JOBS=$jobs" \
    -v "$package_stage:/package-stage" \
    -v "$package_dir:/packages" \
    -v "$workdir:/candidate-work" \
    "$builder_image" \
    bash -lc '
        set -euo pipefail
        pacman -Syu --noconfirm --needed \
            aarch64-linux-gnu-gcc \
            bc bison curl dtc flex git gnupg inetutils kmod libarchive libcap libelf openssl pahole patch perl python rsync

        build_home=/candidate-work/build-home
        mkdir -p "$build_home"
        if ! id -u uconsole-build >/dev/null 2>&1; then
            useradd --no-create-home --home-dir "$build_home" --shell /bin/bash uconsole-build
        fi
        chown -R uconsole-build:uconsole-build /package-stage /packages "$build_home"

        {
            printf "builder_image_id=%s\\n" "$1"
            printf "cross_gcc_version=%s\\n" "$(aarch64-linux-gnu-gcc --version | sed -n "1p")"
            printf "cross_ld_version=%s\\n" "$(aarch64-linux-gnu-ld --version | sed -n "1p")"
            printf "dtc_version=%s\\n" "$(dtc --version 2>&1 | sed -n "1p")"
            printf "pacman_version=%s\\n" "$(pacman --version | sed -n "2p" | sed "s/^[[:space:]]*//")"
            printf "make_version=%s\\n" "$(make --version | sed -n "1p")"
        } > /candidate-work/builder-metadata.txt

        runuser -u uconsole-build -- \
            env \
                HOME="$build_home" \
                CARCH=aarch64 \
                ARCH=arm64 \
                CROSS_COMPILE=aarch64-linux-gnu- \
                MAKEFLAGS="-j${JOBS}" \
                PKGDEST=/packages \
                makepkg \
                    --ignorearch \
                    --nodeps \
                    --cleanbuild \
                    --force \
                    --noconfirm \
                    --nocheck \
                    --dir /package-stage
    ' _ "$builder_image_id"
package_build_status=$?
set -e
sudo -n chown -R "$(id -u):$(id -g)" "$workdir" 2>/dev/null || true
if [[ "$package_build_status" -ne 0 ]]; then
    printf 'ERROR: Stage 12F candidate kernel package build failed.\n' >&2
    printf 'Workspace retained at: %s\n' "$workdir" >&2
    exit "$package_build_status"
fi

mapfile -t candidate_packages < <(
    find "$package_dir" -maxdepth 1 -type f \
        -name 'linux-uconsole-*-aarch64.pkg.tar*' ! -name '*.sig' | sort
)
if [[ "${#candidate_packages[@]}" -ne 1 ]]; then
    printf 'ERROR: expected exactly one Stage 12F candidate package, got %s.\n' \
        "${#candidate_packages[@]}" >&2
    exit 1
fi
candidate_package="${candidate_packages[0]}"
candidate_package_sha256="$(sha256sum "$candidate_package" | awk '{print $1}')"

printf 'Reconstructing accepted userspace/rootfs offline...\n'
set +e
"${container_cmd[@]}" run --rm --pull=never \
    "${offline_network[@]}" \
    -e UCONSOLE_LOCKED_BASELINE_BUNDLE=/baseline \
    -v "$repo_root:/repo:ro" \
    -v "$bundle_dir:/baseline:ro" \
    -v "$workdir:/work" \
    "$builder_image" \
    bash -lc '
        set -euo pipefail
        bash /repo/scripts/build-archlinuxarm-rootfs.sh \
            /work/rootfs \
            /work/baseline-packages
    '
rootfs_status=$?
set -e
if [[ "$rootfs_status" -ne 0 ]]; then
    printf 'ERROR: Stage 12F accepted-baseline rootfs reconstruction failed.\n' >&2
    exit "$rootfs_status"
fi

printf 'Replacing only the accepted kernel with the Stage 12F candidate offline...\n'
set +e
"${container_cmd[@]}" run --rm --pull=never \
    "${offline_network[@]}" \
    -v "$repo_root:/repo:ro" \
    -v "$bundle_dir:/baseline:ro" \
    -v "$workdir:/candidate-work" \
    "$builder_image" \
    bash -lc '
        set -euo pipefail
        bash /repo/scripts/install-kernel-update-candidate.sh \
            /candidate-work/rootfs \
            "/candidate-work/packages/$3" \
            /baseline \
            "$1" \
            "$2" \
            /candidate-work/final-packages.txt
    ' _ "$candidate_version" "$candidate_commit" "$(basename "$candidate_package")"
install_status=$?
set -e
if [[ "$install_status" -ne 0 ]]; then
    printf 'ERROR: Stage 12F candidate kernel integration failed.\n' >&2
    exit "$install_status"
fi

printf 'Building and validating Stage 12F candidate microSD image...\n'
sudo -n env \
    UCONSOLE_IMAGE_KERNEL_RELEASE="$candidate_release" \
    UCONSOLE_IMAGE_RPI_LINUX_COMMIT="$candidate_commit" \
    UCONSOLE_IMAGE_CHECKPOINT=Stage12F \
    UCONSOLE_IMAGE_VARIANT="candidate-kernel-${candidate_version}-${candidate_commit:0:12}" \
    bash "$repo_root/scripts/build-archlinuxarm-image.sh" \
        "$rootfs_dir" \
        "$package_dir" \
        "$artifact_dir"

sudo -n chown -R "$(id -u):$(id -g)" "$workdir" "$artifact_dir"
cp -f "$final_inventory" "$artifact_dir/final-packages.txt"
cp -f "$metadata_file" "$artifact_dir/builder-metadata.txt"
cp -f "$package_stage/PKGBUILD" "$artifact_dir/candidate-PKGBUILD"
cp -f "$stage12e_report" "$artifact_dir/stage12e-candidate-report.txt"

image_stem="uconsole-archlinuxarm-${BASELINE_ROOTFS_RELEASE}-cm4-candidate-kernel-${candidate_version}-${candidate_commit:0:12}"
image_manifest="$artifact_dir/${image_stem}.manifest"
compressed_image="$artifact_dir/${image_stem}.img.zst"
if [[ ! -s "$image_manifest" || ! -s "$compressed_image" ]]; then
    printf 'ERROR: Stage 12F candidate image artifacts are incomplete.\n' >&2
    exit 1
fi

final_inventory_sha256="$(sha256sum "$artifact_dir/final-packages.txt" | awk '{print $1}')"
builder_metadata_sha256="$(sha256sum "$artifact_dir/builder-metadata.txt" | awk '{print $1}')"
candidate_pkgbuild_sha256="$(sha256sum "$artifact_dir/candidate-PKGBUILD" | awk '{print $1}')"
stage12e_report_sha256="$(sha256sum "$artifact_dir/stage12e-candidate-report.txt" | awk '{print $1}')"
compressed_sha256="$(sha256sum "$compressed_image" | awk '{print $1}')"
report="$artifact_dir/stage12f-candidate-report.txt"
cat > "$report" <<REPORT
stage=12F
candidate_class=kernel-update
baseline_id=$BASELINE_ID
baseline_bundle_lock_sha256=$BASELINE_BUNDLE_LOCK_SHA256
baseline_bundle_files_sha256=$BASELINE_BUNDLE_FILES_SHA256
pinned_kernel_version=$RPI_LINUX_VERSION
pinned_kernel_commit=$RPI_LINUX_COMMIT
candidate_kernel_version=$candidate_version
candidate_kernel_commit=$candidate_commit
candidate_kernel_release=$candidate_release
builder_image_id=$builder_image_id
candidate_package_filename=$(basename "$candidate_package")
candidate_package_sha256=$candidate_package_sha256
userspace_inventory=accepted-baseline-except-linux-uconsole
final_inventory_sha256=$final_inventory_sha256
builder_metadata_sha256=$builder_metadata_sha256
candidate_pkgbuild_sha256=$candidate_pkgbuild_sha256
stage12e_report_sha256=$stage12e_report_sha256
compressed_image_filename=$(basename "$compressed_image")
compressed_image_sha256=$compressed_sha256
project_pins_changed=no
repository_mutated=no
physical_validation=not_run
promotion=not_performed
REPORT

# Re-check repository state only after every candidate artifact has been written.
git_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
if [[ "$git_status_after" != "$git_status_before" ]]; then
    printf 'ERROR: Stage 12F changed tracked/unignored repository state.\n' >&2
    printf '%s\n' '--- git status before ---' >&2
    printf '%s\n' "$git_status_before" >&2
    printf '%s\n' '--- git status after ---' >&2
    printf '%s\n' "$git_status_after" >&2
    exit 1
fi

printf '\n=== STAGE 12F KERNEL UPDATE CANDIDATE BUILD ===\n'
cat "$report"
printf 'artifact_dir=%s\n' "$artifact_dir"
printf '=== END STAGE 12F KERNEL UPDATE CANDIDATE BUILD ===\n\n'
printf 'PASS: real candidate kernel package and candidate image built without moving accepted pins.\n'

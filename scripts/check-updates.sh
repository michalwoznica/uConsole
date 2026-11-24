#!/usr/bin/env bash
set -euo pipefail

trap 'rc=$?; printf "ERROR: update checker aborted unexpectedly at line %s (exit %s).\n" "$LINENO" "$rc" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_lock="$repo_root/image/archlinuxarm/release-baseline.lock"
rootfs_lock="$repo_root/image/archlinuxarm/rootfs.lock"
kernel_lock="$repo_root/kernel/source.lock"
pkgbuild="$repo_root/image/shared/packages/linux-uconsole/PKGBUILD"

for cmd in curl git awk grep sed sort tr; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$cmd" >&2
        exit 1
    fi
done

for required in "$baseline_lock" "$rootfs_lock" "$kernel_lock" "$pkgbuild"; do
    if [[ ! -f "$required" ]]; then
        printf 'ERROR: required project file missing: %s\n' "$required" >&2
        exit 1
    fi
done

# shellcheck disable=SC1090
source "$baseline_lock"
# shellcheck disable=SC1090
source "$rootfs_lock"

if [[ "${BASELINE_STATUS:-}" != "accepted" ]]; then
    printf 'ERROR: release baseline is not marked accepted.\n' >&2
    exit 1
fi

if [[ ! "${ROOTFS_FILENAME:-}" =~ ^ArchLinuxARM-([0-9]{4}\.[0-9]{2})-rpi-aarch64-rootfs\.tar\.gz$ ]]; then
    printf 'ERROR: cannot derive pinned rootfs release from ROOTFS_FILENAME=%s\n' \
        "${ROOTFS_FILENAME:-<unset>}" >&2
    exit 1
fi
pinned_rootfs_release="${BASH_REMATCH[1]}"

pinned_kernel_version="${BASELINE_KERNEL_RELEASE%%-*}"
pinned_kernel_commit="$BASELINE_RPI_LINUX_COMMIT"
kernel_repo='https://github.com/raspberrypi/linux.git'
kernel_branch='rpi-6.18.y'

local_consistency=pass

if [[ "$pinned_rootfs_release" != "$BASELINE_ROOTFS_RELEASE" ]]; then
    printf 'ERROR: rootfs.lock release (%s) does not match accepted baseline (%s).\n' \
        "$pinned_rootfs_release" "$BASELINE_ROOTFS_RELEASE" >&2
    local_consistency=fail
fi
if [[ "${ROOTFS_SHA256:-}" != "$BASELINE_ROOTFS_SHA256" ]]; then
    printf 'ERROR: rootfs.lock SHA-256 does not match accepted baseline.\n' >&2
    local_consistency=fail
fi
if ! grep -Fq "$pinned_kernel_commit" "$kernel_lock"; then
    printf 'ERROR: kernel/source.lock does not contain accepted kernel commit %s.\n' \
        "$pinned_kernel_commit" >&2
    local_consistency=fail
fi
if ! grep -Fq "$pinned_kernel_version" "$kernel_lock"; then
    printf 'ERROR: kernel/source.lock does not contain accepted kernel version %s.\n' \
        "$pinned_kernel_version" >&2
    local_consistency=fail
fi
if ! grep -Fq 'github.com/raspberrypi/linux' "$kernel_lock"; then
    printf 'ERROR: kernel/source.lock does not contain canonical Raspberry Pi repository.\n' >&2
    local_consistency=fail
fi
if ! grep -Fq "$kernel_branch" "$kernel_lock"; then
    printf 'ERROR: kernel/source.lock does not contain selected branch %s.\n' \
        "$kernel_branch" >&2
    local_consistency=fail
fi
if ! grep -Fq "$pinned_kernel_commit" "$pkgbuild"; then
    printf 'ERROR: linux-uconsole PKGBUILD does not contain accepted kernel commit.\n' >&2
    local_consistency=fail
fi

pkgver_line="$(grep -m1 -E '^[[:space:]]*pkgver=' "$pkgbuild" || true)"
pkgrel_line="$(grep -m1 -E '^[[:space:]]*pkgrel=' "$pkgbuild" || true)"
pkgver="$(printf '%s' "${pkgver_line#*=}" | tr -d '[:space:]\"\047')"
pkgrel="$(printf '%s' "${pkgrel_line#*=}" | tr -d '[:space:]\"\047')"
if [[ -z "$pkgver" || -z "$pkgrel" ]]; then
    printf 'ERROR: could not read pkgver/pkgrel from linux-uconsole PKGBUILD.\n' >&2
    local_consistency=fail
elif [[ "$pkgver" != "$pinned_kernel_version" || "${pkgver}-${pkgrel}-uconsole" != "$BASELINE_KERNEL_RELEASE" ]]; then
    printf 'ERROR: linux-uconsole PKGBUILD version metadata does not match accepted baseline.\n' >&2
    local_consistency=fail
fi

if [[ "$local_consistency" != pass ]]; then
    exit 1
fi

# Snapshot repository status so this checker can prove that it did not mutate it.
git_status_before=''
git_status_after=''
inside_git=no
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    inside_git=yes
    git_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
fi

curl_get() {
    curl --fail --location --silent --show-error \
        --connect-timeout 10 --max-time 30 "$1"
}

rootfs_query_status=unknown
rootfs_candidate_release=unknown
rootfs_candidate_source=none
rootfs_update_available=unknown
rootfs_listing=''
rootfs_listing_base=''

for base in "${ROOTFS_PRIMARY_BASE_URL:-}" "${ROOTFS_FALLBACK_BASE_URL:-}"; do
    [[ -n "$base" ]] || continue
    if rootfs_listing="$(curl_get "${base%/}/" 2>/dev/null)"; then
        rootfs_listing_base="${base%/}"
        break
    fi
done

if [[ -n "$rootfs_listing" ]]; then
    rootfs_candidate_release="$({
        printf '%s\n' "$rootfs_listing" |
            grep -Eo 'ArchLinuxARM-[0-9]{4}\.[0-9]{2}-rpi-aarch64-rootfs\.tar\.gz' || true
    } | sed -E 's/^ArchLinuxARM-([0-9]{4}\.[0-9]{2})-rpi-aarch64-rootfs\.tar\.gz$/\1/' |
        sort -Vu | tail -n 1)"

    if [[ -n "$rootfs_candidate_release" ]]; then
        rootfs_query_status=ok
        rootfs_candidate_source="$rootfs_listing_base/"
        if [[ "$rootfs_candidate_release" == "$pinned_rootfs_release" ]]; then
            rootfs_update_available=no
        elif [[ "$(printf '%s\n%s\n' "$pinned_rootfs_release" "$rootfs_candidate_release" | sort -V | tail -n 1)" == "$rootfs_candidate_release" ]]; then
            rootfs_update_available=yes
        else
            rootfs_update_available=no
        fi
    fi
fi

# Some mirrors disable directory listing. Fall back to comparing the moving
# latest alias with the pinned versioned sidecar without downloading either
# rootfs archive. A differing alias proves that a different rootfs candidate
# exists, even if its release label cannot be learned from the listing.
if [[ "$rootfs_query_status" != ok ]]; then
    for base in "${ROOTFS_PRIMARY_BASE_URL:-}" "${ROOTFS_FALLBACK_BASE_URL:-}"; do
        [[ -n "$base" ]] || continue
        latest_md5_url="${base%/}/ArchLinuxARM-rpi-aarch64-latest.tar.gz${ROOTFS_MD5_SUFFIX:-.md5}"
        pinned_md5_url="${base%/}/${ROOTFS_FILENAME}${ROOTFS_MD5_SUFFIX:-.md5}"
        latest_md5_text="$(curl_get "$latest_md5_url" 2>/dev/null || true)"
        pinned_md5_text="$(curl_get "$pinned_md5_url" 2>/dev/null || true)"
        latest_md5="$(printf '%s\n' "$latest_md5_text" | awk 'NF {print tolower($1); exit}')"
        pinned_md5="$(printf '%s\n' "$pinned_md5_text" | awk 'NF {print tolower($1); exit}')"
        if [[ "$latest_md5" =~ ^[0-9a-f]{32}$ && "$pinned_md5" =~ ^[0-9a-f]{32}$ ]]; then
            rootfs_query_status=ok
            rootfs_candidate_source="$latest_md5_url"
            if [[ "$latest_md5" == "$pinned_md5" ]]; then
                rootfs_candidate_release="$pinned_rootfs_release"
                rootfs_update_available=no
            else
                rootfs_candidate_release=unknown-different-latest-alias
                rootfs_update_available=yes
            fi
            break
        fi
    done
fi

kernel_query_status=unknown
kernel_candidate_commit=unknown
kernel_candidate_version=unknown
kernel_update_available=unknown

kernel_candidate_commit="$(
    git ls-remote --exit-code "$kernel_repo" "refs/heads/$kernel_branch" 2>/dev/null |
        awk 'NR == 1 {print $1}' || true
)"

if [[ "$kernel_candidate_commit" =~ ^[0-9a-f]{40}$ ]]; then
    kernel_makefile="$(curl_get "https://raw.githubusercontent.com/raspberrypi/linux/${kernel_candidate_commit}/Makefile" 2>/dev/null || true)"
    if [[ -n "$kernel_makefile" ]]; then
        # Parse the fetched Makefile directly. Avoid a printf|awk pipeline here:
        # with pipefail, awk exiting after its first match can SIGPIPE printf and
        # make the checker terminate under set -e even though parsing succeeded.
        kver="$(awk -F' = ' '/^VERSION = /{print $2; exit}' <<<"$kernel_makefile")"
        kpatch="$(awk -F' = ' '/^PATCHLEVEL = /{print $2; exit}' <<<"$kernel_makefile")"
        ksub="$(awk -F' = ' '/^SUBLEVEL = /{print $2; exit}' <<<"$kernel_makefile")"
        if [[ "$kver" =~ ^[0-9]+$ && "$kpatch" =~ ^[0-9]+$ && "$ksub" =~ ^[0-9]+$ ]]; then
            kernel_candidate_version="${kver}.${kpatch}.${ksub}"
            kernel_query_status=ok
            if [[ "$kernel_candidate_commit" == "$pinned_kernel_commit" ]]; then
                kernel_update_available=no
            else
                kernel_update_available=yes
            fi
        fi
    fi
fi

if [[ "$inside_git" == yes ]]; then
    git_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
    if [[ "$git_status_after" != "$git_status_before" ]]; then
        printf 'ERROR: repository state changed while running read-only update checker.\n' >&2
        exit 1
    fi
fi

printf '\n=== STAGE 12D UPDATE CHECK ===\n'
printf 'local_lock_consistency=%s\n' "$local_consistency"
printf 'pinned_rootfs_release=%s\n' "$pinned_rootfs_release"
printf 'rootfs_query_status=%s\n' "$rootfs_query_status"
printf 'rootfs_candidate_release=%s\n' "$rootfs_candidate_release"
printf 'rootfs_update_available=%s\n' "$rootfs_update_available"
printf 'rootfs_candidate_source=%s\n' "$rootfs_candidate_source"
printf 'pinned_kernel_version=%s\n' "$pinned_kernel_version"
printf 'pinned_kernel_commit=%s\n' "$pinned_kernel_commit"
printf 'kernel_branch=%s\n' "$kernel_branch"
printf 'kernel_query_status=%s\n' "$kernel_query_status"
printf 'kernel_candidate_version=%s\n' "$kernel_candidate_version"
printf 'kernel_candidate_commit=%s\n' "$kernel_candidate_commit"
printf 'kernel_update_available=%s\n' "$kernel_update_available"
printf 'repository_mutated=no\n'
printf '=== END STAGE 12D UPDATE CHECK ===\n\n'

if [[ "$rootfs_query_status" != ok || "$kernel_query_status" != ok ]]; then
    printf 'ERROR: one or more upstream update sources could not be queried reliably.\n' >&2
    exit 2
fi

if [[ "$rootfs_update_available" == yes || "$kernel_update_available" == yes ]]; then
    printf 'RESULT: upstream update candidate(s) available; no project pins were changed.\n'
else
    printf 'RESULT: no newer selected-line rootfs/kernel candidate detected; no project pins were changed.\n'
fi

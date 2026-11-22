#!/usr/bin/env bash

# Shared helpers for hashing and compressing completed raw image artifacts.
#
# The caller owns image naming, manifest content, retention/removal policy and
# any target-specific artifact metadata.

uconsole_compress_and_checksum_image() {
    local image="$1"
    local compressed="$2"
    local raw_sha_file="$3"
    local compressed_sha_file="$4"
    local raw_sha_var="$5"
    local compressed_sha_var="$6"
    local raw_sha
    local compressed_sha

    printf 'Recording raw image checksum...\n'
    raw_sha="$(sha256sum "$image" | awk '{print $1}')"
    printf '%s  %s\n' "$raw_sha" "$(basename "$image")" > "$raw_sha_file"

    printf 'Compressing image with zstd using all available CPUs...\n'
    zstd \
        -T0 \
        -10 \
        --force \
        "$image" \
        -o "$compressed"

    zstd -t "$compressed"

    compressed_sha="$(sha256sum "$compressed" | awk '{print $1}')"
    printf '%s  %s\n' \
        "$compressed_sha" "$(basename "$compressed")" \
        > "$compressed_sha_file"

    printf -v "$raw_sha_var" '%s' "$raw_sha"
    printf -v "$compressed_sha_var" '%s' "$compressed_sha"
}

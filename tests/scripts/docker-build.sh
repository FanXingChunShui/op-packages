#!/usr/bin/env bash
# docker-build.sh - Build the OpenWrt 25.12 SDK Docker image
#
# Three modes:
#   1. Default (no env vars set): native `docker build` (local dev)
#   2. USE_BUILDX=1:               use `docker buildx build` with optional
#                                 GitHub Actions cache (cache-from type=gha)
#   3. CI detected (GITHUB_ACTIONS=true): automatically use buildx + GHA cache
#
# Usage:
#   ./tests/scripts/docker-build.sh                 # local: native docker
#   USE_BUILDX=1 ./tests/scripts/docker-build.sh    # local: buildx
#   ./tests/scripts/docker-build.sh                 # CI:  buildx + gha cache
#
# Notes:
#   - GitHub Actions runners ship with Docker but the daemon is NOT started
#     by default. Use docker/setup-buildx-action to start it before invoking
#     this script in a workflow.
#   - `--load` is required to use the image in subsequent `docker run` steps
#     (otherwise buildx only pushes to a registry).

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not found. Install Docker Desktop or set OPENWRT_SDK." >&2
    exit 2
fi

# Auto-detect CI: prefer buildx when running under GitHub Actions.
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    USE_BUILDX=1
fi
USE_BUILDX="${USE_BUILDX:-0}"

cd "${REPO_ROOT}"

if [[ "${USE_BUILDX}" == "1" ]]; then
    # buildx mode — supports cache-from / cache-to for layer reuse.
    CACHE_FLAGS=()
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        # Only push to the GHA cache from the dedicated sdk-image job, not
        # from every consumer. The cache-to side does an implicit OCI image
        # push, which is the part GHA's cache backend understands.
        CACHE_FLAGS+=(--cache-from type=gha)
        if [[ "${GHA_POPULATE_CACHE:-0}" == "1" ]]; then
            CACHE_FLAGS+=(--cache-to type=gha,mode=max)
        fi
    fi

    docker buildx build \
        --tag op-packages-sdk:latest \
        --load \
        --file tests/Dockerfile.openwrt-sdk \
        "${CACHE_FLAGS[@]}" \
        .
else
    # Native docker (no BuildKit) — local dev.
    docker build \
        --tag op-packages-sdk:latest \
        --file tests/Dockerfile.openwrt-sdk \
        --progress=plain \
        .
fi

echo ""
echo "Image built: op-packages-sdk:latest"
echo "Run a build with:"
echo "  docker run --rm -v \"\$(pwd):/src\" op-packages-sdk ./tests/scripts/build-all.sh"

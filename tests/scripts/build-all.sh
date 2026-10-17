#!/usr/bin/env bash
# build-all.sh - Compile every package in net/ against an OpenWrt 25.12 SDK
#
# When run inside the Docker image the SDK is at /opt/openwrt-sdk.
# When run outside, the script expects OPENWRT_SDK env var to point to the
# SDK root (or $HOME/openwrt-sdk).
#
# Output: tests/artifacts/<pkg>-build.log per package + a summary table.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACTS="${REPO_ROOT}/tests/artifacts"
mkdir -p "${ARTIFACTS}"

# Locate SDK
SDK="${OPENWRT_SDK:-${OPWRT_SDK:-/opt/openwrt-sdk}}"
if [[ ! -d "${SDK}" ]]; then
    SDK="${HOME}/openwrt-sdk"
fi
if [[ ! -d "${SDK}" ]]; then
    echo "ERROR: OpenWrt SDK not found. Set OPENWRT_SDK env var." >&2
    echo "       Expected: /opt/openwrt-sdk (in Docker) or ~/openwrt-sdk" >&2
    exit 2
fi

# Symlink our feed into the SDK's package directory
echo "==> Symlinking op-packages into ${SDK}/package/op-packages"
ln -sfn "${REPO_ROOT}/net" "${SDK}/package/op-packages"

cd "${SDK}"

# Update feed index
echo "==> Updating package index"
./scripts/feeds update -i 2>&1 | tee "${ARTIFACTS}/feeds-update.log" | tail -5
./scripts/feeds install op-packages 2>/dev/null || true

# Packages to build (top-level VPN packages we expose)
PACKAGES=(
    libreswan
    openvpn-easy-rsa
    openvpn-openssl
    openvpn-mbedtls
    # openvpn-wolfssl omitted: @BROKEN upstream, ssl_openssl.c does not
    # build against wolfSSL's compat headers (see sdk-minimal.config).
    softethervpn-base
    softethervpn-server
    softethervpn-bridge
    softethervpn-client
    softethervpn5-base
    softethervpn5-server
    softethervpn5-bridge
    softethervpn5-client
    strongswan-default
)

FAILED=()
SUCCEEDED=()

# Our feed is symlinked as ${SDK}/package/op-packages -> ${REPO_ROOT}/net
# so the make target path is package/op-packages/<pkg>/compile
# (exactly one "op-packages" segment, matching the symlink name).
for pkg in "${PACKAGES[@]}"; do
    echo ""
    echo "==> Compiling ${pkg}"
    log="${ARTIFACTS}/${pkg}-build.log"

    # NOTE: `make ... | tee | tail` would return tail's exit status (always 0),
    # masking a build failure. PIPESTATUS[0] is make's real exit code.
    set +e
    make "package/op-packages/${pkg}/compile" V=s 2>&1 | tee "${log}" | tail -30
    rc="${PIPESTATUS[0]}"
    set -e

    if [[ "${rc}" -eq 0 ]]; then
        SUCCEEDED+=("${pkg}")
        echo "==> ${pkg}: OK"
    else
        FAILED+=("${pkg}")
        echo "==> ${pkg}: FAILED (make exit ${rc}) — see ${log}"
    fi
done

echo ""
echo "============================================================"
echo "Build summary"
echo "============================================================"
echo "Succeeded (${#SUCCEEDED[@]}):"
for p in "${SUCCEEDED[@]:-}"; do echo "  - ${p}"; done
echo "Failed (${#FAILED[@]}):"
for p in "${FAILED[@]:-}"; do echo "  - ${p}"; done

[[ ${#FAILED[@]} -eq 0 ]] || exit 1

#!/usr/bin/env bash
# verify-ipk.sh - DEPRECATED alias for verify-pkg.sh
#
# OpenWrt 25.12 ships packages as .apk in the apk-tools v3 "ADB" container
# format, which is neither gzip nor tar, so the old .ipk-only reader no longer
# describes what we produce. verify-pkg.sh detects the container by its magic
# bytes and handles both, so this wrapper just forwards.
#
# Usage: verify-ipk.sh <package-name-fragment> [more fragments...]

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "note: verify-ipk.sh is deprecated; delegating to verify-pkg.sh" >&2
exec "${REPO_ROOT}/tests/scripts/verify-pkg.sh" "$@"

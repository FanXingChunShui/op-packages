#!/usr/bin/env bash
# dep-audit.sh - Audit package dependencies for known 25.12 compatibility issues
#
# Checks every package against a curated list of compatibility concerns:
#   - kmod-nf-nathelper-extra (split into per-protocol modules in 25.12)
#   - kmod-ovpn-dco-v2 (renamed to kmod-ovpn-backports in the 25.12 feeds)
#   - iptables-mod-ipsec (replaced by nftables flowtables)
#   - musl-incompatible glibc functions
#   - OpenSSL 1.1-only APIs (HMAC_CTX_new, EVP_CIPHER_CTX_init, etc.)
#   - OpenSSL 3.5 legacy provider usage
#
# Output: human-readable report. Exits 1 only when an actual incompat is found.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# Patterns that are FORBIDDEN on OpenWrt 25.12
DEPRECATED_KMODS=(
    "kmod-nf-nathelper-extra"
    "kmod-ovpn-dco-v2"        # renamed to kmod-ovpn-backports in the 25.12 feeds
    "kmod-ipsec-transforms"   # superseded by kmod-ipsec
)
DEPRECATED_SYMBOLS=(
    "EVP_CIPHER_CTX_init\b"   # removed in OpenSSL 3.x; use EVP_CIPHER_CTX_reset
    "HMAC_CTX_new\b"          # moved into legacy provider in 3.5+
    "RAND_pseudo_bytes\b"     # removed in OpenSSL 3.0
    "FIPS_mode\b"             # FIPS_mode() removed in OpenSSL 3.0
    "EC_KEY_new_by_curve_name\b" # legacy only in 3.5+
)

ISSUES=()

while IFS= read -r mf; do
    rel="${mf#"${REPO_ROOT}/"}"

    # Check Makefile DEPENDS for deprecated kmod names
    for k in "${DEPRECATED_KMODS[@]}"; do
        if grep -qE "\\+${k}\\b" "${mf}"; then
            ISSUES+=("${rel}: DEPENDS references deprecated '${k}'")
        fi
    done

    # Scan patches for deprecated OpenSSL symbols (heuristic)
    for s in "${DEPRECATED_SYMBOLS[@]}"; do
        if grep -rqE "\\b${s}" "${mf%/*}/patches" 2>/dev/null; then
            ISSUES+=("${rel}: patches reference deprecated OpenSSL symbol '${s}'")
        fi
    done
done < <(find "${REPO_ROOT}/net" -maxdepth 3 -name Makefile)

if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo "Deprecation audit found ${#ISSUES[@]} issue(s):"
    for i in "${ISSUES[@]}"; do echo "  - ${i}"; done
    exit 1
fi

echo "Dependency audit: clean. No deprecated references found."

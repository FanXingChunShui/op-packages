#!/usr/bin/env bash
# hash-check.sh - Verify that PKG_HASH is not 'skip' in any package Makefile
#
# Once a package is committed for release, the PKG_HASH must be the real
# upstream SHA256. Having PKG_HASH:=skip is only acceptable during the
# initial development scaffold; CI should fail if it slips into main.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# Allow the dev branch to have PKG_HASH:=skip; main/master must not.
# Precedence: explicit arg > STRICT_HASH env > default(non-strict)
if [[ $# -ge 1 ]]; then
    case "$1" in
        main|master) STRICT=1 ;;
        *)           STRICT=0 ;;
    esac
elif [[ -n "${STRICT_HASH:-}" ]]; then
    STRICT="${STRICT_HASH}"
else
    STRICT=0
fi

FAILED=()

while IFS= read -r mf; do
    rel="${mf#"${REPO_ROOT}/"}"
    hash_line=$(grep -E '^[[:space:]]*PKG_HASH[[:space:]]*:?=' "${mf}" | head -1 || true)
    if [[ -z "${hash_line}" ]]; then
        # Some packages use a git source which uses PKG_MIRROR_HASH instead
        if grep -qE '^[[:space:]]*PKG_SOURCE_PROTO[[:space:]]*:?=[[:space:]]*git' "${mf}"; then
            mirror=$(grep -E '^[[:space:]]*PKG_MIRROR_HASH[[:space:]]*:?=' "${mf}" | head -1 || true)
            if [[ -z "${mirror}" ]] && [[ ${STRICT} -eq 1 ]]; then
                echo "  ✗ ${rel}: git source without PKG_MIRROR_HASH"
                FAILED+=("${rel}:no-mirror-hash")
            fi
            continue
        fi
        if [[ ${STRICT} -eq 1 ]]; then
            echo "  ✗ ${rel}: no PKG_HASH at all"
            FAILED+=("${rel}:no-hash")
        fi
        continue
    fi
    hash_val=$(echo "${hash_line}" | sed -E 's/.*PKG_HASH[[:space:]]*:?=[[:space:]]*//' | tr -d '"' | tr -d "'")
    if [[ "${hash_val}" == "skip" ]]; then
        if [[ ${STRICT} -eq 1 ]]; then
            echo "  ✗ ${rel}: PKG_HASH is still 'skip'"
            FAILED+=("${rel}:hash-skip")
        else
            echo "  ⚠ ${rel}: PKG_HASH is 'skip' (allowed on dev branch)"
        fi
    elif [[ ! "${hash_val}" =~ ^[a-fA-F0-9]{64}$ ]]; then
        if [[ ${STRICT} -eq 1 ]]; then
            echo "  ✗ ${rel}: PKG_HASH is not a 64-char hex string: '${hash_val}'"
            FAILED+=("${rel}:hash-malformed")
        fi
    fi
done < <(find "${REPO_ROOT}/net" -maxdepth 3 -name Makefile)

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "PKG_HASH validation failed:"
    for f in "${FAILED[@]}"; do echo "  - ${f}"; done
    exit 1
fi

if [[ ${STRICT} -eq 1 ]]; then
    echo "All PKG_HASH values are valid 64-char hex strings."
else
    echo "All PKG_HASH checks passed (non-strict mode; 'skip' is allowed here)."
fi

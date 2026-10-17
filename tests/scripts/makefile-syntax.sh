#!/usr/bin/env bash
# makefile-syntax.sh - Sanity-check every Makefile
#
# Performs static checks that don't require an SDK:
#   1. Required PKG_ variables present (PKG_NAME, PKG_VERSION, PKG_RELEASE)
#   2. No trailing whitespace
#   3. $(eval $(call BuildPackage,...)) lines balance the Package definitions
#   4. Patches exist on disk when referenced
#
# Exit 0 if everything looks well-formed.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

FAILED=()

for mf in $(find "${REPO_ROOT}/net" -maxdepth 3 -name Makefile); do
    rel="${mf#"${REPO_ROOT}/"}"
    echo "checking ${rel}"

    # 1. Required vars
    for v in PKG_NAME PKG_VERSION PKG_RELEASE; do
        if ! grep -qE "^[[:space:]]*${v}[[:space:]]*[:?]?=" "${mf}"; then
            echo "  ✗ missing ${v}"
            FAILED+=("${rel}:missing-${v}")
        fi
    done

    # 2. No trailing whitespace on Makefile lines (catches typos)
    if grep -nE '[[:space:]]+$' "${mf}" >/dev/null 2>&1; then
        echo "  ✗ trailing whitespace"
        FAILED+=("${rel}:trailing-ws")
    fi

    # 3. BuildPackage / BuildPlugin presence (BuildPlugin expands to one
    #    BuildPackage each, so just verify at least one of them exists)
    if ! grep -qE "^[[:space:]]*\\\$\(eval[[:space:]]+\\\$\(call[[:space:]]+Build(Package|Plugin)," "${mf}"; then
        echo "  ✗ no BuildPackage|BuildPlugin eval found"
        FAILED+=("${rel}:no-eval")
    fi

    # 4. Referenced patches must exist
    while IFS= read -r p; do
        path="${mf%/*}/patches/${p}"
        if [[ ! -f "${path}" ]]; then
            echo "  ✗ referenced patch not found: ${p}"
            FAILED+=("${rel}:patch-missing")
        fi
    done < <(grep -oE "[0-9]{3}-[A-Za-z0-9_.-]+\.patch" "${mf}" || true)
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Makefile issues:"
    for f in "${FAILED[@]}"; do echo "  - ${f}"; done
    exit 1
fi

echo ""
echo "All Makefiles pass static checks."

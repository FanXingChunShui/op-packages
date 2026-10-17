#!/usr/bin/env bash
# run-tests.sh - Entry point for all op-packages validation
#
# Usage:
#   ./tests/run-tests.sh docker          Build the SDK image (needs Docker)
#   ./tests/run-tests.sh build           Compile every package
#   ./tests/run-tests.sh shellcheck      Lint all init scripts
#   ./tests/run-tests.sh syntax          Syntax-check all Makefiles
#   ./tests/run-tests.sh deps            Audit every package's dependencies
#   ./tests/run-tests.sh inits           Semantic validation of init scripts
#   ./tests/run-tests.sh hash            Check PKG_HASH values
#   ./tests/run-tests.sh verify <pkg>    Verify a built .ipk (needs build first)
#   ./tests/run-tests.sh all             Run all static checks
#   ./tests/run-tests.sh all-static      Same as 'all'
#   ./tests/run-tests.sh ci              Run everything CI would run (static only)
#   ./tests/run-tests.sh upstream        Check upstream versions
#
# Exits non-zero on the first failure. Designed to be safe to run repeatedly.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/tests/scripts"

usage() {
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "${1:-0}"
}

[[ $# -ge 1 ]] || usage 1

# Default to non-strict (dev) mode for hash checks; CI sets STRICT=1
# automatically based on the ref name.
if [[ -n "${GITHUB_REF_NAME:-}" ]]; then
    case "${GITHUB_REF_NAME}" in
        main|master) export STRICT_HASH=1 ;;
        *)           export STRICT_HASH=0 ;;
    esac
fi
STRICT_HASH="${STRICT_HASH:-0}"

case "$1" in
    docker)
        "${SCRIPTS_DIR}/docker-build.sh"
        ;;
    build)
        "${SCRIPTS_DIR}/build-all.sh"
        ;;
    shellcheck)
        "${SCRIPTS_DIR}/shellcheck-all.sh"
        ;;
    syntax)
        "${SCRIPTS_DIR}/makefile-syntax.sh"
        ;;
    deps)
        "${SCRIPTS_DIR}/dep-audit.sh"
        ;;
    inits)
        "${SCRIPTS_DIR}/validate-inits.sh"
        ;;
    hash)
        "${SCRIPTS_DIR}/hash-check.sh"
        : "${STRICT_HASH:=0}"  # suppress unbound warning
        ;;
    verify)
        shift
        if [[ $# -lt 1 ]]; then
            echo "Usage: $0 verify <package-name-fragment>" >&2
            exit 1
        fi
        "${SCRIPTS_DIR}/verify-pkg.sh" "$@"
        ;;
    all|all-static|ci)
        "${SCRIPTS_DIR}/makefile-syntax.sh"
        "${SCRIPTS_DIR}/dep-audit.sh"
        "${SCRIPTS_DIR}/validate-inits.sh"
        "${SCRIPTS_DIR}/hash-check.sh"
        "${SCRIPTS_DIR}/shellcheck-all.sh"
        ;;
    upstream)
        "${SCRIPTS_DIR}/upstream-check.sh"
        ;;
    -h|--help|help)
        usage 0
        ;;
    *)
        echo "Unknown target: $1" >&2
        usage 1
        ;;
esac

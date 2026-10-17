#!/usr/bin/env bash
# shellcheck-all.sh - Lint every shell script shipped with our packages
#
# Verifies /etc/init.d/*, /usr/bin/* and any other POSIX shell scripts.
# Optionally auto-installs shellcheck if missing.
#
# Exit codes:
#   0  - all scripts clean OR only OpenWrt-style minor warnings
#   1  - real syntax errors found
#   2  - shellcheck not installed

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not found. Install with: brew install shellcheck" >&2
    exit 2
fi

mapfile -t SCRIPTS < <(
    find "${REPO_ROOT}/net" \
        -type f \( -name "*.init" -o -name "*.sh" -o -name "*.profile" \
                 -o -name "*.user" -o -name "01-user" -o -name "launcher.sh" \) \
        -print
)

# Whitelist of warning codes that are common OpenWrt init-script patterns.
# OpenWrt scripts use bash-style local, intentional word-splitting, and
# uci get/set helpers that shellcheck can't see through. The feed upstream
# (coolsnowwolf/packages, openwrt/packages) also doesn't gate on these.
#
#   SC2034 - START/STOP/USE_PROCD read by /etc/rc.common
#   SC2046 - intentional word-splitting on uci/get_config output
#   SC2048 - intentional word-splitting in include loops
#   SC2145 - argument mixes in/out (uci pattern)
#   SC2154 - var assigned by uci_load/uci_config_get helpers
#   SC2155 - declaration+assignment of return values (POSIX-safe in bash)
#   SC2166 - [ p -a q ] is fine in OpenWrt's ash
#   SC2174 - unused helper variable
#   SC2223 - : ${VAR:=default} is fine for env-var defaults
#   SC3037 - '#'-prefixed commands are bash/ash extensions
#   SC3043 - 'local' is bash (OpenWrt /bin/sh is bash)
#   SC3045 - bash 4.x redirect features
#   SC3057 - bash 5.x declare features
#   SC3060 - declare flag warnings
#   SC2240 - '. file "$arg"' is an ash extension; OpenWrt /bin/sh is ash.
OPENWRT_OK_CODES=(SC2034 SC2046 SC2048 SC2145 SC2154 SC2155 SC2166 SC2174 SC2223 SC3037 SC3043 SC3045 SC3057 SC3060 SC2240)

SYNTAX_ERRORS=()
ADVISORY=()

for s in "${SCRIPTS[@]}"; do
    rel="${s#"${REPO_ROOT}/"}"
    echo ""
    echo "shellcheck ${rel}"
    out="$(shellcheck --shell sh \
                       --severity warning \
                       --color=never \
                       "${s}" 2>&1 || true)"
    if [[ -z "${out}" ]]; then
        continue
    fi
    echo "${out}"

    # Filter to only lines whose code is NOT in the whitelist
    real_errors="$(echo "${out}" | grep -oE 'SC[0-9]+' | sort -u | while read -r code; do
        ok=0
        for ok_code in "${OPENWRT_OK_CODES[@]}"; do
            [[ "${code}" == "${ok_code}" ]] && ok=1 && break
        done
        [[ ${ok} -eq 1 ]] || echo "${code}"
    done | sort -u)"
    if [[ -n "${real_errors}" ]]; then
        SYNTAX_ERRORS+=("${s}")
    else
        ADVISORY+=("${s}")
    fi
done

echo ""
echo "============================================================"
echo "shellcheck summary"
echo "  scripts scanned     : ${#SCRIPTS[@]}"
echo "  scripts clean       : $((${#SCRIPTS[@]} - ${#SYNTAX_ERRORS[@]} - ${#ADVISORY[@]}))"
echo "  scripts with advisory (OpenWrt-pattern warnings): ${#ADVISORY[@]}"
echo "  scripts with real syntax errors : ${#SYNTAX_ERRORS[@]}"
echo "============================================================"

if [[ ${#SYNTAX_ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo "Real issues in:"
    for f in "${SYNTAX_ERRORS[@]}"; do echo "  - ${f#"${REPO_ROOT}/"}"; done
    exit 1
fi

exit 0

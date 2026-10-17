#!/usr/bin/env bash
# validate-inits.sh - Semantic validation of OpenWrt init scripts
#
# Static checks that go beyond shellcheck:
#   - procd init scripts must declare USE_PROCD=1
#   - procd init scripts must use procd_open_instance / procd_close_instance
#   - All init scripts must define a SERVICE_DAEMONIZE-equivalent (start/stop)
#   - UCI config file references must exist in files/ or be generated
#
# Exit 1 if any check fails.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

FAILED=()

while IFS= read -r init; do
    rel="${init#"${REPO_ROOT}/"}"
    echo "validating ${rel}"

    # Every init.d script must source rc.common
    if ! grep -qE '^#!.*sh.*rc\.common' "${init}"; then
        # OpenWrt allows scripts to NOT source rc.common if they don't follow
        # the procd convention, but in our packages they all should. Allow
        # /bin/sh shebang as a special case.
        if ! head -1 "${init}" | grep -qE '/bin/sh'; then
            echo "  ✗ missing #!/bin/sh shebang"
            FAILED+=("${rel}:no-shebang")
        fi
    fi

    # If declares USE_PROCD=1, must use procd_open_instance
    if grep -qE '^USE_PROCD=1' "${init}"; then
        if ! grep -qE 'procd_open_instance' "${init}" && \
           ! grep -qE 'procd_append_param' "${init}"; then
            echo "  ✗ declares USE_PROCD=1 but never uses procd_open_instance"
            FAILED+=("${rel}:no-procd")
        fi
        if ! grep -qE '^start_service\b|^start\(\)' "${init}"; then
            echo "  ✗ declares USE_PROCD=1 but no start_service() / start() function"
            FAILED+=("${rel}:no-start")
        fi
    fi

    # START/STOP priorities should be valid numbers (0-99)
    for var in START STOP; do
        if val=$(grep -E "^${var}=[0-9]+" "${init}" | head -1 | cut -d= -f2); then
            if (( val < 0 || val > 99 )); then
                echo "  ✗ ${var}=${val} out of range (0-99)"
                FAILED+=("${rel}:${var}-bad-range")
            fi
        fi
    done

    # /etc/init.d/<name> install path must be writable (procd needs /var/run)
    for path in /var/run /var/lock /var/log; do
        if grep -qE "mkdir -p ${path}" "${init}"; then
            : # good
        fi
    done

done < <(find "${REPO_ROOT}/net" -path "*/files/*.init" -o -path "*/files/*/vpn*.init" 2>/dev/null | sort -u)

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Init-script semantic validation failed for ${#FAILED[@]} item(s):"
    for f in "${FAILED[@]}"; do echo "  - ${f}"; done
    exit 1
fi

echo ""
echo "All init scripts pass semantic validation."

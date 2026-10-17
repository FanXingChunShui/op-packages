#!/usr/bin/env bash
# verify-pkg.sh - Functional verification of compiled OpenWrt package artifacts
#
# Usage: verify-pkg.sh [package-name-fragment ...]
#
#   With no argument every package found in the artifact directory is checked.
#   With one or more arguments only artifacts whose filename contains the
#   given fragment are checked.
#
#   ARTIFACT_DIR   override the search directory (default: tests/artifacts/apk,
#                  falling back to the legacy tests/artifacts/ipk)
#   APK_BIN        path to an apk-tools v3 `apk` binary. Required to inspect
#                  OpenWrt 25.12+ `.apk` (ADB) packages. Auto-detected from
#                  $SDK_DIR / $SDK_EXTRACTED / $GITHUB_WORKSPACE when possible.
#
# Two container formats are supported and detected by magic bytes:
#
#   ADB*           apk-tools v3 (OpenWrt 25.12+ default). A binary "ADB"
#                  container, *not* tar/gzip.
#   \x1f\x8b       gzip stream: the legacy opkg-era `.ipk`, i.e. a tar.gz
#                  holding ./debian-binary, ./control.tar.gz and ./data.tar.gz.
#                  Read it with GNU tar.
#
# How control metadata is read differs between the two, and getting this wrong
# is easy:
#
#   * `.PKGINFO` only exists in the v2/opkg tar format. apk-tools v3 has no
#     such file at all — `apk extract` on a v3 package writes *only* the
#     payload tree. The control data lives in the container's ADB `info`
#     object, which is what `apk adbdump` renders, and the file/conffile
#     manifests ship as payload files under /lib/apk/packages/.
#     (Reference: apk-tools src/extract_v3.c writes no .PKGINFO;
#      src/extract_v2.c is where that filename lives.)
#   * The .PKGINFO file is therefore read for the legacy .ipk path only.
#
# Checks performed on every artifact:
#   1. Container integrity (apk verify / gzip magic)
#   2. Metadata: package name matches the expected fragment, version present,
#      architecture sane
#   3. File list present and non-empty
#   4. conffiles declaration consistent with the shipped /etc payload
#   5. procd init scripts parse as POSIX shell
#   6. No payload escaping the standard OpenWrt install roots
#   7. UCI config files have a structurally valid `config` stanza
#
# Exit 0 = all checks pass, 1 = at least one failed, 2 = usage/environment error.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── locate the artifact directory ────────────────────────────────────────────
if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    DIST_DIR="${ARTIFACT_DIR}"
elif [[ -d "${REPO_ROOT}/tests/artifacts/apk" ]]; then
    DIST_DIR="${REPO_ROOT}/tests/artifacts/apk"
elif [[ -d "${REPO_ROOT}/tests/artifacts/ipk" ]]; then
    DIST_DIR="${REPO_ROOT}/tests/artifacts/ipk"   # legacy layout
else
    DIST_DIR="${REPO_ROOT}/tests/artifacts/apk"
fi

# ── locate an apk-tools v3 binary (only needed for ADB packages) ─────────────
find_apk_bin() {
    if [[ -n "${APK_BIN:-}" ]]; then
        printf '%s' "${APK_BIN}"
        return 0
    fi
    local candidate
    local -a roots=()
    [[ -n "${SDK_EXTRACTED:-}" ]] && roots+=("${SDK_EXTRACTED}")
    [[ -n "${SDK_DIR:-}" ]] && roots+=("${SDK_DIR}")
    [[ -n "${OPENWRT_SDK:-}" ]] && roots+=("${OPENWRT_SDK}")
    [[ -n "${GITHUB_WORKSPACE:-}" ]] && roots+=("${GITHUB_WORKSPACE}")
    roots+=("${REPO_ROOT}")
    for r in "${roots[@]}"; do
        [[ -d "${r}" ]] || continue
        candidate="$(find "${r}" -maxdepth 6 -type f -path '*/staging_dir/host/bin/apk' -print -quit 2>/dev/null || true)"
        if [[ -n "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    if command -v apk >/dev/null 2>&1; then
        command -v apk
        return 0
    fi
    return 1
}

APK=""
if APK_CANDIDATE="$(find_apk_bin)"; then
    APK="${APK_CANDIDATE}"
fi

# ── collect artifacts ────────────────────────────────────────────────────────
mapfile -t ALL_ARTS < <(find "${DIST_DIR}" -type f \( -name '*.apk' -o -name '*.ipk' \) 2>/dev/null | sort)

if [[ ! -d "${DIST_DIR}" ]]; then
    echo "ERROR: ${DIST_DIR} not found. Run the CI build job (or build-all.sh) first." >&2
    exit 2
fi

if [[ $# -gt 0 ]]; then
    ARTS=()
    for frag in "$@"; do
        found=0
        for a in "${ALL_ARTS[@]}"; do
            if [[ "$(basename "${a}")" == *"${frag}"* ]]; then
                ARTS+=("${a}")
                found=1
            fi
        done
        if [[ "${found}" -eq 0 ]]; then
            echo "No .apk/.ipk files matching '${frag}' found in ${DIST_DIR}" >&2
            exit 1
        fi
    done
else
    ARTS=("${ALL_ARTS[@]}")
fi

if [[ ${#ARTS[@]} -eq 0 ]]; then
    echo "No .apk/.ipk files found in ${DIST_DIR}" >&2
    exit 1
fi

# ── helpers ──────────────────────────────────────────────────────────────────
FAILED=()
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAILED+=("$*"); }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$*"; }

# Human-readable container kind from the magic bytes.
container_kind() {
    local f="$1" m
    m="$(head -c 3 "${f}")"
    if [[ "${m}" == ADB* ]]; then
        printf 'ADB (apk-tools v3)'
    elif [[ "${m:0:2}" == $'\x1f\x8b' ]]; then
        printf 'gzip+tar (legacy .ipk)'
    else
        printf 'unknown (magic %s)' "$(head -c 3 "${f}" | LC_ALL=C tr -c '[:print:]' '.' )"
    fi
}

echo "==> ${#ARTS[@]} artifact(s) in ${DIST_DIR}"
for a in "${ARTS[@]}"; do
    printf '    %-52s %8s bytes  %s\n' \
        "$(basename "${a}")" "$(wc -c <"${a}" | tr -d ' ')" \
        "$(container_kind "${a}")"
done
echo

WORK="$(mktemp -d)"
# Cleanup must never change the script's exit status, and must survive
# environments that refuse rm -rf (sandboxes, read-only CI runners).
trap 'rm -rf "${WORK}" >/dev/null 2>&1 || true' EXIT

# `set -e` is hostile inside loops that are *meant* to probe; every caller
# wraps probe commands with `|| true`.
probe() { "$@" 2>/dev/null || true; }

# Read a `.PKGINFO`-style key (legacy .ipk path; v3 has no such file).
pkginfo_field() {
    local file="$1" key="$2"
    sed -n "s/^${key}:[[:space:]]*//p" "${file}" 2>/dev/null | head -1
}

# Read the ADB `info` object of a v3 .apk and print three tab-separated
# fields: name, version, arch. `apk adbdump` is the only supported reader —
# the package carries no `.PKGINFO` file to grep.
adb_info() {
    local apk="$1" file="$2" out=""

    if out="$("${apk}" adbdump --format json "${file}" 2>/dev/null)" && [[ -n "${out}" ]]; then
        if printf '%s' "${out}" | python3 -c '
import json, sys
info = json.load(sys.stdin).get("info", {})
print("\t".join(str(info.get(k, "")) for k in ("name", "version", "arch")))
' 2>/dev/null; then
            return 0
        fi
    fi

    # Fallback: the default YAML rendering (older builds, or no python3).
    # `adbdump` puts the info fields two spaces deep under `info:`.
    out="$("${apk}" adbdump "${file}" 2>/dev/null)" || out=""
    [[ -n "${out}" ]] || return 1
    local k
    for k in name version arch; do
        printf '%s' "${out}" | sed -n "s/^  ${k}:[[:space:]]*//p" | head -1
    done | paste -sd '\t' -
}

# Validate the shape of an OpenWrt UCI config file without needing uci itself.
#
# A real config looks like this (tabs are the usual indent, and the file may
# carry a `package <name>` declaration before the first section):
#
#     package openvpn
#
#     config openvpn sample_server
#     	option enabled 0
#     	list remote "host 1194"
#
# Both section-name spellings occur in the wild: `config dropbear main`
# (what OpenWrt itself ships) and `config dropbear 'main'`.
#
# Only these line kinds are legal: a leading `package <name>`, `config <type>
# [name]`, `option <key> <value>`, `list <key> <value>`, comments, and blank
# lines. Anything else means the file is not a UCI config.
uci_shape_ok() {
    local f="$1"
    # Must contain at least one `config` section ...
    grep -qE '^[[:space:]]*config[[:space:]]+[a-zA-Z0-9_-]+' "${f}" 2>/dev/null || return 1
    # ... and every non-comment, non-blank line must be a UCI statement.
    if grep -nE -v \
        "^[[:space:]]*(#|[[:space:]]*$|package[[:space:]]|config[[:space:]]|option[[:space:]]|list[[:space:]])" \
        "${f}" | grep -q .; then
        return 1
    fi
    # A `config` line must be `config <type>` plus an optional section name,
    # quoted or not, and nothing else.
    if grep -nE '^[[:space:]]*config([[:space:]]|$)' "${f}" \
        | grep -vE ':[[:space:]]*config[[:space:]]+[a-zA-Z0-9_-]+([[:space:]]+(\x27[^\x27]*\x27|[^\x27[:space:]]+))?[[:space:]]*$' \
        | grep -q .; then
        return 1
    fi
    return 0
}

# Shared checks that operate on a *materialised* payload tree ($1 = root dir,
# $2 = name, $3 = expected fragment, $4 = file-list file, $5 = conffiles file)
verify_payload_tree() {
    local root="$1" name="$2" frag="$3" listfile="$4" conffile="$5"

    # --- 3. file list ---
    #
    # A metapackage legitimately ships no payload at all: strongswan's
    # -default/-full/-isakmp/-minimal variants exist purely to pull in a
    # dependency set and their install sections are literally `true`
    # (net/strongswan/Makefile:501-515). OpenWrt still emits a normal,
    # empty .apk for them, so an empty file list is correct there.
    #
    # Decide on the *actual* unpacked content rather than on the manifest,
    # so a package that was supposed to ship files but lost them still
    # fails. Only an artifact that is empty both in its manifest and on
    # disk is treated as a metapackage.
    local nfiles=0 npayload=0
    [[ -f "${listfile}" ]] && nfiles="$(grep -c . "${listfile}" 2>/dev/null || true)"
    # Count real files outside the /lib/apk/packages/ bookkeeping directory.
    # Directory entries are ignored (-type f): an empty metapackage still has
    # the lib/, lib/apk/ and lib/apk/packages/ directories, and those must not
    # be mistaken for payload.
    npayload="$(find "${root}" -mindepth 1 -type f -not -path '*/lib/apk/packages/*' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${nfiles}" -gt 0 ]]; then
        ok "file list: ${nfiles} entries ($(du -sh "${root}" 2>/dev/null | cut -f1) unpacked)"
    elif [[ "${npayload}" -eq 0 ]]; then
        ok "metapackage: no payload (dependency-only), ${nfiles} manifest entries"
    else
        bad "${name}: empty file list but ${npayload} payload path(s) unpacked"
    fi

    # --- 4. conffiles ---
    local nconf=0
    [[ -f "${conffile}" ]] && nconf="$(grep -c . "${conffile}" 2>/dev/null || true)"
    if [[ "${nconf}" -gt 0 ]]; then
        local missing=0 f
        while read -r f; do
            f="${f%%[[:space:]]*}"        # a .conffiles_static line is "<path> <sha256>"
            [[ -n "${f}" ]] || continue
            [[ -e "${root}${f}" ]] || missing=$((missing + 1))
        done <"${conffile}"
        if [[ "${missing}" -gt 0 ]]; then
            bad "${name}: ${missing} conffile(s) declared but not shipped"
        else
            ok "conffiles: ${nconf} declared and present"
        fi
    fi

    # --- 5. init scripts parse ---
    # `find` yields absolute paths here (${root} is absolute), so they are used
    # as-is; prefixing ${root} again would produce an unresolvable path.
    local -a inits=()
    while IFS= read -r f; do
        [[ -n "${f}" ]] && inits+=("${f}")
    done < <(find "${root}/etc/init.d" -maxdepth 1 -type f \
        ! -name '.*' 2>/dev/null | sort)

    if [[ ${#inits[@]} -gt 0 ]]; then
        local ifail=0 f
        for f in "${inits[@]}"; do
            if ! sh -n "${f}" 2>/dev/null; then
                bad "${name}: init script syntax error: ${f#${root}}"
                ifail=$((ifail + 1))
            fi
        done
        [[ "${ifail}" -eq 0 ]] && ok "init scripts: ${#inits[@]} parse as shell"
    fi

    # --- 6. payload stays inside the standard install roots ---
    local escaped
    escaped="$(find "${root}" -mindepth 1 -maxdepth 1 \
        ! -name etc ! -name usr ! -name lib ! -name var ! -name bin ! -name sbin 2>/dev/null || true)"
    if [[ -n "${escaped}" ]]; then
        bad "${name}: payload outside /etc /usr /lib /var /bin /sbin: ${escaped//$'\n'/ }"
    else
        ok "payload rooted in /etc /usr /lib /var /bin /sbin only"
    fi

    # --- 7. UCI shapes ---
    local -a ucis=()
    while IFS= read -r f; do
        [[ -n "${f}" ]] && ucis+=("${f}")
    done < <(find "${root}/etc/config" -maxdepth 1 -type f \
        ! -name '.*' 2>/dev/null | sort)

    if [[ ${#ucis[@]} -gt 0 ]]; then
        local ufail=0 f
        for f in "${ucis[@]}"; do
            if ! uci_shape_ok "${f}"; then
                bad "${name}: malformed UCI config ${f#${root}}"
                ufail=$((ufail + 1))
            fi
        done
        [[ "${ufail}" -eq 0 ]] && ok "UCI configs: ${#ucis[@]} structurally valid"
    fi
}

verify_common_metadata() {
    local name="$1" frag="$2" pkgname="$3" pkgver="$4" arch="$5"

    if [[ -z "${pkgname}" ]]; then
        bad "${name}: package metadata has no name"
        return
    fi
    if [[ -n "${frag}" && "${pkgname}" != *"${frag}"* ]]; then
        bad "${name}: package name '${pkgname}' does not contain expected fragment '${frag}'"
    else
        ok "name    = ${pkgname}"
    fi
    if [[ -z "${pkgver}" ]]; then
        bad "${name}: package metadata has no version"
    else
        ok "version = ${pkgver}"
    fi
    case "${arch}" in
        x86_64|aarch64|arm|mips*|riscv64|i386|"") : ;;
        *) warn "unexpected arch '${arch}' (expected a target arch)" ;;
    esac
    if [[ -n "${arch}" ]]; then
        ok "arch    = ${arch}"
    fi
}

# Resolve the apk manifest basename for a package inside an extracted v3 tree.
# Normally it is simply <pkgname>; the fallback covers a name that carries an
# ABI-version suffix we did not predict.
apk_manifest_name() {
    local ex="$1" pkgname="$2" want="$3"
    if [[ -e "${ex}/lib/apk/packages/${pkgname}.${want}" ]]; then
        printf '%s' "${pkgname}"
        return 0
    fi
    # ABI-versioned libraries get a numeric suffix appended to the package
    # name, so the manifest is e.g. `libnl-cli200.list` for package
    # `libnl-cli`. include/feeds.mk:70 (FormatABISuffix) appends the ABI
    # version when the name does not already end in a digit.
    #
    # Match on the prefix only, rather than falling back to "any single
    # .list in the directory": with several manifests present, a blind
    # pick would silently validate the wrong package's file list and hide
    # a real mismatch.
    local f
    while IFS= read -r f; do
        [[ -n "${f}" ]] || continue
        basename "${f}" ".${want}"
        return 0
    done < <(find "${ex}/lib/apk/packages" -maxdepth 1 -name "${pkgname}[0-9]*.${want}" 2>/dev/null | sort)
    return 1
}

# ── main loop ────────────────────────────────────────────────────────────────
for art in "${ARTS[@]}"; do
    name="$(basename "${art}")"
    base="${name%.apk}"; base="${base%.ipk}"

    # Expected fragment: what the caller asked for, else derived from filename.
    frag=""
    for want in "$@"; do
        [[ "${name}" == *"${want}"* ]] && { frag="${want}"; break; }
    done
    if [[ -z "${frag}" ]]; then
        # Filenames are <pkgname>-<version>-r<release>.apk, e.g.
        #   openvpn-easy-rsa-3.2.0-r1   -> openvpn-easy-rsa
        #   softethervpn5-libs-5.2.5188-r2 -> softethervpn5-libs
        # Strip the -r<release> suffix first, then the -<version> part.
        frag="${base%-r[0-9]*}"
        frag="${frag%-*}"
    fi

    echo "────────────────────────────────────────────────────────────"
    echo "Verifying ${name}"
    echo "────────────────────────────────────────────────────────────"

    magic3="$(head -c 3 "${art}" | LC_ALL=C tr -d '\000')"

    if [[ "${magic3}" == ADB* ]]; then
        # ─────────── apk-tools v3 / ADB container ───────────
        if [[ -z "${APK}" || ! -x "${APK}" ]]; then
            bad "${name}: ADB package but no apk-tools v3 'apk' binary available"
            warn "  set APK_BIN=/path/to/staging_dir/host/bin/apk and re-run"
            continue
        fi

        av="$(mktemp "${WORK}/av.XXXXXX")"
        if ! "${APK}" verify --allow-untrusted "${art}" >"${av}" 2>&1; then
            bad "${name}: apk verify failed"
            sed 's/^/      /' "${av}" | head -20
            continue
        fi
        ok "apk verify (ADB container integrity)"

        # Control metadata lives in the ADB container, not in a .PKGINFO file.
        info="$(adb_info "${APK}" "${art}" || true)"
        if [[ -z "${info}" ]]; then
            bad "${name}: could not read ADB package info (apk adbdump)"
            continue
        fi
        IFS=$'\t' read -r pkgname pkgver arch <<<"${info}"
        ok "apk adbdump (ADB package info)"
        verify_common_metadata "${name}" "${frag}" "${pkgname}" "${pkgver}" "${arch}"

        ex="${WORK}/${base}.x"
        mkdir -p "${ex}"
        if ! probe "${APK}" extract --allow-untrusted --destination "${ex}" "${art}"; then
            bad "${name}: apk extract failed"
            continue
        fi

        # The manifest basename may carry an ABI-version suffix.
        manifest="$(apk_manifest_name "${ex}" "${pkgname}" list || true)"
        if [[ -z "${manifest}" ]]; then
            bad "${name}: extracted payload has no /lib/apk/packages/*.list manifest"
            continue
        fi

        # `.conffiles_static` lists only the conffiles actually shipped (with
        # their checksums); `.conffiles` may also name files that only appear
        # at runtime (e.g. generated host keys). Prefer the former when present
        # so that "declared but not shipped" stays a real signal.
        conf="${ex}/lib/apk/packages/${manifest}.conffiles_static"
        [[ -f "${conf}" ]] || conf="${ex}/lib/apk/packages/${manifest}.conffiles"

        verify_payload_tree "${ex}" "${name}" "${frag}" \
            "${ex}/lib/apk/packages/${manifest}.list" "${conf}"

    elif [[ "${magic3:0:2}" == $'\x1f\x8b' ]]; then
        # ─────────── legacy gzip+tar (.ipk) container ───────────
        if ! probe tar -tzf "${art}"; then
            bad "${name}: not a valid gzip+tar archive"
            continue
        fi
        ok "gzip+tar container integrity"

        ex="${WORK}/${base}.x"
        mkdir -p "${ex}"
        tar -xzf "${art}" -C "${ex}"
        if [[ ! -f "${ex}/control.tar.gz" || ! -f "${ex}/data.tar.gz" ]]; then
            bad "${name}: missing control.tar.gz / data.tar.gz"
            continue
        fi
        ok "control.tar.gz + data.tar.gz present"

        mkdir -p "${ex}/control" "${ex}/data"
        tar -xzf "${ex}/control.tar.gz" -C "${ex}/control"
        tar -xzf "${ex}/data.tar.gz"   -C "${ex}/data"

        # This is the one container format that really does carry .PKGINFO
        # semantics; materialise it from the opkg control file and reuse the
        # shared metadata check.
        ctl="${ex}/control/control"
        verify_common_metadata "${name}" "${frag}" \
            "$(probe awk '/^Package:/{print $2; exit}'      "${ctl}")" \
            "$(probe awk '/^Version:/{print $2; exit}'      "${ctl}")" \
            "$(probe awk '/^Architecture:/{print $2; exit}' "${ctl}")"

        verify_payload_tree "${ex}/data" "${name}" "${frag}" \
            "/dev/null" "${ex}/control/conffiles"

    else
        bad "${name}: unrecognised container (magic '${magic3}')"
    fi

    echo
done

echo "════════════════════════════════════════════════════"
if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf 'FAILED: %d issue(s)\n' "${#FAILED[@]}"
    for f in "${FAILED[@]}"; do printf '  - %s\n' "${f}"; done
    exit 1
fi
printf 'OK: all %d package artifact(s) passed functional verification.\n' "${#ARTS[@]}"

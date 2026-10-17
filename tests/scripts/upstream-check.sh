#!/usr/bin/env bash
# upstream-check.sh - Print upstream latest versions for our packages
#
# Used by the weekly GitHub Actions cron to detect when our packages are
# lagging behind upstream. Output is informational; never fails the build.

set -uo pipefail

echo "==> Checking upstream versions"
echo "    OpenWrt latest: $(curl -fsS 'https://downloads.openwrt.org/' 2>/dev/null | grep -oE 'releases/[0-9.]+' | sort -u | tail -1 || echo 'unknown')"
echo ""

# libreswan - GitHub releases
echo "libreswan  latest: $(curl -fsS 'https://api.github.com/repos/libreswan/libreswan/releases/latest' 2>/dev/null | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"

# strongswan - download.strongswan.org page scrape
echo "strongswan latest: $(curl -fsS 'https://www.strongswan.org/download.html' 2>/dev/null | grep -oE 'strongswan-[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/strongswan-//')"

# openvpn - GitHub releases
echo "openvpn    latest: $(curl -fsS 'https://api.github.com/repos/OpenVPN/openvpn/releases/latest' 2>/dev/null | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"

# easy-rsa - GitHub releases
echo "easy-rsa   latest: $(curl -fsS 'https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest' 2>/dev/null | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"

# SoftEtherVPN - GitHub releases
echo "softethervpn  latest: $(curl -fsS 'https://api.github.com/repos/SoftEtherVPN/SoftEtherVPN_Stable/releases/latest' 2>/dev/null | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"
echo "softethervpn5 latest: $(curl -fsS 'https://api.github.com/repos/SoftEtherVPN/SoftEtherVPN/releases/latest' 2>/dev/null | grep -oE '"tag_name":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"

echo ""
echo "Compare against versions declared in net/*/Makefile (PKG_VERSION)."

#!/bin/bash
# SSH allowlist by country using ipinfo (IPv4 and IPv6).
# Requires: ipinfo CLI (installed by altahost-start.sh)
# ALLOW_COUNTRIES is overwritten at install time from SSH_ALLOW_COUNTRIES.

ALLOW_COUNTRIES="AR"

if [ $# -ne 1 ]; then
  echo "Usage:  $(basename "$0") <ip>" 1>&2
  exit 0
fi

IP="$1"

# Normalize IPv4-mapped IPv6 (::ffff:1.2.3.4) to plain IPv4
if [[ "$IP" == *":"* ]]; then
  if [[ "$IP" =~ ::ffff:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    IP="${BASH_REMATCH[1]}"
  fi
fi

COUNTRY=""
if command -v ipinfo >/dev/null 2>&1; then
  COUNTRY=$(ipinfo "$IP" 2>/dev/null | grep -i "country code" | awk -F: '{print $2}' | tr -d ' \r\n' | head -c 2)
  [ -z "$COUNTRY" ] && COUNTRY=$(ipinfo "$IP" 2>/dev/null | grep -i "country" | head -1 | awk -F: '{print $2}' | tr -d ' \r\n' | head -c 2)
fi

if [[ -z "$COUNTRY" ]]; then
  logger "DENY sshd connection from $1 (no country from ipinfo)"
  exit 1
fi

if [[ "$ALLOW_COUNTRIES" =~ $COUNTRY ]]; then
  exit 0
else
  logger "DENY sshd connection from $1 (country: $COUNTRY)"
  exit 1
fi

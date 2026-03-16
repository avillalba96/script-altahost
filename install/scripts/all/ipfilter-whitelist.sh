#!/bin/bash
# Whitelist SSH por país. Usa ipinfo (soporta IPv4 e IPv6).
# Requiere: ipinfo CLI instalado por altahost-start.sh

ALLOW_COUNTRIES="AR"

if [ $# -ne 1 ]; then
  echo "Usage:  $(basename "$0") <ip>" 1>&2
  exit 0
fi

IP="$1"

# Normalizar: si es IPv6 con notación IPv4-mapeada (::ffff:1.2.3.4), extraer IPv4
if [[ "$IP" == *":"* ]]; then
  if [[ "$IP" =~ ::ffff:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    IP="${BASH_REMATCH[1]}"
  fi
  # Si sigue siendo IPv6 puro, ipinfo lo soporta directamente
fi

# Obtener código de país con ipinfo (funciona con IPv4 e IPv6)
COUNTRY=""
if command -v ipinfo >/dev/null 2>&1; then
  # ipinfo puede devolver "Country Code: AR" o en JSON; intentamos texto primero
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

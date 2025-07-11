#!/bin/bash

ALLOW_COUNTRIES="AR"

if [ $# -ne 1 ]; then
  echo "Usage:  `basename $0` <ip>" 1>&2
  exit 0
fi

# Extraer IPv4 de cualquier cosa que tenga el formato IPv6/IPv4-mapeado
IP=$(echo "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

# Si no se pudo extraer una IPv4, bloquear
if [ -z "$IP" ]; then
  logger "DENY sshd connection from $1 (no IPv4 found)"
  exit 1
fi

COUNTRY=$(/usr/bin/geoiplookup "$IP" | awk -F ": " '{ print $2 }' | awk -F "," '{ print $1 }' | head -n 1)

if [[ "$COUNTRY" == "IP Address not found" ]]; then
  logger "DENY sshd connection from $1 ($COUNTRY)"
  exit 1
fi

if [[ "$ALLOW_COUNTRIES" =~ $COUNTRY ]]; then
  exit 0
else
  logger "DENY sshd connection from $1 ($COUNTRY)"
  exit 1
fi

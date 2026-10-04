#!/bin/bash
set -euo pipefail

NAME="${1:-aerotab-dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "certificate '$NAME' already exists"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null

openssl pkcs12 -export -legacy -passout pass:aerotab \
  -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12"

security import "$work/id.p12" -k "$KEYCHAIN" -P aerotab -T /usr/bin/codesign >/dev/null
echo "imported '$NAME' into $KEYCHAIN"

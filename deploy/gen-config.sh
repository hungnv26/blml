#!/usr/bin/env bash
#
# Generates deploy/blml.conf from the rebranded server/server/tinode.conf,
# substituting the secrets from deploy/secrets.env and pointing the server at
# the compose Postgres.
#
# Rerun after changing secrets.env or pulling upstream config changes.
# blml.conf is generated + gitignored; tinode.conf stays the pristine template.
#
set -euo pipefail
cd "$(dirname "$0")"

source ./secrets.env

TEMPLATE=../server/server/tinode.conf
OUT=./blml.conf

sed \
  -e "s|T713/rYYgW7g4m3vG6zGRh7+FM1t0T8j13koXScOAj4=|${API_KEY_SALT}|" \
  -e "s|wfaY2RgF2S1OQI/ZlK+LSrp1KB2jwAdGAIHQ7JZn+Kc=|${AUTH_TOKEN_KEY}|" \
  -e "s|la6YsO+bNX/+XIkOqc5Svw==|${UID_ENCRYPTION_KEY}|" \
  -e 's|"use_adapter": ""|"use_adapter": "postgres"|' \
  -e 's|"Passwd": "postgres"|"Passwd": "'"${POSTGRES_PASSWORD}"'"|' \
  -e 's|"Host": "localhost"|"Host": "db"|' \
  -e 's|"max_size": 8388608|"max_size": 104857600|' \
  -e 's|"upload_dir": "uploads"|"upload_dir": "/var/blml/uploads"|' \
  -e 's|"required": \["auth"\]|"required": []|' \
  "$TEMPLATE" > "$OUT"

# Sanity: no known default secret may survive into the generated config.
for leaked in 'T713/rYYgW7g4m3vG6zGRh7' 'wfaY2RgF2S1OQI' 'la6YsO+bNX'; do
  if grep -qF "$leaked" "$OUT"; then
    echo "ERROR: default secret '$leaked' still present in $OUT" >&2
    exit 1
  fi
done

echo "wrote $OUT"
grep -n '"use_adapter"\|"Host"\|"max_size"\|"upload_dir"' "$OUT" | head -6

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

# Invite-only registration: inject the code as a top-level array. An empty
# REGISTRATION_CODE leaves registration open.
if [ -n "${REGISTRATION_CODE:-}" ]; then
  python3 - "$REGISTRATION_CODE" "$OUT" <<'PYEOF'
import re, sys
code, path = sys.argv[1], sys.argv[2]
s = open(path).read()
s = re.sub(r'\n\t"registration_codes": \[[^\]]*\],', '', s)
entry = '\n\t"registration_codes": ["%s"],' % code
s = re.sub(r'(\n\t"api_key_salt": "[^"]*",)', lambda m: m.group(1) + entry, s, count=1)
open(path, 'w').write(s)
PYEOF
  echo "  registration_codes: invite-only enabled"
fi

# Email verification. When EMAIL_VERIFICATION=true the email validator is
# required for auth-level accounts and SMTP settings are substituted in.
python3 - "$OUT" <<'PYEOF'
import re, sys, os
path = sys.argv[1]
s = open(path).read()
enabled = os.environ.get('EMAIL_VERIFICATION', '').lower() == 'true'

s = re.sub(r'("email":\s*\{[^}]*?"required":\s*)\[[^\]]*\]',
           lambda m: m.group(1) + ('["auth"]' if enabled else '[]'), s, count=1, flags=re.S)

if enabled:
    def setkey(text, key, value):
        # The value may contain escaped quotes, e.g. "\"BLML\" <a@b>", so the
        # naive "[^"]*" pattern stops at the first \" and corrupts the line.
        return re.sub(r'("%s":\s*)"(?:[^"\\]|\\.)*"' % key,
                      lambda m: m.group(1) + '"' + value.replace('"', '\\"') + '"',
                      text, count=1)
    # Only the email validator's own config block, not the SMS one below it.
    i = s.find('"email": {')
    j = s.find('"tel": {', i)
    block = s[i:j]
    block = setkey(block, 'smtp_server', os.environ.get('SMTP_SERVER', ''))
    block = setkey(block, 'smtp_port', os.environ.get('SMTP_PORT', ''))
    block = setkey(block, 'login', os.environ.get('SMTP_LOGIN', ''))
    block = setkey(block, 'sender_password', os.environ.get('SMTP_PASSWORD', ''))
    block = setkey(block, 'sender', os.environ.get('SMTP_SENDER', ''))
    block = setkey(block, 'smtp_helo_host', 'blml.app')
    s = s[:i] + block + s[j:]

open(path, 'w').write(s)
print("  email verification: " + ("REQUIRED" if enabled else "disabled"))
PYEOF

echo "wrote $OUT"
grep -n '"use_adapter"\|"Host"\|"max_size"\|"upload_dir"' "$OUT" | head -6

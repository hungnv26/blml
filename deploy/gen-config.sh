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

# Phone verification. A verified number becomes a "tel:<number>" tag, which is
# what address-book contact sync and phone search look up. Without Twilio
# credentials the server sends no SMS and accepts a fixed debug code — see the
# warning printed below and the note in secrets.env.
python3 - "$OUT" <<'PYEOF'
import json, os, re, sys
path = sys.argv[1]
s = open(path).read()
enabled = os.environ.get('PHONE_VERIFICATION', '').lower() == 'true'

i = s.find('"tel": {')
if i < 0:
    print("  phone: tel validator not found, skipped")
    sys.exit(0)

depth, j = 0, i + len('"tel": ')
for k in range(j, len(s)):
    if s[k] == '{':
        depth += 1
    elif s[k] == '}':
        depth -= 1
        if depth == 0:
            j = k + 1
            break

cfg = {
    "host_url": "http://localhost:6060/",
    "languages": ["en", "vi"],
    "sender": "BLML",
    "universal_templ": "./templ/sms-universal-{{.Language}}.templ",
    "max_retries": 3,
}
sid, token = os.environ.get('TWILIO_SID', ''), os.environ.get('TWILIO_TOKEN', '')
if sid and token:
    cfg["twilio_conf"] = {"account_sid": sid, "auth_token": token}
else:
    # No SMS gateway: accept a fixed code instead of texting one.
    cfg["debug_response"] = os.environ.get('PHONE_DEBUG_CODE', '123456')

block = {
    "add_to_tags": True,
    # "root", not "auth" — deliberately.
    #
    # Two competing facts: a validator with an empty "required" is skipped at
    # startup, so a bare phone number never gets rewritten to a "tel:" tag and
    # phone search finds nothing. But "auth" makes a verified phone MANDATORY,
    # and login gating reads globals.authValidators[session auth level]: every
    # existing account without a phone is met with "300 validate credentials"
    # and cannot get in.
    #
    # "root" registers the validator (so the rewrite and the search work) while
    # leaving that map empty for ordinary "auth" logins, so a phone number stays
    # optional: add one in Settings when you want to be findable by it.
    "required": ["root"] if enabled else [],
    "config": cfg,
}
rendered = '"tel": ' + json.dumps(block, indent='\t').replace('\n', '\n\t\t')
s = s[:i] + rendered + s[j:]
open(path, 'w').write(s)

if enabled and "debug_response" in cfg:
    print("  phone verification: ENABLED (DEBUG MODE — no SMS sent, code '%s' accepted;"
          " anyone can claim any number)" % cfg["debug_response"])
elif enabled:
    print("  phone verification: ENABLED via Twilio")
else:
    print("  phone verification: disabled")
PYEOF

# Voice/video calls. Upstream ships "enabled": false with placeholder ICE
# servers (stun.example.com), which silently fails to connect rather than
# erroring, so the whole block is rewritten from secrets.env.
python3 - "$OUT" <<'PYEOF'
import json, os, re, sys
path = sys.argv[1]
s = open(path).read()
enabled = os.environ.get('WEBRTC_ENABLED', '').lower() == 'true'

i = s.find('"webrtc": {')
if i < 0:
    print("  webrtc: section not found, skipped")
    sys.exit(0)

# Find the matching close brace by depth, since the block contains nested
# objects and arrays.
depth, j = 0, i + len('"webrtc": ')
for k in range(j, len(s)):
    if s[k] == '{':
        depth += 1
    elif s[k] == '}':
        depth -= 1
        if depth == 0:
            j = k + 1
            break

ice = []
if os.environ.get('STUN_URL'):
    ice.append({"urls": [os.environ['STUN_URL']]})
if os.environ.get('TURN_URL'):
    entry = {"urls": [os.environ['TURN_URL']]}
    if os.environ.get('TURN_USER'):
        entry["username"] = os.environ['TURN_USER']
    if os.environ.get('TURN_PASSWORD'):
        entry["credential"] = os.environ['TURN_PASSWORD']
    ice.append(entry)

block = {"enabled": enabled, "call_establishment_timeout": 30, "ice_servers": ice}
rendered = '"webrtc": ' + json.dumps(block, indent='\t').replace('\n', '\n\t')
s = s[:i] + rendered + s[j:]
open(path, 'w').write(s)

if enabled and not ice:
    print("  WARNING: webrtc enabled but no ICE servers — calls will not connect")
else:
    print("  webrtc: %s (%d ICE server(s)%s)" % (
        "ENABLED" if enabled else "disabled", len(ice),
        "" if os.environ.get('TURN_URL') else ", STUN only — no TURN relay"))
PYEOF

echo "wrote $OUT"
grep -n '"use_adapter"\|"Host"\|"max_size"\|"upload_dir"' "$OUT" | head -6

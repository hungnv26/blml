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

# set -a so the settings reach the python blocks below, which read os.environ.
# Plain `source` leaves them as shell-only variables, and every one of those
# blocks then silently takes its "not configured" branch: no phone or email
# verification, and WebRTC disabled with no ICE servers. The generated config
# looks fine and the server starts happily — calls just never connect.
set -a
source ./secrets.env
set +a

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

# ── coturn ───────────────────────────────────────────────────────────────────
# Rendered only when a TURN relay is configured, so a local checkout that just
# uses Google's STUN never grows a stray turnserver.conf.
#
# TURN advertises the address it will relay from. Behind a cloud provider's NAT
# that has to be stated explicitly, or clients are handed an address that does
# not route and calls fail after appearing to connect.
if [ -n "${TURN_URL:-}" ]; then
  if [ -z "${TURN_USER:-}" ] || [ -z "${TURN_PASSWORD:-}" ]; then
    echo "ERROR: TURN_URL is set but TURN_USER/TURN_PASSWORD are empty" >&2
    exit 1
  fi
  turn_realm="${BLML_DOMAIN:-blml.local}"
  turn_ip="${TURN_EXTERNAL_IP:-}"
  if [ -z "$turn_ip" ]; then
    turn_ip="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [ -z "$turn_ip" ]; then
    echo "ERROR: could not determine the public IP for coturn." >&2
    echo "       Set TURN_EXTERNAL_IP in secrets.env to the VPS address." >&2
    exit 1
  fi

  cat > ./turnserver.conf <<TURNEOF
# Generated by gen-config.sh — edit secrets.env instead.
listening-port=3478
fingerprint
lt-cred-mech
realm=${turn_realm}
user=${TURN_USER}:${TURN_PASSWORD}
external-ip=${turn_ip}

# Relay only what a call needs. Without these a TURN server is an open proxy
# that strangers will find and use within days of it being reachable.
no-cli
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255

# Keep the relay range narrow and matched to the firewall rule in
# provision-vps.sh; every port here has to be open in UDP.
min-port=49160
max-port=49200
TURNEOF
  echo "wrote ./turnserver.conf (realm ${turn_realm}, external-ip ${turn_ip})"
fi

# Push notifications. Enabled by the mere presence of the Firebase service
# account key, so there is no second switch to forget: drop the file in and
# rerun, remove it and push goes quiet.
#
# The whole fcm notificator block is rewritten rather than patched in place.
# The upstream block ships an inline "credentials" object full of placeholders,
# and the server prefers it over credentials_file whenever it is present
# (push_fcm.go: `if config.Credentials == nil && config.CredentialsFile != ""`),
# so a surgical edit that forgot to delete it would authenticate with nonsense.
FCM_KEY=./fcm-service-account.json
# compose creates a directory if a bind-mount source is missing, which the
# server would then fail to read. Keep an empty placeholder so the mount always
# has a file to bind; empty means push stays off.
[ -e "$FCM_KEY" ] || : > "$FCM_KEY"
if [ -s "$FCM_KEY" ]; then
  python3 - "$FCM_KEY" "$OUT" <<'PYEOF'
import json, sys

keypath, path = sys.argv[1], sys.argv[2]
# project_id comes from the key itself; one less value to keep in sync.
project = json.load(open(keypath))["project_id"]
s = open(path).read()

# Find the fcm notificator object and replace it wholesale, matching braces so
# the surrounding array is left intact.
anchor = s.index('"name":"fcm"')
start = s.rindex('{', 0, anchor)
depth, i = 0, start
while True:
    if s[i] == '{': depth += 1
    elif s[i] == '}': depth -= 1
    if depth == 0: break
    i += 1
end = i + 1

# android.enabled stays false: that makes it a data-only message, which wakes
# the app so FBaseMessagingService can build the notification itself. With no
# content in the payload it falls back to R.string.new_message, giving
# "<sender> / New message".
#
# apns must exist and be enabled or apnsShouldPresentAlert() returns false and
# iPhones get a silent background push with no alert at all — no banner, and
# the notification service extension never runs. body is a fixed string for
# the same reason the payload carries no text: the sender is shown by the
# extension, the message is not.
block = '''{
			// Generated by gen-config.sh from fcm-service-account.json.
			"name":"fcm",
			"config": {
				"enabled": true,
				"project_id": "%s",
				"credentials_file": "/etc/blml/fcm-service-account.json",
				"apns_bundle_id": "app.blml.chat",
				"time_to_live": 3600,

				"android": {
					"enabled": false,
					"icon": "ic_logo_push",
					"color": "#00A884",
					"click_action": ".MessageActivity"
				},

				"apns": {
					"enabled": true,
					"msg": {
						"title": "",
						"body": "New message",
						"title_loc_key": "",
						"body_loc_key": ""
					},
					"sub": {
						"title": "",
						"body": "New chat",
						"title_loc_key": "",
						"body_loc_key": ""
					}
				}
			}
		}''' % project

open(path, 'w').write(s[:start] + block + s[end:])
print("  push: fcm enabled for project %s (sender only, no message text)" % project)
PYEOF
else
  echo "  push: disabled (no ./fcm-service-account.json)"
fi

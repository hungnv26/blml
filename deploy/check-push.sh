#!/usr/bin/env bash
#
# Is push actually working? Answers the three questions in order, because a
# failure at any one of them looks identical from a phone: nothing arrives.
#
#   1. Did the server load the FCM notificator?
#   2. Has any device registered a push token?
#   3. Did a send actually reach FCM, or get rejected?
#
#   ./deploy/check-push.sh          # run from the repo, talks to the VPS
set -uo pipefail
VPS=${VPS:-root@45.32.107.71}
DC="docker compose --env-file secrets.env -f docker-compose.yml -f docker-compose.prod.yml"

echo "1. server push handler"
ssh -o ConnectTimeout=15 "$VPS" "docker logs blml-blml-1 2>&1 | grep -i 'Push handlers configured' | tail -1" \
  | sed 's/^/   /' || echo "   (no line found — push handler did not load)"

echo
echo "2. registered devices"
# No 2>/dev/null and no `|| echo` fallback here: hiding stderr turned a
# broken query into the words "no devices", which is the same thing a
# working query says when nobody has installed yet. Let errors be visible.
devices=$(ssh -o ConnectTimeout=15 "$VPS" "cd /opt/blml/deploy && $DC exec -T db \
  psql -U postgres -d tinode -tAc \"SELECT coalesce(u.public->>'fn','?') || '  ' || d.platform || '  last seen ' || to_char(d.lastseen,'YYYY-MM-DD HH24:MI') FROM devices d JOIN users u ON u.id = d.userid ORDER BY d.lastseen DESC\"" 2>&1)
if [ -z "$(echo "$devices" | tr -d '[:space:]')" ]; then
  echo "   none yet — open the app on a phone and allow notifications"
else
  echo "$devices" | sed 's/^/   /'
fi

echo
echo "3. recent push activity (errors are what matter here)"
# SINCE is worth widening: a failure that happened on the last send is still
# the current failure, and 30m of history routinely misses it.
SINCE=${SINCE:-30m}
ssh -o ConnectTimeout=15 "$VPS" "docker logs --since $SINCE blml-blml-1 2>&1 | grep -iE 'fcm|push|apns' | tail -25" \
  | sed 's/^/   /' | grep -v '^\s*$' || echo "   nothing in the last $SINCE"

echo
echo "4. APNs credential (the one FCM uses to reach Apple)"
# Asks Apple directly. A sandbox-only key authenticates against the sandbox host
# and is refused by production with BadEnvironmentKeyInToken — and TestFlight and
# App Store builds are production. FCM reports this only as the opaque
# "THIRD_PARTY_AUTH_ERROR Invalid APNs credential", which does not say which of
# key, team, bundle or environment is at fault. This does.
# 4L7G2LT9P2 was sandbox-only and is retired; 43CTT28QV6 is Sandbox & Production.
APNS_KEY_ID=${APNS_KEY_ID:-43CTT28QV6}
APNS_TEAM_ID=${APNS_TEAM_ID:-Y9T5MPV87F}
APNS_P8=${APNS_P8:-$HOME/.apns/AuthKey_${APNS_KEY_ID}.p8}
if [ ! -f "$APNS_P8" ]; then
  echo "   no key at $APNS_P8 — skipping"
else
  JWT=$(python3 - "$APNS_P8" "$APNS_KEY_ID" "$APNS_TEAM_ID" <<'PYEOF'
import base64, json, sys, time
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
p8, kid, team = sys.argv[1], sys.argv[2], sys.argv[3]
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
hdr = b64(json.dumps({"alg":"ES256","kid":kid},separators=(',',':')).encode())
pay = b64(json.dumps({"iss":team,"iat":int(time.time())},separators=(',',':')).encode())
key = load_pem_private_key(open(p8,'rb').read(), password=None)
r, s = decode_dss_signature(key.sign(f"{hdr}.{pay}".encode(), ec.ECDSA(hashes.SHA256())))
print(f"{hdr}.{pay}." + b64(r.to_bytes(32,'big')+s.to_bytes(32,'big')))
PYEOF
)
  for pair in "api.sandbox.push.apple.com sandbox" "api.push.apple.com production"; do
    host=${pair% *}; label=${pair#* }
    out=$(curl -s --http2 --max-time 25 -H "authorization: bearer $JWT" \
      -H "apns-topic: app.blml.chat" -H "apns-push-type: alert" -d '{"aps":{"alert":"t"}}' \
      "https://$host/3/device/0000000000000000000000000000000000000000000000000000000000000000")
    case "$out" in
      *BadDeviceToken*)            echo "   $label: key ACCEPTED (only the dummy token was rejected)" ;;
      *BadEnvironmentKeyInToken*)  echo "   $label: key REFUSED — not valid for this environment" ;;
      *InvalidProviderToken*)      echo "   $label: key REFUSED — wrong key id or team id" ;;
      *)                           echo "   $label: $out" ;;
    esac
  done
  echo "   TestFlight and App Store builds use production. Sandbox-only is not enough."
fi

echo
echo "5. end-to-end: does FCM accept a send to a real device token?"
# Steps 1-4 each check one link in isolation and can all pass while delivery
# still fails, because the one thing they never exercise is FCM's own APNs
# handshake. This asks FCM to validate a message against a live token
# (validate_only: no notification is delivered) and prints the verdict Google
# returns, which is the error the server would have hit.
SA=${SA:-$(dirname "$0")/fcm-service-account.json}
tokens=$(ssh -o ConnectTimeout=15 "$VPS" "cd /opt/blml/deploy && $DC exec -T db \
  psql -U postgres -d tinode -tAc \"SELECT d.platform || '|' || coalesce(u.public->>'fn','?') || '|' || d.deviceid FROM devices d JOIN users u ON u.id = d.userid ORDER BY d.lastseen DESC\"" 2>&1)
if [ ! -f "$SA" ]; then
  echo "   no service account at $SA — skipping"
else
  # Tokens go through a file, not a pipe: `python3 -` already reads the script
  # itself from stdin, so a piped stdin is silently empty.
  TOKFILE=$(mktemp); printf '%s\n' "$tokens" | tr -d '\r' > "$TOKFILE"
  trap 'rm -f "$TOKFILE"' EXIT
  python3 - "$SA" "$TOKFILE" <<'PYEOF'
import base64, json, sys, time, urllib.request, urllib.error
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes

sa = json.load(open(sys.argv[1]))
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
now = int(time.time())
hdr = b64(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(',', ':')).encode())
pay = b64(json.dumps({
    "iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/firebase.messaging",
    "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now + 3600,
}, separators=(',', ':')).encode())
key = load_pem_private_key(sa["private_key"].encode(), password=None)
sig = b64(key.sign(f"{hdr}.{pay}".encode(), padding.PKCS1v15(), hashes.SHA256()))
body = urllib.parse.urlencode({
    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "assertion": f"{hdr}.{pay}.{sig}"}).encode()
try:
    tok = json.load(urllib.request.urlopen(urllib.request.Request(
        "https://oauth2.googleapis.com/token", data=body), timeout=25))["access_token"]
except urllib.error.HTTPError as e:
    print("   could not get a Google token:", e.read().decode()[:300]); sys.exit(0)

url = f"https://fcm.googleapis.com/v1/projects/{sa['project_id']}/messages:send"
import os
only, send = os.environ.get("ONLY", ""), os.environ.get("SEND", "")
rows = [l for l in open(sys.argv[2]).read().splitlines() if l.count("|") == 2]
if not rows:
    print("   no device tokens to test")
for row in rows:
    platform, who, token = row.strip().split("|", 2)
    # validate_only never touches Apple, so it cannot see a bad APNs
    # credential — the single most common cause of silent iOS failure.
    # ONLY=<name> plus SEND=1 does one real, delivered send to that person's
    # device, which is the only way to make FCM report THIRD_PARTY_AUTH_ERROR.
    if only and only.lower() not in who.lower():
        continue
    real = bool(send and only)
    msg = {"validate_only": not real, "message": {"token": token,
           "apns": {"payload": {"aps": {"alert": {"title": "BLML",
                    "body": "Push diagnostic"}, "sound": "default"}}},
           "data": {"what": "check"}}}
    req = urllib.request.Request(url, data=json.dumps(msg).encode(), headers={
        "Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    label = f"   {who} ({platform})"
    try:
        urllib.request.urlopen(req, timeout=25)
        print(f"{label}: FCM ACCEPTED the {'REAL send — watch the phone' if real else 'send'}")
    except urllib.error.HTTPError as e:
        err = json.loads(e.read().decode() or "{}").get("error", {})
        detail = next((d.get("errorCode", "") for d in err.get("details", [])
                       if "FcmError" in d.get("@type", "")), "")
        print(f"{label}: REJECTED {e.code} {detail or err.get('status','')} — {err.get('message','')[:160]}")
PYEOF
fi

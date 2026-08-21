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
ssh -o ConnectTimeout=15 "$VPS" "cd /opt/blml/deploy && $DC exec -T db \
  psql -U postgres -d tinode -tAc \"SELECT coalesce(u.public->>'fn','?') || '  ' || d.devicetype FROM devices d JOIN users u ON u.id = d.userid\"" 2>/dev/null \
  | sed 's/^/   /' | grep -v '^\s*$' || echo "   none yet — open the app on a phone and allow notifications"

echo
echo "3. recent push activity (errors are what matter here)"
ssh -o ConnectTimeout=15 "$VPS" "docker logs --since 30m blml-blml-1 2>&1 | grep -iE 'fcm|push' | tail -12" \
  | sed 's/^/   /' | grep -v '^\s*$' || echo "   nothing in the last 30 minutes"

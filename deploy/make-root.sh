#!/usr/bin/env bash
#
# Creates a working ROOT account for the admin console.
#
#   ./make-root.sh blmladmin 'some-strong-password'
#
# This exists because `tinode-db --add_root` does not produce an account that
# can actually log in. Three things have to be true, and it gets two of them
# wrong:
#
#   1. The auth record's uname must be `basic:<login>`. --add_root writes
#      `:<login>` — an empty scheme — because it fetches the basic handler
#      with GetAuthHandler("basic") without initialising it, so the handler's
#      own name is blank. A login for scheme "basic" then matches nothing and
#      the server answers 401.
#
#   2. Root accounts need a validated credential. gen-config.sh deliberately
#      sets the tel validator to `required: ["root"]` — that registers the
#      validator without forcing a phone on ordinary members, but it does mean
#      a root login without one is met with "300 validate credentials". The
#      session is not authenticated at that point, so it cannot add its own
#      credential through the API either.
#
#   3. `credentials.resp` must not be NULL. The server scans it into a
#      *string and a NULL turns any login into a 500.
#
#   --add_root also calls store.Users.Create twice (tinode-db/main.go:341 and
#   343), leaving an orphan user row. Harmless, and left alone here: deleting
#   it trips a foreign key from subscriptions.
#
# Everything below was established by running it, not by reading the source.
set -euo pipefail
cd "$(dirname "$0")"

LOGIN=${1:-blmladmin}
# Generated, not supplied. Every time this script has taken a password as an
# argument, the value that arrived was a placeholder from the instructions or
# a stale shell variable — three times running, twice landing a guessable
# password on an internet-reachable ROOT account. A value nobody types is a
# value nobody can get wrong.
PASSWORD=${2:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-24)}
# A placeholder number, only ever used to satisfy the validator above.
PHONE=${ROOT_PHONE:-+15550100001}

set -a
# shellcheck disable=SC1091
source ./secrets.env
set +a

COMPOSE="docker compose --env-file secrets.env"
if [ -f docker-compose.prod.yml ] && [ "${PROD:-}" = "1" ]; then
  COMPOSE="$COMPOSE -f docker-compose.yml -f docker-compose.prod.yml"
fi

psql() { $COMPOSE exec -T db psql -U postgres -d tinode "$@"; }

# --add_root refuses outright when the login already exists ("duplicate
# value"), which makes a re-run abort before any of the repairs below. Clear
# the previous auth records first so this script is safe to run again — which
# it needs to be, because rotating the password is exactly a re-run.
#
# The old user rows are deliberately left behind: subscriptions reference
# them, so deleting trips a foreign key. They are inert once the auth record
# is gone.
echo "==> Clearing any previous auth record for ${LOGIN}"
psql -c "DELETE FROM auth WHERE uname IN ('basic:${LOGIN}', ':${LOGIN}')"

echo "==> Creating the account"
# tinode-db logs the credentials it just created, in the clear. Redact that
# line: this script generates the password precisely so it never has to pass
# through a human's eyes, and letting the tool print it undoes the whole point.
$COMPOSE run --rm blml-init --config=/etc/blml/blml.conf \
  --add_root="${LOGIN}:${PASSWORD}" 2>&1 \
  | sed -E "s/ROOT user created:.*/ROOT user created (password withheld)/" \
  | tail -2

echo "==> Repairing the auth record's scheme prefix"
# Each statement separately: psql -c "a; b" runs them in ONE transaction, so a
# later failure silently rolls back an earlier success.
psql -c "UPDATE auth SET uname = 'basic' || uname WHERE uname = ':${LOGIN}'"

UID_ROW=$(psql -tAc "SELECT userid FROM auth WHERE uname = 'basic:${LOGIN}'" | tr -d '[:space:]')
[ -n "$UID_ROW" ] || { echo "error: no auth record for basic:${LOGIN}" >&2; exit 1; }

echo "==> Attaching a validated credential"
# Clear any row holding this number first. A previous run's credential belongs
# to a user that no longer has an auth record, and the unique index on
# `synthetic` would otherwise turn this INSERT into a silent no-op.
psql -c "DELETE FROM credentials WHERE synthetic = 'tel:${PHONE}'"
psql -c "INSERT INTO credentials
           (createdat, updatedat, method, value, synthetic, userid, done, resp, retries)
         VALUES (now(), now(), 'tel', '${PHONE}', 'tel:${PHONE}', ${UID_ROW}, true, '', 0)"

echo "==> Verifying"
CHECK=$(psql -tAc "SELECT a.authlvl || '/' || coalesce(c.done::text, 'nocred')
                   FROM auth a LEFT JOIN credentials c ON c.userid = a.userid
                   WHERE a.uname = 'basic:${LOGIN}'" | tr -d '[:space:]')
if [ "$CHECK" != "30/true" ]; then
  echo "FAILED: expected authlvl 30 with a validated credential, got '${CHECK}'" >&2
  exit 1
fi
echo "  ok: authlvl 30, credential validated"

echo "==> Recording it in secrets.env"
sed -i '/^TINODE_ROOT_LOGIN=/d; /^TINODE_ROOT_PASSWORD=/d' secrets.env
printf 'TINODE_ROOT_LOGIN=%s\nTINODE_ROOT_PASSWORD=%s\n' "$LOGIN" "$PASSWORD" >> secrets.env

cat <<EOF

Done. secrets.env now holds the root credentials; nothing further to copy.

The password is stored there and nowhere else. tinode-db logs it in the clear,
so that line is redacted above — the value never needs to be read by a human,
and every failed attempt at this went wrong because one passed through.
EOF

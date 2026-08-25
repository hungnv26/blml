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

LOGIN=${1:?usage: ./make-root.sh <login> <password>}
PASSWORD=${2:?usage: ./make-root.sh <login> <password>}
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

echo "==> Creating the account"
$COMPOSE run --rm blml-init --config=/etc/blml/blml.conf \
  --add_root="${LOGIN}:${PASSWORD}" 2>&1 | tail -2

echo "==> Repairing the auth record's scheme prefix"
# Each statement separately: psql -c "a; b" runs them in ONE transaction, so a
# later failure silently rolls back an earlier success.
psql -c "UPDATE auth SET uname = 'basic' || uname WHERE uname = ':${LOGIN}'"

UID_ROW=$(psql -tAc "SELECT userid FROM auth WHERE uname = 'basic:${LOGIN}'" | tr -d '[:space:]')
[ -n "$UID_ROW" ] || { echo "error: no auth record for basic:${LOGIN}" >&2; exit 1; }

echo "==> Attaching a validated credential"
psql -c "INSERT INTO credentials
           (createdat, updatedat, method, value, synthetic, userid, done, resp, retries)
         VALUES (now(), now(), 'tel', '${PHONE}', 'tel:${PHONE}', ${UID_ROW}, true, '', 0)
         ON CONFLICT DO NOTHING"

echo "==> Verifying"
psql -tAc "SELECT a.uname, a.authlvl, c.method, c.done
           FROM auth a LEFT JOIN credentials c ON c.userid = a.userid
           WHERE a.uname = 'basic:${LOGIN}'"

cat <<EOF

Done. Put these in secrets.env for the admin console:

  TINODE_ROOT_LOGIN=${LOGIN}
  TINODE_ROOT_PASSWORD=${PASSWORD}

Confirm it works before relying on it — a root login should answer
200 with authlvl "root", not 300 "validate credentials".
EOF

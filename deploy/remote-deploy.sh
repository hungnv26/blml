#!/usr/bin/env bash
#
# Runs ON the server. migrate-to-vps.sh rsyncs this across and executes it.
#
# It lives in its own file rather than being piped into `ssh bash -s` on
# purpose: `docker compose exec -T` attaches stdin, and when the script itself
# arrives on stdin the first such command eats the remainder of it. bash then
# reaches EOF and exits 0, so the deploy stops silently, half-done, and reports
# success. Executing a real file gives every command a clean stdin.
#
# Restores /tmp/tinode.sql and /tmp/uploads.tar if migrate-to-vps.sh staged
# them, then brings the whole stack up. Safe to re-run without them.
set -euo pipefail
cd "$(dirname "$0")"

set -a
# shellcheck disable=SC1091
source ./secrets.env
set +a

# Only Caddy should be able to reach the server; it proxies over the compose
# network, so the published port stays on loopback.
export BLML_BIND=127.0.0.1

COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"

echo "==> Rendering config"
./gen-config.sh

echo "==> Starting database"
$COMPOSE up -d db
for i in $(seq 1 60); do
  if $COMPOSE exec -T db pg_isready -U postgres </dev/null >/dev/null 2>&1; then break; fi
  [ "$i" = 60 ] && { echo "postgres did not become ready" >&2; exit 1; }
  sleep 2
done

# init-db creates the schema, but it needs the database itself to exist first.
if ! $COMPOSE exec -T db psql -U postgres -tAc \
      "SELECT 1 FROM pg_database WHERE datname='tinode'" </dev/null | grep -q 1; then
  echo "==> Creating database"
  $COMPOSE exec -T db psql -U postgres -c "CREATE DATABASE tinode" </dev/null >/dev/null
fi

if [ -f /tmp/tinode.sql ]; then
  echo "==> Restoring database"
  $COMPOSE exec -T db psql -U postgres -d tinode -q -v ON_ERROR_STOP=1 < /tmp/tinode.sql
  echo "    $($COMPOSE exec -T db psql -U postgres -d tinode -tAc \
    'SELECT count(*) FROM users' </dev/null) accounts restored"
fi

if [ -f /tmp/uploads.tar ]; then
  echo "==> Restoring media"
  docker run --rm -v blml_uploads:/u -w /u -v /tmp:/in alpine \
    sh -c 'tar xf /in/uploads.tar' </dev/null
fi

echo "==> Building and starting everything (the Go build takes a few minutes)"
$COMPOSE up -d --build

rm -f /tmp/tinode.sql /tmp/uploads.tar
echo "==> Stack up"
$COMPOSE ps --format '    {{.Name}}  {{.State}}'

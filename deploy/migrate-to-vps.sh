#!/usr/bin/env bash
#
# Ships BLML to the VPS: code, secrets, database and uploaded media.
#
#   ./deploy/migrate-to-vps.sh root@203.0.113.10
#
# Run it from your Mac with the local stack UP — the data comes out of the
# running containers.
#
# It carries the existing API_KEY_SALT and UID_ENCRYPTION_KEY across unchanged.
# That is deliberate: those two derive every user ID and the client API key, so
# reusing them means the accounts, the message history and the app builds
# already on everyone's phones all keep working. Generating fresh ones would
# mean every family member re-registers and every client needs rebuilding.
#
# Re-running replaces the server's database with your local one. It asks first.
set -euo pipefail
cd "$(dirname "$0")"

TARGET="${1:-}"
FORCE="${2:-}"
[ -n "$TARGET" ] || { echo "usage: $0 user@host [--force]" >&2; exit 1; }

REMOTE_DIR=/opt/blml
log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
log "Checking local state"
[ -f secrets.env ] || die "deploy/secrets.env not found"
# shellcheck disable=SC1091
set -a; source ./secrets.env; set +a

for v in API_KEY_SALT AUTH_TOKEN_KEY UID_ENCRYPTION_KEY POSTGRES_PASSWORD \
         BLML_DOMAIN ACME_EMAIL TURN_USER TURN_PASSWORD; do
  [ -n "${!v:-}" ] || die "$v is empty in secrets.env"
done
echo "  domain: $BLML_DOMAIN"

docker compose ps --services --filter status=running | grep -qx db \
  || die "local stack is not running — start it first, the data is read from it"

# The DNS check is advisory: Caddy is what actually needs the record, and it
# will simply retry until it resolves.
host_ip="$(echo "$TARGET" | sed 's/.*@//')"
resolved="$(dig +short "$BLML_DOMAIN" A 2>/dev/null | tail -1 || true)"
if [ -n "$resolved" ] && [ "$resolved" != "$host_ip" ]; then
  printf '\033[1;33mwarning:\033[0m %s resolves to %s, not %s — TLS will fail until DNS updates\n' \
    "$BLML_DOMAIN" "$resolved" "$host_ip"
elif [ -z "$resolved" ]; then
  printf '\033[1;33mwarning:\033[0m %s does not resolve yet — add the A record before Caddy starts\n' \
    "$BLML_DOMAIN"
fi

log "Checking the server is reachable"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" \
  'command -v docker >/dev/null || { echo "docker missing — run provision-vps.sh first" >&2; exit 1; }' \
  || die "cannot ssh to $TARGET, or provision-vps.sh has not been run there"

if [ "$FORCE" != "--force" ]; then
  remote_users="$(ssh "$TARGET" "cd $REMOTE_DIR/deploy 2>/dev/null && \
    docker compose exec -T db psql -U postgres -d tinode -tAc \
    'SELECT count(*) FROM users' 2>/dev/null" || echo "")"
  if [ -n "$remote_users" ] && [ "$remote_users" -gt 0 ] 2>/dev/null; then
    printf '\n\033[1;31mThe server already has %s user accounts.\033[0m\n' "$remote_users"
    printf 'Continuing REPLACES them with your local database. Type yes to proceed: '
    read -r reply
    [ "$reply" = "yes" ] || die "aborted"
  fi
fi

# ── Snapshot the local data ──────────────────────────────────────────────────
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

log "Dumping database and media"
docker compose exec -T db pg_dump -U postgres --clean --if-exists tinode \
  > "$STAGE/tinode.sql"
echo "  database: $(du -h "$STAGE/tinode.sql" | cut -f1)"

# Read the uploads out of the volume via a throwaway container, so this works
# whether or not the app container happens to be running.
docker run --rm -v blml_uploads:/u -w /u alpine \
  tar cf - . > "$STAGE/uploads.tar" 2>/dev/null
echo "  media:    $(du -h "$STAGE/uploads.tar" | cut -f1)"

# ── Ship ─────────────────────────────────────────────────────────────────────
log "Copying the project to $TARGET:$REMOTE_DIR"
ssh "$TARGET" "mkdir -p $REMOTE_DIR"
rsync -az --delete \
  --exclude '.git' --exclude 'node_modules' --exclude 'build' \
  --exclude '*.apk' --exclude '*.ipa' --exclude 'DerivedData' \
  --exclude 'deploy/blml.conf' --exclude 'deploy/turnserver.conf' \
  ../ "$TARGET:$REMOTE_DIR/"

# secrets.env is gitignored and excluded from nothing above only because it
# lives inside deploy/ — send it explicitly so intent is visible.
scp -q secrets.env "$TARGET:$REMOTE_DIR/deploy/secrets.env"
scp -q "$STAGE/tinode.sql" "$STAGE/uploads.tar" "$TARGET:/tmp/"

# ── Bring it up ────────────────────────────────────────────────────────────--
# Executed as a file on the server, never piped to `ssh bash -s`: `docker
# compose exec -T` attaches stdin, so a script arriving on stdin gets eaten
# mid-run and the deploy stops silently while still exiting 0.
log "Building and starting the stack (the Go build takes a few minutes)"
ssh "$TARGET" "cd $REMOTE_DIR/deploy && chmod +x remote-deploy.sh && ./remote-deploy.sh"

# ── Verify ───────────────────────────────────────────────────────────────────
log "Verifying"
sleep 12
# secrets.env has to be sourced for compose to interpolate POSTGRES_PASSWORD;
# </dev/null so exec -T does not swallow this script's own stdin.
users="$(ssh "$TARGET" "cd $REMOTE_DIR/deploy && set -a && . ./secrets.env && set +a && \
  docker compose exec -T db psql -U postgres -d tinode -tAc 'SELECT count(*) FROM users'" \
  </dev/null 2>/dev/null | tr -d '[:space:]' || echo '?')"
echo "  accounts on server: $users"

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "https://$BLML_DOMAIN/" || echo 000)"
if [ "$code" = "200" ]; then
  echo "  https://$BLML_DOMAIN -> 200 OK"
else
  echo "  https://$BLML_DOMAIN -> $code"
  echo "  If this is 000, Caddy may still be issuing the certificate. Check:"
  echo "    ssh $TARGET 'cd $REMOTE_DIR/deploy && docker compose logs caddy | tail -30'"
fi

log "Done"
echo "Admin dashboard (loopback only):"
echo "  ssh -L 6061:localhost:6061 $TARGET"
echo "  then open http://localhost:6061/?token=\$ADMIN_TOKEN"

#!/usr/bin/env bash
#
# Nightly backup of the database and uploaded media.
#
# Install on the VPS (run from /opt/blml/deploy):
#   ./backup.sh --install
#
# Or take one now:
#   ./backup.sh
#
# Backups land in /var/backups/blml. That is still the same disk as the data,
# so it protects against "someone deleted the group" but not against losing the
# server. Enable the provider's snapshots as well, or add an off-box copy at
# the bottom of this file.
set -euo pipefail
cd "$(dirname "$0")"

DEST=${BLML_BACKUP_DIR:-/var/backups/blml}
KEEP_DAYS=${BLML_BACKUP_KEEP_DAYS:-14}

if [ "${1:-}" = "--install" ]; then
  here="$(cd "$(dirname "$0")" && pwd)"
  line="15 3 * * * cd $here && ./backup.sh >> /var/log/blml-backup.log 2>&1"
  # Replace any previous entry rather than stacking duplicates.
  ( crontab -l 2>/dev/null | grep -v 'blml/deploy/backup.sh\|blml-backup.log' || true
    echo "$line" ) | crontab -
  echo "installed: nightly at 03:15, logging to /var/log/blml-backup.log"
  crontab -l | tail -2
  exit 0
fi

mkdir -p "$DEST"
stamp=$(date +%Y%m%d-%H%M%S)

# --clean --if-exists so the dump can be replayed onto a populated database
# without hand-dropping anything first.
docker compose exec -T db pg_dump -U postgres --clean --if-exists tinode \
  | gzip > "$DEST/db-$stamp.sql.gz"

docker run --rm -v blml_uploads:/u -w /u alpine tar czf - . \
  > "$DEST/uploads-$stamp.tar.gz"

# Verify rather than trust: a zero-length or truncated dump is worse than no
# backup, because it looks like one.
gzip -t "$DEST/db-$stamp.sql.gz" || { echo "database dump is corrupt" >&2; exit 1; }
gzip -t "$DEST/uploads-$stamp.tar.gz" || { echo "media archive is corrupt" >&2; exit 1; }

find "$DEST" -name 'db-*.sql.gz' -mtime "+$KEEP_DAYS" -delete
find "$DEST" -name 'uploads-*.tar.gz' -mtime "+$KEEP_DAYS" -delete

printf '%s  db %s  media %s\n' "$stamp" \
  "$(du -h "$DEST/db-$stamp.sql.gz" | cut -f1)" \
  "$(du -h "$DEST/uploads-$stamp.tar.gz" | cut -f1)"

# ── Off-box copy (optional) ──────────────────────────────────────────────────
# Uncomment and point at somewhere that is not this server. Without this, a
# destroyed VPS takes the backups with it.
#
# rclone copy "$DEST" remote:blml-backups --max-age 25h

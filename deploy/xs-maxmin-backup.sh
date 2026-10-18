#!/bin/bash
# Online-safe daily backup of the xs-maxmin SQLite DB. Keeps the newest 14.
set -u
DB=/opt/xs-maxmin/backend/build/data/xoso.db
DIR=/var/backups/xs-maxmin
LOGDIR=/var/log/xs-maxmin
LOG=$LOGDIR/backup.log
KEEP=14
umask 077
mkdir -p "$DIR" "$LOGDIR"; chmod 700 "$DIR"
DEST="$DIR/xoso-$(date +%Y%m%d-%H%M).db"
if sqlite3 "$DB" ".backup '$DEST'" && [ "$(sqlite3 "$DEST" 'pragma integrity_check;')" = "ok" ]; then
  chmod 600 "$DEST"
  echo "$(date '+%F %T') OK $DEST $(stat -c %s "$DEST") bytes" >> "$LOG"
else
  rm -f "$DEST"
  echo "$(date '+%F %T') FAIL backup of $DB" >> "$LOG"
  exit 1
fi
ls -1t "$DIR"/xoso-*.db 2>/dev/null | tail -n +$((KEEP+1)) | while read -r f; do
  rm -f -- "$f"; echo "$(date '+%F %T') PRUNED $f" >> "$LOG"
done

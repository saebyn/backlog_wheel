#!/bin/sh
set -eu

DB_USERNAME=$(python3 -c "import json; print(json.load(open('/opt/backlog-wheel/database-secret.json'))['username'])")
TABLE_COUNT=$(docker exec backlog-wheel-postgres psql -U "$DB_USERNAME" -d backlog_wheel -tAc "select count(*) from information_schema.tables where table_schema = 'public'")

if [ "$TABLE_COUNT" != "0" ]; then
  echo "Database already has public tables; skipping restore."
  exit 0
fi

aws s3api list-objects-v2 \
  --bucket __DATABASE_BACKUP_BUCKET__ \
  --prefix database/ \
  --output json > /tmp/backlog-wheel-backups.json

LATEST_KEY=$(python3 - <<'PY'
import json
from pathlib import Path

objects = json.loads(Path('/tmp/backlog-wheel-backups.json').read_text()).get('Contents', [])
objects = [obj for obj in objects if obj.get('Key', '').endswith('.dump')]
print(max(objects, key=lambda obj: obj['LastModified'])['Key'] if objects else '')
PY
)

if [ -z "$LATEST_KEY" ]; then
  echo "No database backup found; starting with empty database."
  exit 0
fi

echo "Restoring database backup: $LATEST_KEY"
aws s3 cp "s3://__DATABASE_BACKUP_BUCKET__/$LATEST_KEY" - \
  | docker exec -i backlog-wheel-postgres pg_restore -U "$DB_USERNAME" -d backlog_wheel --clean --if-exists --no-owner

#!/bin/sh
set -eu

if ! docker inspect backlog-wheel-postgres >/dev/null 2>&1; then
  exit 0
fi

DB_USERNAME=$(python3 -c "import json; print(json.load(open('/opt/backlog-wheel/database-secret.json'))['username'])")
mkdir -p /opt/backlog-wheel/backups

BACKUP=/opt/backlog-wheel/backups/backlog_wheel-$(date -u +%Y%m%d%H%M%S).dump
docker exec backlog-wheel-postgres pg_dump -U "$DB_USERNAME" -d backlog_wheel -Fc > "$BACKUP"
aws s3 cp "$BACKUP" s3://__DATABASE_BACKUP_BUCKET__/database/$(basename "$BACKUP")

find /opt/backlog-wheel/backups -type f -name '*.dump' -mtime +7 -delete

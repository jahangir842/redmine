#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() { echo >&2 "Usage: $0 [--yes] backups/YYYY-MM-DD_HHMMSS"; exit 2; }
assume_yes=0
if [[ "${1:-}" == "--yes" ]]; then assume_yes=1; shift; fi
[[ $# -eq 1 ]] || usage
backup_dir="$(cd "$1" 2>/dev/null && pwd)" || { echo >&2 "Backup directory does not exist: $1"; exit 1; }

for file in redmine.dump redmine-files.tar.gz metadata.txt checksums.sha256; do
  [[ -f "$backup_dir/$file" ]] || { echo >&2 "Missing $backup_dir/$file"; exit 1; }
done
(cd "$backup_dir" && sha256sum --check --strict checksums.sha256)

if tar -tzf "$backup_dir/redmine-files.tar.gz" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo >&2 "Unsafe path found in attachment archive"; exit 1
fi

command -v docker >/dev/null 2>&1 || { echo >&2 "docker is required"; exit 1; }
[[ -f .env ]] || { echo >&2 "Missing .env"; exit 1; }

echo "WARNING: this will replace the configured Redmine database and every attachment."
echo "Target compose project: $(docker compose config --format json 2>/dev/null | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -1 || echo unknown)"
echo "Backup: $backup_dir"
if (( ! assume_yes )); then
  read -r -p "Type RESTORE to continue: " answer
  [[ "$answer" == RESTORE ]] || { echo "Restore cancelled."; exit 1; }
fi

docker compose up -d postgres
until docker compose exec -T postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; do sleep 2; done
docker compose stop nginx redmine >/dev/null 2>&1 || true

echo "Recreating the application database..."
docker compose exec -T postgres sh -eu -c '
  dropdb --if-exists --force --username="$POSTGRES_USER" "$REDMINE_DB_DATABASE"
  createdb --username="$POSTGRES_USER" --owner="$REDMINE_DB_USERNAME" --encoding=UTF8 "$REDMINE_DB_DATABASE"
'
docker compose exec -T postgres sh -eu -c \
  'exec pg_restore --exit-on-error --no-owner --no-acl --role="$REDMINE_DB_USERNAME" --username="$POSTGRES_USER" --dbname="$REDMINE_DB_DATABASE"' \
  < "$backup_dir/redmine.dump"

echo "Replacing the attachments volume..."
docker compose run --rm --no-deps -T --entrypoint sh redmine -eu -c \
  'find /usr/src/redmine/files -mindepth 1 -delete; tar -xzf - -C /usr/src/redmine/files --no-same-owner; chown -R redmine:redmine /usr/src/redmine/files' \
  < "$backup_dir/redmine-files.tar.gz"

echo "Applying target-version migrations..."
docker compose run --rm -T redmine bundle exec rake db:migrate RAILS_ENV=production
docker compose run --rm -T redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
docker compose up -d

echo "Waiting for service health..."
if ! "$ROOT_DIR/scripts/healthcheck.sh" --wait; then
  echo >&2 "Restore finished, but health verification failed. Inspect: docker compose logs"
  exit 1
fi
echo "Restore complete. Retain the backup until application-level validation is complete."

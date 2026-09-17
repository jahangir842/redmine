#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v docker >/dev/null 2>&1 || { echo >&2 "docker is required"; exit 1; }
docker compose version >/dev/null
[[ -f .env ]] || { echo >&2 "Missing .env (copy .env.example and configure it)"; exit 1; }

timestamp="$(date -u +%Y-%m-%d_%H%M%S)"
backup_dir="${BACKUP_ROOT:-$ROOT_DIR/backups}/$timestamp"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

running_services="$(docker compose ps --status running --services 2>/dev/null || true)"
grep -qx postgres <<<"$running_services" || { echo >&2 "PostgreSQL is not running"; exit 1; }

restart_app=0
restart_proxy=0
grep -qx redmine <<<"$running_services" && restart_app=1
grep -qx nginx <<<"$running_services" && restart_proxy=1

restart_services() {
  local services=()
  (( restart_app )) && services+=(redmine)
  (( restart_proxy )) && services+=(nginx)
  if ((${#services[@]})); then
    docker compose start "${services[@]}" >/dev/null
  fi
  return 0
}
trap restart_services EXIT

echo "Quiescing Redmine to keep the database and attachments consistent..."
(( restart_proxy )) && docker compose stop nginx >/dev/null
(( restart_app )) && docker compose stop redmine >/dev/null

echo "Creating PostgreSQL custom-format dump..."
docker compose exec -T postgres sh -eu -c \
  'PGPASSWORD="$REDMINE_DB_PASSWORD" exec pg_dump --format=custom --no-owner --no-acl --username="$REDMINE_DB_USERNAME" --dbname="$REDMINE_DB_DATABASE"' \
  > "$backup_dir/redmine.dump"

echo "Archiving attachments and DMSF documents..."
docker compose run --rm --no-deps -T --entrypoint tar redmine \
  -C /usr/src/redmine/files -czf - . > "$backup_dir/redmine-files.tar.gz"

{
  printf 'backup_timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'redmine_version=6.1.4\n'
  printf 'ruby_version=3.4.10\n'
  printf 'rails_version=7.2.3.2\n'
  printf 'dmsf_version=4.1.3\n'
  printf 'postgresql_version='
  docker compose exec -T postgres postgres --version | tr -d '\r'
  printf 'compose_images=\n'
  docker compose config --images | sed 's/^/  /'
  printf 'image_ids=\n'
  docker compose images --quiet | sort -u | sed 's/^/  /'
  printf 'compose_project=%s\n' "$(docker compose config --format json 2>/dev/null | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -1 || true)"
} > "$backup_dir/metadata.txt"

(
  cd "$backup_dir"
  sha256sum redmine.dump redmine-files.tar.gz metadata.txt > checksums.sha256
)

trap - EXIT
restart_services
echo "Backup complete: $backup_dir"

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo >&2 "Missing .env"; exit 1; }

"$ROOT_DIR/scripts/healthcheck.sh" --wait

echo "== Runtime versions =="
docker compose exec -T redmine ruby --version
docker compose exec -T redmine bundle exec rails --version
docker compose exec -T postgres postgres --version

echo "== DMSF registration =="
plugin_list="$(docker compose exec -T redmine sh -lc \
  'export SECRET_KEY_BASE="$REDMINE_SECRET_KEY_BASE"; exec bundle exec rails runner -e production "puts Redmine::Plugin.registered_plugins.keys"')"
printf '%s\n' "$plugin_list"
grep -qi 'DMSF\|redmine_dmsf' <<<"$plugin_list" || { echo >&2 "DMSF was not registered"; exit 1; }

echo "== Core migration status =="
migration_status="$(docker compose exec -T redmine sh -lc \
  'export SECRET_KEY_BASE="$REDMINE_SECRET_KEY_BASE"; exec bundle exec rake db:migrate:status RAILS_ENV=production')"
printf '%s\n' "$migration_status"
if grep -Eq '^[[:space:]]*down[[:space:]]' <<<"$migration_status"; then
  echo >&2 "Pending core migrations found"
  exit 1
fi

echo "== Attachment-volume persistence across Redmine recreation =="
marker=".deployment-check-$(date -u +%s)"
cleanup() { docker compose exec -T redmine rm -f "/usr/src/redmine/files/$marker" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker compose exec -T redmine sh -c "printf persistent > '/usr/src/redmine/files/$marker'"
docker compose up -d --force-recreate --no-deps redmine
for _ in {1..60}; do
  if docker compose exec -T redmine wget -q -O /dev/null http://127.0.0.1:3000/login >/dev/null 2>&1; then break; fi
  sleep 2
done
docker compose exec -T redmine test -f "/usr/src/redmine/files/$marker"
cleanup
trap - EXIT
docker compose restart nginx
"$ROOT_DIR/scripts/healthcheck.sh" --wait

echo "Automated deployment verification passed. Complete the browser workflow/RBAC checks in docs/DMSF.md."

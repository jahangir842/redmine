#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
wait_mode=0
[[ "${1:-}" == "--wait" ]] && wait_mode=1

command -v docker >/dev/null 2>&1 || { echo >&2 "docker is required"; exit 1; }
[[ -f .env ]] || { echo >&2 "Missing .env"; exit 1; }

echo "== Docker service status =="
docker compose ps

check_all() {
  docker compose exec -T postgres sh -c 'pg_isready -U "$REDMINE_DB_USERNAME" -d "$REDMINE_DB_DATABASE"' >/dev/null 2>&1 &&
  docker compose exec -T redmine wget -q -O /dev/null http://127.0.0.1:3000/login >/dev/null 2>&1 &&
  docker compose exec -T nginx wget -q -O /dev/null http://127.0.0.1:8080/login >/dev/null 2>&1
}

if (( wait_mode )); then
  for _ in {1..60}; do check_all && break; sleep 2; done
fi

failed=0
printf '\n== PostgreSQL readiness ==\n'
if docker compose exec -T postgres sh -c 'pg_isready -U "$REDMINE_DB_USERNAME" -d "$REDMINE_DB_DATABASE"'; then echo "OK"; else failed=1; fi

printf '\n== Redmine application HTTP ==\n'
if docker compose exec -T redmine wget -S -q -O /dev/null http://127.0.0.1:3000/login 2>&1; then echo "OK"; else failed=1; fi

printf '\n== Nginx proxy HTTP ==\n'
if docker compose exec -T nginx wget -S -q -O /dev/null http://127.0.0.1:8080/login 2>&1; then echo "OK"; else failed=1; fi

printf '\n== Docker disk usage ==\n'
docker system df

exit "$failed"

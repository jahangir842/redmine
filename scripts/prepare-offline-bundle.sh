#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo >&2 "Missing .env"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo >&2 "docker is required"; exit 1; }

timestamp="$(date -u +%Y-%m-%d_%H%M%S)"
output_dir="${1:-$ROOT_DIR/offline-bundles/$timestamp}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
chmod 700 "$output_dir"

echo "Pulling pinned upstream images and building the custom Redmine image..."
docker compose pull postgres nginx
docker compose build --pull redmine

mapfile -t images < <(docker compose config --images | sort -u)
((${#images[@]} >= 3)) || { echo >&2 "Expected at least three images"; exit 1; }

echo "Saving images..."
docker save --output "$output_dir/redmine-offline-images.tar" "${images[@]}"

echo "Archiving deployment source (without secrets, backups, or Git history)..."
tar -czf "$output_dir/redmine-deployment-source.tar.gz" \
  --exclude='.git' --exclude='.env' --exclude='backups/*' --exclude='offline-bundles' \
  --exclude='*.key' --exclude='*.pem' .

{
  printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'images=\n'
  for image in "${images[@]}"; do
    printf '  %s %s\n' "$image" "$(docker image inspect --format '{{.Id}}' "$image")"
  done
} > "$output_dir/manifest.txt"

(cd "$output_dir" && sha256sum redmine-offline-images.tar redmine-deployment-source.tar.gz manifest.txt > checksums.sha256)
echo "Offline bundle ready: $output_dir"

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -ne 2 ]]; then
  echo >&2 "Usage: $0 SOURCE_POSTGRES_CUSTOM_DUMP SOURCE_FILES_TAR_GZ"
  exit 2
fi
[[ -f .env ]] || { echo >&2 "Missing .env"; exit 1; }
grep -Eq '^MIGRATION_MODE=true$' .env || {
  echo >&2 "Refusing to run: set MIGRATION_MODE=true only in a disposable migration copy."
  exit 1
}

source_dump="$(realpath "$1")"
source_files="$(realpath "$2")"
[[ -f "$source_dump" && -f "$source_files" ]] || { echo >&2 "Source artifacts not found"; exit 1; }

staging_dir="$ROOT_DIR/backups/migration_$(date -u +%Y-%m-%d_%H%M%S)"
mkdir -m 700 "$staging_dir"
cp --no-clobber "$source_dump" "$staging_dir/redmine.dump"
cp --no-clobber "$source_files" "$staging_dir/redmine-files.tar.gz"
{
  printf 'source_redmine=4.2.5-stable\n'
  printf 'purpose=temporary migration validation only\n'
  printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$staging_dir/metadata.txt"
(cd "$staging_dir" && sha256sum redmine.dump redmine-files.tar.gz metadata.txt > checksums.sha256)

echo "This imports Redmine 4.2.5 artifacts into the configured DISPOSABLE stack."
read -r -p "Type MIGRATE-TEST to continue: " answer
[[ "$answer" == MIGRATE-TEST ]] || { echo "Migration test cancelled."; exit 1; }

"$ROOT_DIR/scripts/restore.sh" --yes "$staging_dir"
echo "Migration mechanics completed. Follow every validation and plugin-inventory step in docs/MIGRATION.md."

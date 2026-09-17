#!/bin/sh
set -eu

: "${REDMINE_DB_DATABASE:?missing REDMINE_DB_DATABASE}"
: "${REDMINE_DB_USERNAME:?missing REDMINE_DB_USERNAME}"
: "${REDMINE_DB_PASSWORD:?missing REDMINE_DB_PASSWORD}"

case "$REDMINE_DB_DATABASE:$REDMINE_DB_USERNAME" in
  *[!a-zA-Z0-9_-]*) echo >&2 "Database and role names may contain only letters, digits, underscore, and hyphen"; exit 1 ;;
esac

psql --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=app_user="$REDMINE_DB_USERNAME" --set=app_password="$REDMINE_DB_PASSWORD" <<-'SQL'
	CREATE ROLE :"app_user" LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
SQL

createdb --username "$POSTGRES_USER" --owner "$REDMINE_DB_USERNAME" --encoding UTF8 "$REDMINE_DB_DATABASE"

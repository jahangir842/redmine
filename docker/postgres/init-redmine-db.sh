#!/bin/sh
set -eu

: "${REDMINE_DB_DATABASE:?missing REDMINE_DB_DATABASE}"
: "${REDMINE_DB_USERNAME:?missing REDMINE_DB_USERNAME}"
: "${REDMINE_DB_PASSWORD:?missing REDMINE_DB_PASSWORD}"

case "$REDMINE_DB_DATABASE:$REDMINE_DB_USERNAME" in
  *[!a-zA-Z0-9_-]*) echo >&2 "Database and role names may contain only letters, digits, underscore, and hyphen"; exit 1 ;;
esac

psql --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=app_db="$REDMINE_DB_DATABASE" \
  --set=app_user="$REDMINE_DB_USERNAME" \
  --set=app_password="$REDMINE_DB_PASSWORD" <<-'SQL'
	SELECT format('CREATE ROLE %I', :'app_user')
	WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user')
	\gexec

	ALTER ROLE :"app_user"
	  WITH LOGIN PASSWORD :'app_password'
	  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;

	SELECT format(
	  'CREATE DATABASE %I OWNER %I ENCODING %L',
	  :'app_db', :'app_user', 'UTF8'
	)
	WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'app_db')
	\gexec

	ALTER DATABASE :"app_db" OWNER TO :"app_user";
SQL

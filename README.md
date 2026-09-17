# Production Redmine + DMSF

A Docker Compose deployment for Redmine 6.1.4 (Ruby 3.4.10 / Rails 7.2.3.2), DMSF 4.1.3, PostgreSQL 16.15, and Nginx 1.30.5. It is designed for ordinary project management and controlled QMS/SOP documents, with reproducible plugin installation, backups, disaster recovery, migration testing, and offline deployment.

The latest Redmine release is not used blindly: Redmine 7.0.1 is newer, but DMSF 4.1.3 only declares Redmine 6 compatibility. Redmine 6.1.4 is the newest supported 6.x release and is therefore the newest evidenced-compatible choice. See [DMSF compatibility](docs/DMSF.md).

## Requirements

- Linux host with Docker Engine 24+ and Docker Compose v2
- 2 CPU, 4 GiB RAM, and storage sized for the database, attachments, and backups
- Bash, `openssl`, `sha256sum`, and `tar`
- Internet access only while pulling/building, or a prepared offline bundle

## Architecture

```text
Client / upstream TLS proxy
          |
          v  host port 8080 by default
        Nginx
          |
          v  frontend network
       Redmine + DMSF
          |
          v  internal backend network
      PostgreSQL
```

Only Nginx publishes a host port. PostgreSQL has no host port and its Docker network is marked internal. Only the database data and `/usr/src/redmine/files` are persisted; application/plugin code remains in the image.

## First installation

```bash
cp .env.example .env
openssl rand -base64 36   # use for each database password
openssl rand -hex 64      # use for REDMINE_SECRET_KEY_BASE
chmod 600 .env
# edit .env and replace every CHANGE_ME value
docker compose --env-file .env config
docker compose build redmine
docker compose up -d postgres
docker compose run --rm redmine bundle exec rake db:migrate RAILS_ENV=production
docker compose run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
docker compose up -d
./scripts/healthcheck.sh
```

Open `http://127.0.0.1:8080` (or the configured bind address/port). The initial Redmine credentials are `admin` / `admin`; change the password immediately, set the canonical host/protocol under Administration, and configure SMTP before production use.

The explicit commands above run core and plugin migrations before starting the complete stack. Normal container starts do not run migrations.

## Configuration

`.env` controls the bind address/port, canonical hostname, separate database administrator/application credentials, Rails secret, and local image name. `compose.yml` controls services and volumes; Nginx is configured in `docker/nginx/nginx.conf`. Keep `.env` mode 0600 and never commit it. See [Installation and upgrade](docs/INSTALLATION.md) and [Security](docs/SECURITY.md).

## Build, start, stop, and logs

```bash
docker compose build redmine
docker compose up -d
docker compose down              # preserves named volumes
docker compose restart
docker compose logs -f --tail=200
docker compose ps
./scripts/healthcheck.sh
./scripts/verify-deployment.sh   # versions, migrations, DMSF, persistence
```

Never use `docker compose down -v` unless intentionally destroying all database and attachment data.

## Database and plugin migrations

```bash
docker compose run --rm redmine bundle exec rake db:migrate RAILS_ENV=production
docker compose run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Run migrations first on a restored test copy and take a verified backup before production schema changes.

## Backup and restore

```bash
./scripts/backup.sh
./scripts/restore.sh backups/2026-09-17_120000
```

Restore is destructive to the configured destination and requires typed confirmation. See [Backup and restore](docs/BACKUP_RESTORE.md).

## DMSF

Log in as an administrator and open **Administration → Plugins**. `DMSF 4.1.3` must be listed. Then enable the **DMSF** module in a test project and configure its role permissions. From the CLI:

```bash
docker compose exec redmine bundle exec rake redmine:plugins RAILS_ENV=production
```

Compatibility, optional full-text search, WebDAV, and acceptance tests are documented in [DMSF compatibility and operation](docs/DMSF.md).

## Migration from old Redmine

Export a logical database dump and the attachment files from the quiesced Redmine 4.2.5 system, then restore and migrate only in an isolated temporary copy. Inventory and replace plugins with target-compatible releases; never copy old plugin code or Podman volumes. Follow [Migration from Redmine 4.2.5](docs/MIGRATION.md).

## Offline deployment

On an Internet-connected build host run `./scripts/prepare-offline-bundle.sh`, transfer and verify the resulting image/source archives, then use `docker load` on the isolated host. Follow [Offline deployment](docs/OFFLINE_DEPLOYMENT.md).

## Upgrade procedure

Re-check Redmine/DMSF compatibility, restore the latest backup into a disposable environment, rebuild pinned images, run core then plugin migrations, execute `./scripts/verify-deployment.sh` and browser workflow tests, and only then schedule production maintenance. See [Installation and upgrade](docs/INSTALLATION.md).

## Documentation

- [Installation and upgrade](docs/INSTALLATION.md)
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [Migration from Redmine 4.2.5](docs/MIGRATION.md)
- [DMSF compatibility and operation](docs/DMSF.md)
- [Offline deployment](docs/OFFLINE_DEPLOYMENT.md)
- [Security](docs/SECURITY.md)
- [QMS/SOP design](docs/QMS_DESIGN.md)

## Troubleshooting

- `docker compose config` reports a missing variable: populate every required `.env` value.
- PostgreSQL reports password authentication failure: the named volume was probably initialized with older credentials (or before the database-init script existed). Environment changes never rewrite roles in an existing PostgreSQL volume. For a brand-new installation with no data to retain, inspect the targeted volumes with `docker compose config --volumes`, then deliberately reset them with `docker compose down -v` and repeat the first-install commands. Never do this after real data exists.
- Redmine reports pending migrations: run the two migration commands above, then `docker compose restart`.
- DMSF is missing: rebuild the image and inspect `docker compose exec redmine bundle check` and the plugin list command above.
- Proxy returns 502/503: wait for the Redmine health check, then run `./scripts/healthcheck.sh` and `docker compose logs`.
- Upload is rejected: Nginx defaults to 100 MiB; coordinate changes to `client_max_body_size` with Redmine's attachment limit.

Before production, complete the manual checklist in [Installation](docs/INSTALLATION.md), perform a full backup/restore drill, test migration on an isolated copy, validate RBAC/workflows, configure TLS/SMTP, and establish monitoring and patch review.

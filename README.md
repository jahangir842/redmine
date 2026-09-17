# Production Redmine + DMSF

A Docker Compose deployment for Redmine 6.1.4 (Ruby 3.4.10 / Rails 7.2.3.2), DMSF 4.1.3, PostgreSQL 16.15, and Nginx 1.30.5. It is designed for ordinary project management and controlled QMS/SOP documents, with reproducible plugin installation, backups, disaster recovery, migration testing, and offline deployment.

The latest Redmine release is not used blindly: Redmine 7.0.1 is newer, but DMSF 4.1.3 only declares Redmine 6 compatibility. Redmine 6.1.4 is the newest supported 6.x release and is therefore the newest evidenced-compatible choice. See [DMSF compatibility](docs/DMSF.md).

## Requirements

- Linux host with Docker Engine 24+ and Docker Compose v2
- 2 CPU, 4 GiB RAM, and storage sized for the database, attachments, and backups
- `make`, Bash, `openssl`, `sha256sum`, and `tar`
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
make install
make health
```

Open `http://127.0.0.1:8080` (or the configured bind address/port). The initial Redmine credentials are `admin` / `admin`; change the password immediately, set the canonical host/protocol under Administration, and configure SMTP before production use.

`make install` deliberately runs core and plugin migrations as explicit deployment steps before starting the complete stack. Normal container starts do not run migrations.

## Operations

```bash
make build              # build the immutable Redmine+DMSF image
make up                 # start an already-installed stack
make down               # stop/remove containers, preserve volumes
make restart
make logs
make status
make health
make verify             # versions, migrations, DMSF, container-recreate persistence
make migrate            # explicit Redmine core migration
make plugins-migrate    # explicit plugin migrations
make backup
make restore BACKUP=backups/2026-09-17_120000
make offline-bundle
```

Never use `docker compose down -v` unless intentionally destroying all database and attachment data.

## Verify DMSF

Log in as an administrator and open **Administration → Plugins**. `DMSF 4.1.3` must be listed. Then enable the **DMSF** module in a test project and configure its role permissions. From the CLI:

```bash
docker compose exec redmine bundle exec rake redmine:plugins RAILS_ENV=production
```

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
- PostgreSQL is unhealthy: inspect `docker compose logs postgres`; changing init credentials after the volume exists does not alter existing roles.
- Redmine reports pending migrations: run `make migrate` and `make plugins-migrate`, then `make restart`.
- DMSF is missing: rebuild the image and inspect `docker compose exec redmine bundle check` and the plugin list command above.
- Proxy returns 502/503: wait for the Redmine health check, then use `make health` and `make logs`.
- Upload is rejected: Nginx defaults to 100 MiB; coordinate changes to `client_max_body_size` with Redmine's attachment limit.

Before production, complete the manual checklist in [Installation](docs/INSTALLATION.md), perform a full backup/restore drill, test migration on an isolated copy, validate RBAC/workflows, configure TLS/SMTP, and establish monitoring and patch review.

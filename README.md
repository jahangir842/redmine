# Production Redmine with DMSF

This repository deploys a pinned Redmine stack using Docker Compose. It is
intended for project management, DMSF document management, and controlled
QMS/SOP use.

## Pinned versions

| Component | Version |
| --- | --- |
| Redmine | 6.1.4 |
| Ruby | 3.4.10 (from the Redmine image) |
| Rails | 7.2.3.2 (from Redmine) |
| DMSF | 4.1.3 |
| PostgreSQL | 16.15, Debian Bookworm image |
| Nginx | 1.30.5, Alpine 3.24 image |

The deployment never uses a `latest` image tag. The versions above describe
this tested deployment and do not update automatically. Re-check Redmine and
DMSF compatibility before changing either version. See
[DMSF compatibility](docs/DMSF.md).

## Architecture

```text
Browser / upstream TLS reverse proxy
                  |
                  v  127.0.0.1:8080 by default
                Nginx
                  |
                  v  frontend Docker network
            Redmine + DMSF
                  |
                  v  internal backend Docker network
              PostgreSQL
```

Only Nginx publishes a host port. PostgreSQL is not exposed on the host, and
the backend Docker network is internal. Named volumes persist:

- `postgres_data`: PostgreSQL database cluster
- `redmine_files`: Redmine attachments and DMSF documents

Application and plugin code remain immutable inside the custom image. The
whole `/usr/src/redmine` application directory is deliberately not mounted as
a volume.

## Requirements

Prepare a Linux host with:

- Docker Engine 24 or newer (https://docs.docker.com/engine/install/ubuntu/)
- Docker Compose v2 (`docker compose`, not legacy `docker-compose`)
- Git, Bash, OpenSSL, `sha256sum`, and `tar`
- At least 2 CPU cores and 4 GiB RAM
- Enough storage for the database, attachments, images, and backups
- Internet access during the initial image pull/build, or an offline bundle

Verify Docker before continuing:

```bash
docker version
docker compose version
docker run --rm hello-world
```

These instructions assume the current user can access Docker. If your host
requires root access, prefix Docker commands with `sudo` and run repository
scripts with `sudo`, as in `sudo ./scripts/healthcheck.sh`.

## Fresh installation on a new system

This section creates an empty Redmine installation. It does not import the old
Redmine 4.2.5 database. If the objective is to move or recover an existing
installation from a backup created by `scripts/backup.sh`, complete steps 1–3
to obtain and build the repository, then skip to
[Restore on another system](#restore-on-another-system). Do not initialize an
empty application schema first.

### 1. Obtain the repository

Clone the repository and enter it:

```bash
git clone <YOUR_REPOSITORY_URL> redmine
cd redmine
```

Alternatively, extract a trusted source archive. Ensure scripts remain
executable:

```bash
chmod 750 scripts/*.sh
```

Check that the expected files exist:

```bash
test -f compose.yml
test -f docker/redmine/Dockerfile
test -f docker/postgres/init-redmine-db.sh
test -f docker/nginx/nginx.conf
test -f .env.example
```

### 2. Create configuration and secrets

Create the private environment file:

```bash
cp .env.example .env
chmod 600 .env
```

Generate three independent values. Do not reuse a password:

```bash
openssl rand -base64 48   # REDMINE_DB_PASSWORD
openssl rand -base64 48   # POSTGRES_PASSWORD
openssl rand -hex 64      # REDMINE_SECRET_KEY_BASE
```

Edit `.env` and replace every `CHANGE_ME` value:

```bash
nano .env
```

At minimum, review these settings:

```dotenv
COMPOSE_PROJECT_NAME=redmine

REDMINE_BIND_ADDRESS=127.0.0.1
REDMINE_HOST=redmine.example.internal
REDMINE_PORT=8080

REDMINE_DB_DATABASE=redmine
REDMINE_DB_USERNAME=redmine
REDMINE_DB_PASSWORD=<random application database password>

POSTGRES_DB=postgres
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<different random PostgreSQL administrator password>

REDMINE_SECRET_KEY_BASE=<random 128-character hex value>
REDMINE_IMAGE=local/redmine-dmsf:6.1.4-dmsf4.1.3
MIGRATION_MODE=false
```

Important configuration rules:

- Keep `REDMINE_SECRET_KEY_BASE` permanently. Changing or losing it can
  invalidate sessions and encrypted application data.
- Keep `COMPOSE_PROJECT_NAME` stable. Docker uses it when naming the persistent
  volumes.
- Database and role names may contain only letters, digits, underscores, and
  hyphens.
- Keep `.env` private and never commit it. It is already excluded by
  `.gitignore`.
- Leave `REDMINE_BIND_ADDRESS=127.0.0.1` when another host reverse proxy will
  provide HTTPS. Use `0.0.0.0` only when LAN access to port 8080 is intended
  and protected by the host firewall.

Confirm there are no unresolved example values:

```bash
if grep -n 'CHANGE_ME' .env; then
  echo 'Replace every CHANGE_ME value before continuing'
  exit 1
fi
```

### 3. Validate and build

Render and validate the Compose configuration without printing `.env`:

```bash
docker compose config --quiet
```

Pull the third-party runtime images and build the custom Redmine image:

```bash
docker compose pull postgres nginx
docker compose build --pull redmine
```

The Redmine build downloads the pinned DMSF release, verifies its SHA-256
checksum, and installs all Ruby dependencies into the image. The upstream
entrypoint checks dependencies at startup, but Bundler is forced into local,
frozen mode: it cannot contact Rubygems or change the locked dependency set.

Confirm the expected image is present:

```bash
docker image inspect local/redmine-dmsf:6.1.4-dmsf4.1.3 >/dev/null
```

### 4. Initialize PostgreSQL

Start only PostgreSQL and wait for its authenticated health check:

```bash
docker compose up -d --wait --wait-timeout 120 postgres
```

On the first start, `docker/postgres/init-redmine-db.sh` creates the dedicated
Redmine role and database. Verify that the application credentials work:

```bash
docker compose exec postgres sh -ec \
  'PGPASSWORD="$REDMINE_DB_PASSWORD" psql \
    --host=127.0.0.1 \
    --username="$REDMINE_DB_USERNAME" \
    --dbname="$REDMINE_DB_DATABASE" \
    --tuples-only \
    --command="select current_user, current_database()"'
```

Expected result:

```text
 redmine | redmine
```

If PostgreSQL is unhealthy, inspect it before doing anything destructive:

```bash
docker compose ps
docker compose logs --tail=200 postgres
```

### 5. Run database migrations

Core and plugin migrations are explicit deployment operations. They are not
run while building the image or during normal container startup:

```bash
docker compose run --rm redmine \
  bundle exec rake db:migrate RAILS_ENV=production

docker compose run --rm redmine \
  bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

The asset-related warning output produced while Rails loads DMSF does not by
itself mean that a migration failed. The command must finish with exit status
zero. Check it immediately if necessary:

```bash
echo $?
```

### 6. Start and verify the complete stack

```bash
docker compose up -d --wait --wait-timeout 180
docker compose ps
./scripts/healthcheck.sh --wait
```

All three services should show `healthy`. Run the deeper deployment check:

```bash
./scripts/verify-deployment.sh
```

This verifies runtime versions, database migrations, DMSF registration, HTTP
health, and attachment persistence across a Redmine container recreation.
It also restarts Nginx after the recreation so that its upstream connection is
refreshed.

Open the configured endpoint. With the example local binding it is:

```text
http://127.0.0.1:8080
```

The initial Redmine credentials are:

```text
Username: admin
Password: admin
```

Change the administrator password immediately.

### 7. Complete first-login configuration

Before production use:

1. Change the default administrator password.
2. Open **Administration → Settings → General** and set the host name and path.
3. Select HTTPS as the protocol once TLS termination is configured.
4. Disable self-registration unless it is intentionally required.
5. Configure SMTP and test outgoing mail.
6. Set the attachment size limit to agree with Nginx's 100 MiB limit.
7. Open **Administration → Plugins** and confirm DMSF 4.1.3 is listed.
8. Create a test project and enable **DMSF** under **Project settings → Modules**.
9. Configure DMSF permissions under **Administration → Roles and permissions**.
10. Perform the DMSF and QMS acceptance tests in [docs/DMSF.md](docs/DMSF.md)
    and [docs/QMS_DESIGN.md](docs/QMS_DESIGN.md).

## Normal operation

```bash
# Start or apply Compose changes
docker compose up -d

# Stop containers while preserving all named volumes
docker compose down

# Restart services
docker compose restart

# Inspect status and health
docker compose ps
./scripts/healthcheck.sh

# Follow all logs
docker compose logs --tail=200 --follow

# Follow one service
docker compose logs --tail=200 --follow redmine
```

Never run `docker compose down -v` on an installation containing data. The
`-v` option deletes both the PostgreSQL and attachment volumes.

## Verify DMSF

List registered plugins:

```bash
docker compose exec redmine \
  bundle exec rake redmine:plugins RAILS_ENV=production
```

The output must include `redmine_dmsf` version 4.1.3. Also verify it through
**Administration → Plugins**, enable it in a test project, upload a document,
create a new version, and confirm its history and permissions.

## Optional free Agile board

Redmine Agile is not currently included in this repository image. If required,
use the free **Redmine Agile Light** package that explicitly supports Redmine
6.1. Do not copy it manually into a running container because it will disappear
on recreation.

The safe installation model is:

1. Download a pinned Light release from the vendor.
2. Record and verify its SHA-256 checksum.
3. Exclude the downloaded ZIP from Git.
4. Copy and extract it as `plugins/redmine_agile` in the Dockerfile.
5. Run `bundle install` during the image build, after both DMSF and Agile are
   present.
6. Build a newly tagged custom image.
7. Take a backup.
8. Run the plugin migration explicitly:

```bash
docker compose run --rm redmine \
  bundle exec rake redmine:plugins:migrate \
  NAME=redmine_agile RAILS_ENV=production
```

9. Recreate Redmine and Nginx, then enable **Agile** under the project's
   **Settings → Modules** page.

Keep the downloaded package in the controlled deployment material for offline
rebuilds, but do not commit it unless its distribution terms explicitly permit
that. Test plugin upgrades on a restored non-production copy first.

## Backup

Create a consistent database and attachment backup:

```bash
./scripts/backup.sh
```

The script briefly stops Nginx and Redmine, creates a PostgreSQL custom-format
dump and attachment archive, writes version metadata, calculates SHA-256
checksums, and restarts the services that were previously running.

A backup resembles:

```text
backups/2026-09-17_120000/
├── checksums.sha256
├── metadata.txt
├── redmine.dump
└── redmine-files.tar.gz
```

Copy backups to encrypted storage outside this Docker host and test restoration
regularly. A backup remaining only on the application host is not sufficient
for disaster recovery. See [Backup and restore](docs/BACKUP_RESTORE.md).

Each backup directory is one indivisible recovery point: keep its database
dump, attachment archive, metadata, and checksum file together. Verify it
before and after transferring it:

```bash
cd backups/YYYY-MM-DD_HHMMSS
sha256sum --check --strict checksums.sha256
```

The backup does **not** contain `.env`, TLS certificates, SMTP/identity-provider
credentials, an upstream reverse-proxy configuration, or Docker images. Protect
those separately. In particular, retain `REDMINE_SECRET_KEY_BASE` in a secure
credential store; do not rely on the application host as its only copy.

### Schedule backups with cron

Schedule the backup as the same unprivileged Linux user that can already run
`docker compose` (in this installation, `ubuntu`). Do not use root's crontab.
First create a private location for the lock and log:

```bash
mkdir -p /home/ubuntu/.local/state/redmine-backup
chmod 700 /home/ubuntu/.local/state/redmine-backup
```

Open that user's crontab:

```bash
crontab -e
```

Add the following entries. This runs a backup every day at 02:00 in the
server's local time. `flock` prevents a second backup from starting if the
previous one is still running:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""

0 2 * * * /usr/bin/flock -n /home/ubuntu/.local/state/redmine-backup/backup.lock /home/ubuntu/projects/redmine/scripts/backup.sh >> /home/ubuntu/.local/state/redmine-backup/backup.log 2>&1
```

Replace `/home/ubuntu/projects/redmine` if the repository is installed
elsewhere. The cron service must be enabled, and the scheduled user must be
able to run `docker compose` without `sudo`:

```bash
sudo systemctl enable --now cron
docker compose ps
crontab -l
```

After the first scheduled run, inspect the log and verify the newest recovery
point:

```bash
tail -n 100 /home/ubuntu/.local/state/redmine-backup/backup.log
latest="$(find /home/ubuntu/projects/redmine/backups -mindepth 1 -maxdepth 1 \
  -type d -name '20??-??-??_??????' -printf '%f\n' | sort | tail -1)"
(cd "/home/ubuntu/projects/redmine/backups/$latest" && \
  sha256sum --check --strict checksums.sha256)
```

The backup causes a short Redmine interruption while the application and proxy
are stopped for consistency, so choose a quiet time. Monitor the log or arrange
cron mail rather than assuming a scheduled job succeeded.

Local retention may be added only after backups are copied to independent,
encrypted storage and those copies are verified. For example, the following
separate entry deletes only timestamp-named local recovery points older than 30
days:

```cron
15 3 * * * /usr/bin/find /home/ubuntu/projects/redmine/backups -mindepth 1 -maxdepth 1 -type d -name '20??-??-??_??????' -mtime +30 -exec /usr/bin/rm -rf -- {} +
```

Test a restore periodically; checksum verification alone does not prove that a
backup meets the recovery requirements.

## Restore on another system

Backups produced by this current PostgreSQL installation can be restored
directly; the old MariaDB-to-PostgreSQL conversion does not need to be repeated.
To move or recover the current installation:

1. Install Docker and obtain the same repository revision used to create the
   backup.
2. Copy the original `.env` securely, or create a new one from `.env.example`.
   Preserve the original `REDMINE_SECRET_KEY_BASE`. On a genuinely fresh
   destination, new database passwords are allowed because PostgreSQL will
   create the roles with those new passwords before importing the dump. Host,
   bind-address, and port settings may also be adapted for the new server.
3. Keep `COMPOSE_PROJECT_NAME` stable after the first start; changing it later
   selects different Docker volumes.
4. Build or load the exact pinned images.
5. Copy one complete backup directory into `backups/` without unpacking either
   archive, and verify `checksums.sha256`.
6. Confirm that this is a fresh destination. Never delete or overwrite an
   existing destination without first taking its own backup.
7. Validate Compose and start only PostgreSQL:

```bash
docker compose config --quiet
docker compose build redmine
docker compose up -d --wait --wait-timeout 120 postgres
```

8. Restore the chosen backup. Do not run the empty-install migration commands
   first; the restore script imports the database and then applies all required
   core and plugin migrations itself:

```bash
./scripts/restore.sh backups/YYYY-MM-DD_HHMMSS
```

The restore command validates checksums and requires typing `RESTORE` before it
replaces the configured destination database and attachments. Afterward:

```bash
./scripts/healthcheck.sh --wait
./scripts/verify-deployment.sh
```

9. Test login, projects, issues, permissions, representative attachments, DMSF,
   SMTP, and external integrations in the browser.
10. Once accepted, create a fresh backup on the destination and copy it to
    independent encrypted storage:

```bash
./scripts/backup.sh
```

Do not delete the source system or the pre-move backup until browser-level
validation and stakeholder acceptance are complete.

## Database and plugin migrations

Use these commands after a tested application or plugin upgrade:

```bash
docker compose run --rm redmine \
  bundle exec rake db:migrate RAILS_ENV=production

docker compose run --rm redmine \
  bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Always back up first and test migrations against a restored copy. Never point a
migration test at the old production Redmine database.

## Upgrade procedure

1. Read the target Redmine and plugin release notes.
2. Confirm Redmine, Ruby, Rails, DMSF, and all other plugin compatibility.
3. Pin every new image and plugin release; update checksums.
4. Create and verify a production backup.
5. Restore it into a disposable Compose project and rehearse the upgrade.
6. Build the new image; never install plugins in a running container.
7. Stop user traffic and run core migrations followed by plugin migrations.
8. Recreate Redmine and Nginx.
9. Run `scripts/verify-deployment.sh` and browser/DMSF workflow tests.
10. Retain the pre-upgrade backup until acceptance is complete.

See [Installation and upgrade](docs/INSTALLATION.md).

## Migration from Redmine 4.2.5

Do not copy Podman volumes or old plugin source into this deployment. The
future migration uses:

```text
old Redmine 4.2.5 logical database dump + attachment files
                            |
                            v
              isolated temporary migration copy
                            |
                            v
               core and compatible plugin migrations
                            |
                            v
                    functional validation
```

Inventory old plugins, install only compatible target releases, rehearse the
entire operation, and preserve the source system unchanged. Follow
[Migration from Redmine 4.2.5](docs/MIGRATION.md).

## Offline deployment

On an Internet-connected machine, prepare an image and source bundle:

```bash
./scripts/prepare-offline-bundle.sh
```

Transfer the resulting bundle and checksums to the isolated server, verify it,
and load its Docker image archive with `docker load`. After the images and
configuration are present, startup and normal operation do not require
Internet access. The restore script also checks that every image is present and
uses Compose's `--pull never` policy before altering data. Follow
[Offline deployment](docs/OFFLINE_DEPLOYMENT.md).

## Troubleshooting

### Compose reports a missing variable

Populate every required `.env` value, then run:

```bash
docker compose config --quiet
```

### PostgreSQL says role `redmine` does not exist

First wait for initialization and inspect the complete log:

```bash
docker compose up -d --wait --wait-timeout 120 postgres
docker compose logs --tail=300 postgres
```

On an empty installation only, the idempotent bootstrap can be run again:

```bash
docker compose exec postgres /docker-entrypoint-initdb.d/10-redmine-db.sh
docker compose up -d --wait --wait-timeout 120 postgres
```

Do not use that command as an unreviewed password-rotation procedure on an
existing production system.

### PostgreSQL password authentication fails

Changing `.env` does not modify credentials already stored in a PostgreSQL
volume. Restore the original matching `.env` or perform a deliberate database
password rotation. For a genuinely new and disposable installation with no
data, you may start again with:

```bash
docker compose down -v
docker compose up -d --wait --wait-timeout 120 postgres
```

This deletes all database and attachment data. Never use it after real data has
been created.

### Redmine is unhealthy

```bash
docker compose ps
docker compose logs --tail=300 postgres redmine
docker compose exec redmine wget -S -O /dev/null http://127.0.0.1:3000/login
```

If migrations are pending, run both migration commands and recreate Redmine.

### Login redirects to the wrong port

This repository preserves the incoming host and port using Nginx's
`X-Forwarded-Host` header. Ensure the current `docker/nginx/nginx.conf` is in
use, then recreate both services:

```bash
docker compose up -d --force-recreate redmine nginx
```

Also configure Redmine's canonical hostname and protocol to match the URL used
by clients.

### Nginx returns 502 or 503

Wait for Redmine to become healthy, then restart Nginx so that it reconnects to
the current Redmine container address:

```bash
./scripts/healthcheck.sh --wait
docker compose restart nginx
docker compose logs --tail=200 nginx redmine
```

### DMSF does not appear

```bash
docker compose exec redmine bundle check
docker compose exec redmine \
  bundle exec rake redmine:plugins RAILS_ENV=production
docker compose logs --tail=300 redmine
```

If the custom image was not built on this host, build it and recreate Redmine.

### Upload is rejected

Nginx permits requests up to 100 MiB. Coordinate any change to
`client_max_body_size` with Redmine's attachment-size setting and available
storage.

## Documentation

- [Installation and upgrade](docs/INSTALLATION.md)
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [Migration from Redmine 4.2.5](docs/MIGRATION.md)
- [DMSF compatibility and operation](docs/DMSF.md)
- [Offline deployment](docs/OFFLINE_DEPLOYMENT.md)
- [Security](docs/SECURITY.md)
- [QMS/SOP design](docs/QMS_DESIGN.md)

Before production use, complete a backup/restore drill, configure TLS and SMTP,
validate roles and workflows, test DMSF document versioning and permissions,
establish monitoring, and document the maintenance and patch-review process.

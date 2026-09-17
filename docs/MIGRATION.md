# Migration from Redmine 4.2.5

This is a future, rehearsed migration—not a production cutover procedure to run now. Do not connect this repository to the old production database, mount Podman volumes, or copy old plugin code.

```text
OLD PODMAN REDMINE 4.2.5
       |  logical database dump + attachment archive + inventory
       v
ISOLATED TEMPORARY MIGRATION COPY
       |  compatible plugin code + core/plugin DB migrations
       v
REDMINE 6.1.4 + DMSF 4.1.3
       |  functional, data, permission, audit validation
       v
SEPARATELY APPROVED PRODUCTION CUTOVER
```

## 1. Inventory without changing the source

Record the exact Redmine/Ruby/Rails/database versions, database engine/encoding, attachment path and size, project/user/issue/document counts, custom themes, SCM integrations, cron jobs, mail settings, and every plugin. On the old application, capture:

```bash
bundle exec rake about RAILS_ENV=production
bundle exec rake redmine:plugins RAILS_ENV=production
```

For each plugin:

```text
old plugin
  └─ supported stable release for Redmine 6.1?
       ├─ yes: install that reviewed version into a test image and migrate its data
       └─ no: remove/replace it, or design an explicit data conversion
```

Never copy Redmine 4.2 plugin directories into this image. Tables left by absent plugins may be harmless, but dependencies, patches, hooks, and data semantics must be assessed before core migration.

## 2. Export portable artifacts

Stop writes or place the old service in maintenance mode. Use its database-native logical backup tool and separately archive the contents of Redmine's `files` directory, preserving relative paths. Compute checksums and retain an untouched copy.

The supplied migration helper accepts a **PostgreSQL custom-format dump** and a `.tar.gz` whose root is the contents of `files/`. It does not read Podman volumes. If the source database is MySQL/MariaDB or another engine, do not feed that dump to `pg_restore`: first test a deliberate cross-engine conversion using a supported migration tool and reconcile schema/data types, or upgrade on the original engine and perform a separately validated conversion to PostgreSQL. Cross-engine conversion is its own project.

Also test that the destination `pg_restore` version can read the old dump. A newer PostgreSQL client normally reads older custom dumps; record both versions.

## 3. Build an isolated migration copy

Use a separate host or unique Compose project, volumes, secrets, hostname, mail sink/disabled outbound email, and no production integrations. Set `MIGRATION_MODE=true` only there. Never reuse production volume names.

```bash
cp .env.example .env
# set unique secrets, COMPOSE_PROJECT_NAME=redmine-migration, MIGRATION_MODE=true
docker compose build redmine
docker compose up -d --wait postgres
./scripts/migrate-old-redmine.sh /staging/redmine.dump /staging/redmine-files.tar.gz
```

The helper copies artifacts with `--no-clobber`, creates checksums, invokes the guarded restore, runs core and DMSF migrations, and starts the target. It never contacts the old server.

Core and plugin migration commands, when run manually, are:

```bash
docker compose run --rm redmine bundle exec rake db:migrate RAILS_ENV=production
docker compose run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

These commands change the copied database. Never run them against the source or production until a reviewed cutover.

## Direct versus staged upgrade

Redmine's official upgrade procedure supports installing a new release, copying configuration/files, and running cumulative `db:migrate`; it does not prescribe mandatory intermediate releases for a source as recent as 4.2.5. Start by testing a direct **4.2.5 → 6.1.4** migration on the isolated copy. Do not invent intermediate steps merely because the version jump is large.

If direct migration fails, preserve logs and identify the exact failing core/plugin migration. First remove incompatible plugin code and install target-compatible releases. Only if a reproduced Redmine core or runtime incompatibility requires it, test the shortest evidence-based sequence, for example 4.2.5 → latest 5.1.x → 6.1.4, using a separate compatible runtime/image at each step. Note that 5.1 is now unsupported, so it is a temporary migration tool only, never an exposed production stage. Back up after every successful stage. Choose any intermediate version from the error, official release/upgrade notes, and plugin requirements—not this example alone.

## Validation and reconciliation

Automate before/after counts and sample checks where possible:

- projects, users/statuses, roles/memberships, issues/journals, time entries, wikis, repositories, custom fields, workflows;
- attachment count/bytes and representative SHA-256 checksums;
- DMSF folders, documents, every revision, workflow decisions, locks, permissions, audit/activity records;
- non-ASCII text, dates/time zones, links, email templates, API clients, authentication, and scheduled jobs;
- new create/edit/upload/approve/revise operations in a test project.

Document discrepancies and acceptance sign-off. Disable outbound email/webhooks during rehearsals to avoid contacting real users.

## Future cutover outline

After multiple successful timed rehearsals: approve downtime and rollback criteria; freeze source writes; take fresh verified logical/files backups; import into a clean destination; run the rehearsed migrations; validate critical counts/checksums and smoke tests; then switch the upstream proxy/DNS. Keep the old system read-only and preserve the pre-cutover backup until formal acceptance. This repository does not perform that cutover.

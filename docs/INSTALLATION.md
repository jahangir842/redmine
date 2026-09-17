# Installation and upgrades

## Selected stack

| Component | Pinned version | Basis |
|---|---:|---|
| Redmine | 6.1.4 (`redmine:6.1.4-bookworm`) | Newest maintained Redmine series accepted by DMSF 4.1.3 |
| Ruby | 3.4.10 in the current official Redmine 6.1.4 image | Official 6.1 image runtime; supported by Redmine 6.1 |
| Rails | 7.2.3.2 | Exact Redmine 6.1.4 dependency |
| DMSF | 4.1.3, tag `v4.1.3`, commit `8cf3f72e...` | Latest stable DMSF release; declares Redmine >= 6.0 |
| PostgreSQL | 16.15 (`postgres:16.15-bookworm`) | Current patched, mature supported major; comfortably meets Redmine's PostgreSQL requirement |
| Nginx | 1.30.5 (`nginx:1.30.5-alpine3.24`) | Current stable Nginx release |

Image tags pin application/OS release versions but registry tags can technically be republished. Record the image IDs/digests in each release manifest and offline bundle. Organizations requiring byte-for-byte supply-chain pinning should replace tags with reviewed multi-architecture digest references for their deployment architecture.

## Install

1. Copy `.env.example` to `.env`, generate unique secrets, and set mode `0600`.
2. Keep `REDMINE_BIND_ADDRESS=127.0.0.1` when another reverse proxy fronts this stack. Use a specific LAN address only when direct LAN HTTP is intended.
3. Validate with `docker compose --env-file .env config`. Confirm no PostgreSQL `ports:` entry is present.
4. Build and install with explicit Docker Compose commands:

   ```bash
   docker compose build redmine
   docker compose up -d postgres
   docker compose run --rm redmine bundle exec rake db:migrate RAILS_ENV=production
   docker compose run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   docker compose up -d
   ```

5. Run `./scripts/healthcheck.sh` and `./scripts/verify-deployment.sh`, then log in. The verification script deliberately recreates the Redmine container to prove attachment-volume persistence. Change the default administrator password immediately.
6. Configure Administration settings, SMTP, canonical host/protocol, time zone, attachment size, roles, and projects.

The first PostgreSQL initialization creates a dedicated non-superuser application role and database. `POSTGRES_USER` is only the cluster administrator. Changing `.env` later does not rotate credentials inside an existing database; use `ALTER ROLE`, then update `.env` in a controlled maintenance window.

## HTTPS and upstream proxy

The included Nginx intentionally serves internal HTTP only and accepts `X-Forwarded-Proto` from a trusted upstream. Terminate TLS at a managed host Nginx, load balancer, Cloudflare tunnel/proxy, or internal reverse proxy, then forward to `127.0.0.1:${REDMINE_PORT}`. The upstream should:

- overwrite, not append, client-supplied forwarded headers;
- set `Host`, `X-Forwarded-For`, and `X-Forwarded-Proto=https`;
- apply HSTS only after HTTPS is verified for the whole hostname;
- use certificates managed outside this repository.

Never expose the Compose frontend broadly while also trusting unfiltered forwarded headers.

## Upgrade procedure

1. Read Redmine and plugin release notes and re-check compatibility; never change only the Redmine base tag.
2. Take and verify a backup. Restore it into a disposable test stack.
3. Update pinned versions/checksums and rebuild. Do not reuse old plugin source.
4. In the test stack run the core `db:migrate` command, then `redmine:plugins:migrate`, using the explicit Docker Compose commands above.
5. Start it, inspect logs, and execute functional, DMSF workflow, permissions, upload/download, and backup/restore tests.
6. Schedule production downtime; take a fresh quiesced backup.
7. Deploy the reviewed image, run the same explicit migrations, start, and validate.
8. Retain the previous images and backup until acceptance. Database schema rollback generally requires restoring the pre-upgrade backup, not reversing migrations.

Patch upgrades within PostgreSQL 16 use the new image with the existing volume. A PostgreSQL major upgrade requires a separate tested `pg_dump`/`pg_restore` or `pg_upgrade` procedure; do not merely change the major image tag.

## Production acceptance checklist

- Login, logout, password reset, email, and 2FA policy tested
- DMSF visible; approval, locking, revision history, and access checks tested
- Attachment survives `docker compose up -d --force-recreate redmine`
- Containers become healthy after host and Docker restart
- Restore drill completed on a separate stack and checksums retained
- TLS grade, DNS, time synchronization, log retention, monitoring, disk alerts, and backup copy/off-site retention configured
- Host firewall exposes only the intended proxy port; Docker socket access is restricted
- Resource capacity/load tests and update/vulnerability review completed

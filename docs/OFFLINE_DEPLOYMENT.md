# Offline deployment

Prepare the bundle on an Internet-connected Docker host with the same CPU architecture as the offline server (or explicitly build/pull every required platform).

```bash
cp .env.example .env
# configure non-production bundle-time values; real secrets are not archived
./scripts/prepare-offline-bundle.sh
```

The script pulls pinned PostgreSQL/Nginx images, builds the custom Redmine+DMSF image (including gems), and creates:

```text
offline-bundles/YYYY-MM-DD_HHMMSS/
├── checksums.sha256
├── manifest.txt
├── redmine-deployment-source.tar.gz
└── redmine-offline-images.tar
```

The source archive excludes `.env`, Git history, backups, keys, and prior bundles. Review it before transfer. Transfer the directory through the approved media/process and verify SHA-256 on the offline host:

```bash
sha256sum --check checksums.sha256
docker load --input redmine-offline-images.tar
mkdir redmine-deployment
tar -xzf redmine-deployment-source.tar.gz -C redmine-deployment
cd redmine-deployment
cp .env.example .env
# generate/edit unique production secrets locally; chmod 600 .env
docker compose config
docker compose up -d --wait postgres
docker compose run --rm redmine bundle exec rake db:migrate RAILS_ENV=production
docker compose run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
docker compose up -d
./scripts/healthcheck.sh
```

Compose will use the loaded custom image, but may choose to build if it is missing. Confirm `docker image inspect local/redmine-dmsf:6.1.4-dmsf4.1.3` succeeds before starting. Do not pull or rebuild on the offline host.

Maintain a software-bill/release record with bundle checksums, image IDs, architecture, build date, source commit, approver, vulnerability review, and deployment date. Offline does not mean unpatched: periodically prepare a newly reviewed bundle, rehearse restore/upgrade, and transfer it through the same controlled process.

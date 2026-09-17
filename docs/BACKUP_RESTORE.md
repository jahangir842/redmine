# Backup and restore

Redmine is only recoverable when the database and `/usr/src/redmine/files` are backed up together. DMSF documents are stored beneath that files tree.

## Create a backup

```bash
./scripts/backup.sh
```

The script stops Nginx and Redmine briefly, leaving PostgreSQL running, so application writes cannot make the database and files inconsistent. It creates a mode-0700 UTC-stamped directory containing:

```text
backups/2026-09-17_120000/
├── checksums.sha256
├── metadata.txt
├── redmine-files.tar.gz
└── redmine.dump
```

The database uses PostgreSQL custom format (`pg_dump -Fc`). The script restarts only application/proxy services that were running when it began. A local backup is not a disaster-recovery strategy by itself: encrypt and copy it to access-controlled independent storage, apply a documented retention policy, monitor failures, and periodically test restore.

## Restore drill

Prefer a separate Compose project/host. Configure a fresh `.env`, start PostgreSQL, then:

```bash
./scripts/restore.sh /secure/path/2026-09-17_120000
```

The script validates required files, SHA-256 checksums, and archive paths; displays the target; requires the exact word `RESTORE`; stops the application; drops/recreates only the configured application database; replaces attachments; applies target core/plugin migrations; starts the stack; and runs health checks.

Restore is destructive to the configured destination. It does not delete the backup. Never aim it at production merely to “test” a backup. `--yes` exists only for the already-confirmed migration wrapper and controlled automation.

## Validation after restore

- Compare project, issue, user, and DMSF document counts with recorded expectations.
- Download representative old/new attachments and compare known checksums.
- Inspect DMSF revisions, workflow/audit history, permissions, and locked states.
- Test login, email links, and create/update in a test project.
- Review `docker compose logs` for migration and application errors.

The database dump does not include PostgreSQL cluster-wide roles. The destination bootstrap creates the Redmine role before restore. TLS certificates, `.env`, external SMTP/identity configuration, host proxy configuration, monitoring, and off-host backup policies must be protected/recreated separately.

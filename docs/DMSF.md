# DMSF compatibility and operation

## Compatibility decision

The selected pair is **Redmine 6.1.4 + DMSF 4.1.3**.

DMSF tag `v4.1.3` identifies itself as version 4.1.3 and declares `requires_redmine version_or_higher: '6.0.0'`. Its README says it is compatible with Redmine 6; the 4.0.0 release introduced Redmine 6 support, 4.1.0 added Puma 6 support, and 4.1.3 includes a Redmine 6.0.5 WebDAV fix. Redmine 6.1.4 uses Ruby 3.4 and Rails 7.2.3.2. DMSF's CI evidence covers Redmine's 6.0 stable branch and Ruby 3.2, while its declared lower bound permits 6.1; this repository must therefore complete the runtime acceptance tests below before production.

Redmine 7.0.1 is intentionally not selected. Although it is the newest Redmine stable release, DMSF 4.1.3 predates it and does not declare Redmine 7/Rails 8.1 compatibility. Re-evaluate when DMSF publishes a stable tagged release with that support.

The plugin archive is pinned to tag `v4.1.3` and SHA-256 `69f84f69945b1f7e5e7987dc996663052e08ace1f48a962e8e23ed69b3687425`. It is not cloned from `master`.

## Image and dependencies

The Dockerfile downloads the checked archive, installs it under `plugins/redmine_dmsf`, and executes `bundle install` during build. Runtime startup executes `bundle check` through the upstream entrypoint but does not need Internet access because required gems are already in the image.

DMSF's optional `xapian` Bundler group is excluded to keep the production image focused. Metadata/file-name search, versioning, workflow, locking, and auditing remain available; full-text indexing inside document bodies is not. If required, design and test a separate image variant with Xapian/Omega and file-format extractors, scheduled indexing, resource limits, and additional patching responsibilities.

The WebDAV middleware is included, but WebDAV is disabled by default in DMSF settings. Enable it only after reviewing authentication, TLS, client behavior, and audit requirements.

During asset compilation, DMSF 4.1.3 can emit warnings for file-type PNG paths referenced by its CSS but absent from the tagged release archive. These are upstream cosmetic warnings and do not cause the database migration failure. Confirm the DMSF page layout/icons during browser acceptance testing; do not treat warnings as proof that migrations succeeded.

## Migration and verification commands

```bash
docker compose run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
docker compose exec redmine bundle exec rake redmine:plugins RAILS_ENV=production
docker compose exec redmine bundle check
```

Then verify in **Administration → Plugins** and a non-production project:

1. DMSF 4.1.3 appears and the module can be enabled.
2. Each RBAC role sees only permitted folders/actions.
3. Upload, download, revision creation, lock/unlock, and delete/trash behavior work.
4. A two-step review/approval workflow records actors and timestamps.
5. Approved content cannot be silently overwritten by an author; change produces a new revision.
6. Activity/audit history remains visible to the auditor role.
7. Files remain after a Redmine container recreation and after backup/restore.
8. Email notifications and links use the public HTTPS hostname.

Do not enable automatic plugin migrations at container startup. Schema changes are explicit deployment steps and must first run against a restored copy.

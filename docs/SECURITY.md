# Security notes

## Implemented controls

- Only Nginx publishes a host port; PostgreSQL is isolated on an internal Docker network.
- PostgreSQL bootstrap administration and the non-superuser Redmine role use separate passwords.
- Secrets are required through `.env`, which is ignored by Git; examples contain no usable default password.
- Redmine, DMSF, PostgreSQL, Nginx, Debian/Alpine variants, and the DMSF archive checksum are pinned.
- Containers are unprivileged in the Docker sense (`privileged` and host networking are absent) and use `no-new-privileges`; Nginx drops all capabilities and has a read-only root filesystem.
- Logs rotate locally. Application code is immutable; only database and files volumes persist.
- Nginx applies conservative response headers and a request-size limit. TLS terminates at a separately managed upstream.
- Backup scripts use restrictive umask/directories and checksums.

The official Redmine and PostgreSQL entrypoints initially run as root to initialize/fix named-volume ownership, then drop privileges to their fixed service users. Forcing a container-wide non-root user or dropping all capabilities breaks reliable first-volume initialization. This deployment preserves upstream behavior instead of adding a fragile permission workaround. Protect Docker/root access because it can read environment variables, volumes, and secrets.

## Required operational controls

- Set `.env` mode 0600, restrict its backups, and use a secrets manager where available. Docker Compose environment variables are visible to Docker administrators.
- Bind to loopback behind a trusted TLS proxy; firewall the host; never publish port 5432.
- Replace the default administrator password, apply least-privilege Redmine/DMSF roles, review anonymous/self-registration settings, and enforce account/2FA policy.
- Configure trusted SMTP, backups, monitoring, host patching, image vulnerability scanning, time synchronization, storage alerts, and incident procedures.
- Treat attachments as potentially hostile. Apply organizational malware scanning/content policies outside this minimal stack if required.
- Review WebDAV separately before enabling it. Disable public links unless their risk and expiry controls are accepted.
- Keep production, restore drills, and migration rehearsals on separate projects/hosts and networks.

HSTS is not set by the internal HTTP Nginx. Add it at the TLS terminator only after confirming the hostname is permanently HTTPS. A Content-Security-Policy is also not imposed here because Redmine/plugin behavior must first be inventoried and tested; deploy a report-only policy before enforcement.

## Secret and credential rotation

Rotating `REDMINE_SECRET_KEY_BASE` invalidates sessions and may affect encrypted application data; plan and test it. Changing database values in `.env` does not change an initialized PostgreSQL role. Rotate with a controlled `ALTER ROLE`, update `.env`, recreate Redmine, test, then securely update escrowed credentials.

Never commit `.env`, dumps, attachment archives, TLS private keys, image archives, or production configuration exports. Run a secret scanner in CI and review `git diff --cached` before every release.

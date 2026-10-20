# Git integration

Redmine browses a local Git mirror to display source files, branches, commits,
and diffs, and associate commits with issues. GitHub remains the remote Git
host. This guide documents the working Docker setup for this repository.

Run host commands as `ubuntu` from `/home/ubuntu/projects/redmine`. Replace
the GitHub URL and mirror name when connecting another repository. Docker
commands below use `sudo`; omit it if your user already has Docker access.

## 1. Create the mirror on the host

The host needs Git and an SSH key with read access to the GitHub repository.
For a private repository, a read-only deploy key can provide that access.

```bash
sudo mkdir -p /var/lib/redmine/repos
sudo chown ubuntu:ubuntu /var/lib/redmine/repos

git clone --mirror git@github.com:jahangir842/redmine.git \
  /var/lib/redmine/repos/myproject.git

git --git-dir=/var/lib/redmine/repos/myproject.git log -1 --oneline
```

Clone as `ubuntu`, without `sudo`, so Git uses that user's SSH configuration.
If the mirror already exists, skip the clone and update it using section 4.

## 2. Mount the mirror into Redmine

The `redmine` service in `compose.yml` includes this read-only bind mount:

```yaml
    volumes:
      - redmine_files:/usr/src/redmine/files
      - /var/lib/redmine/repos:/var/lib/redmine/repos:ro
```

The host path must exist before starting the container, including on a new
deployment. Repository updates run on the host; Redmine only needs read access
inside the container. SSH keys stay on the host.

After adding or changing the mount, apply the configuration:

```bash
sudo docker compose config --quiet
sudo docker compose up -d --no-deps redmine
```

Recreating Redmine briefly interrupts the application. Verify that the
application user can read a commit:

```bash
sudo docker compose exec --user redmine redmine \
  git --git-dir=/var/lib/redmine/repos/myproject.git log -1 --oneline
```

If Nginx returns 502 after the recreation, wait for Redmine to become healthy
and restart Nginx:

```bash
sudo docker compose ps
sudo docker compose restart nginx
```

## 3. Configure the project in Redmine

1. Under **Administration → Settings → Repositories**, ensure Git is enabled.
2. Open the project and enable **Repository** under **Settings → Modules**.
3. Open **Settings → Repositories → New repository** and select **Git**.
4. Set **Path to repository** (or **Path to .git directory**) to
   `/var/lib/redmine/repos/myproject.git`.
5. Save and open the project's **Repository** tab.

Enter the container's filesystem path, rather than the GitHub SSH or HTTPS URL.
Project roles also need permission to browse the repository and view changesets.

## 4. Keep the mirror updated

Run this as the host user that owns the mirror and has GitHub SSH access:

```bash
git -C /var/lib/redmine/repos/myproject.git remote update --prune
```

To fetch every five minutes, open that user's crontab with `crontab -e` and add:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

*/5 * * * * /usr/bin/flock -n /var/lib/redmine/repos/myproject.fetch.lock /usr/bin/git -C /var/lib/redmine/repos/myproject.git remote update --prune >> /var/lib/redmine/repos/myproject.fetch.log 2>&1
```

Confirm `cron` is running with `systemctl status cron`. Scheduled SSH access
must work without an interactive password or an interactive SSH agent. Check
`/var/lib/redmine/repos/myproject.fetch.log` after the first run and arrange log
rotation if you retain this schedule.

Fetching updates the Git mirror. Redmine imports changesets when the Repository
tab is opened if **Fetch commits automatically** is enabled in repository
settings. To import them explicitly after a fetch, run:

```bash
sudo docker compose exec --user redmine redmine \
  bundle exec rake redmine:fetch_changesets RAILS_ENV=production
```

## 5. Link commits to issues

Configure referencing and fixing keywords under
**Administration → Settings → Repositories**. For example, with `refs` and
`fixes` configured:

```text
Add deployment documentation, refs #123
Fix repository mount, fixes #123
```

Referencing keywords associate a commit with an issue. Fixing keywords can
also update the issue status and percentage done according to the configured
settings. Push the commit, update the mirror, and let Redmine import changesets.

## Add a new repository to another Redmine project

Once the initial setup works, reuse the existing directory mount. No Compose
change or container restart is needed for additional mirrors created under
`/var/lib/redmine/repos`.

The example below connects `OWNER/NEW_REPO` to another project. Replace those
placeholders and use a unique mirror directory name for each repository.

### 1. Create the new mirror

Run on the host as `ubuntu`, without `sudo`:

```bash
git clone --mirror git@github.com:OWNER/NEW_REPO.git \
  /var/lib/redmine/repos/new-repo.git
```

If you already made a regular working clone, you can instead create the mirror
from that clone and then point it at GitHub for future updates:

```bash
git clone --mirror --no-hardlinks /absolute/path/to/NEW_REPO \
  /var/lib/redmine/repos/new-repo.git

git -C /var/lib/redmine/repos/new-repo.git remote set-url origin \
  git@github.com:OWNER/NEW_REPO.git

git -C /var/lib/redmine/repos/new-repo.git remote update --prune
```

Choose one of these approaches. Keep your regular clone for development; use
the separate mirror for Redmine. Uncommitted working files are not included.

### 2. Verify access inside Docker

From `/home/ubuntu/projects/redmine`, run:

```bash
sudo docker compose exec --user redmine redmine \
  git --git-dir=/var/lib/redmine/repos/new-repo.git log -1 --oneline
```

For a repository with commits, this should print the latest commit. If it
fails, resolve the path or permissions error before adding it in Redmine.

### 3. Add it to the intended Redmine project

1. Open the **other project** that should use this repository.
2. Enable **Repository** under **Settings → Modules**, if necessary.
3. Open **Settings → Repositories → New repository**.
4. Select **Git** and enter `/var/lib/redmine/repos/new-repo.git` as the path.
5. If prompted, choose a unique repository identifier within that project.
   Select **Main repository** if this should be the project's default repository.
6. Save and open that project's **Repository** tab to check files and commits.

Adding a directory on the host makes it visible through the mount, but does
not register it automatically in Redmine. Repeat these UI steps for each
project/repository association.

### 4. Update the new repository

Fetch new commits on the host:

```bash
git -C /var/lib/redmine/repos/new-repo.git remote update --prune
```

For automatic updates, add a separate entry in `ubuntu`'s `crontab -e`, using
the cron environment described in section 4:

```cron
*/5 * * * * /usr/bin/flock -n /var/lib/redmine/repos/new-repo.fetch.lock /usr/bin/git -C /var/lib/redmine/repos/new-repo.git remote update --prune >> /var/lib/redmine/repos/new-repo.fetch.log 2>&1
```

Each mirror needs its own fetch schedule and the host user needs GitHub access
to each remote. Open the Repository tab after fetching, or use the explicit
changeset import command from section 4.

## Troubleshooting

### Cannot create leading directories

The host user cannot write under `/var/lib`. Create and assign the parent
directory using the commands in section 1, then clone without `sudo`.

### 404: The entry or revision was not found in the repository

In this deployment, the initial cause was a missing Docker bind mount. Check
the mount and run the application-user Git command from section 2. Also verify
that the path entered in Redmine matches the mount, that the repository has
commits, and that the selected branch or revision still exists.

### Permission denied or dubious ownership

Use the error from the application-user Git command to distinguish filesystem
permissions from Git ownership checks. For permissions, ensure the Redmine
user can traverse the parent directories and read the mirror; avoid making
private repositories readable by all host users. For a `safe.directory` error,
trust only the specific mirror path in persistent Git configuration visible to
the Redmine user, then recreate and verify the container. Avoid trusting `*`.

### New commits do not appear

Run the host update command, verify `git log -1` inside the container, and then
run the explicit changeset import. If fetching fails, check the host user's
GitHub SSH access and scheduled-job log.

## Backup and recovery

`scripts/backup.sh` backs up the database and attachments; it does not archive
`/var/lib/redmine/repos` or the host's SSH configuration. On another host,
recreate the mirror at the same path, restore its read permissions and bind
mount, and configure SSH access and the fetch schedule. Back up mirrors
separately if they contain history that cannot be recovered from the remote.

## References

- [Redmine repository documentation](https://www.redmine.org/projects/redmine/wiki/RedmineRepositories)
- [Redmine settings](https://www.redmine.org/projects/redmine/wiki/RedmineSettings)

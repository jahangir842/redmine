FROM redmine:6.1.4-bookworm

ARG DMSF_VERSION=4.1.3
ARG DMSF_SHA256=69f84f69945b1f7e5e7987dc996663052e08ace1f48a962e8e23ed69b3687425

LABEL org.opencontainers.image.title="Redmine with DMSF" \
      org.opencontainers.image.version="6.1.4-dmsf4.1.3" \
      org.opencontainers.image.description="Redmine 6.1.4 with pinned DMSF 4.1.3"

USER root
WORKDIR /usr/src/redmine

# Plugin code and every required gem are installed at image build time. The
# xapian group is optional and deliberately excluded; see docs/DMSF.md.
RUN set -eux; \
    wget -O /tmp/redmine_dmsf.tar.gz \
      "https://github.com/danmunn/redmine_dmsf/archive/refs/tags/v${DMSF_VERSION}.tar.gz"; \
    echo "${DMSF_SHA256}  /tmp/redmine_dmsf.tar.gz" | sha256sum -c -; \
    mkdir -p plugins/redmine_dmsf; \
    tar -xzf /tmp/redmine_dmsf.tar.gz --strip-components=1 -C plugins/redmine_dmsf; \
    rm /tmp/redmine_dmsf.tar.gz; \
    chown -R redmine:redmine plugins/redmine_dmsf; \
    grep -Fq "version '${DMSF_VERSION}'" plugins/redmine_dmsf/init.rb

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential; \
    gosu redmine bundle config --local without 'development test xapian'; \
    gosu redmine bundle install --jobs "$(nproc)"; \
    gosu redmine bundle check; \
    apt-get purge -y --auto-remove build-essential; \
    rm -rf /var/lib/apt/lists/* /home/redmine/.bundle/cache

COPY --chown=redmine:redmine docker/redmine/additional_environment.rb config/additional_environment.rb

# Keep the official entrypoint. It fixes named-volume ownership then drops to
# uid/gid 999. Only /usr/src/redmine/files is persisted by compose.

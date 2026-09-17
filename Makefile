COMPOSE := docker compose

.PHONY: install up down restart logs status build pull migrate plugins-migrate backup restore health verify offline-bundle config

install: build
	$(COMPOSE) up -d postgres
	$(COMPOSE) run --rm redmine bundle exec rake db:migrate RAILS_ENV=production
	$(COMPOSE) run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production
	$(COMPOSE) up -d

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f --tail=200

status:
	$(COMPOSE) ps

build:
	$(COMPOSE) build redmine

pull:
	$(COMPOSE) pull postgres nginx
	$(COMPOSE) build --pull redmine

migrate:
	$(COMPOSE) run --rm redmine bundle exec rake db:migrate RAILS_ENV=production

plugins-migrate:
	$(COMPOSE) run --rm redmine bundle exec rake redmine:plugins:migrate RAILS_ENV=production

backup:
	./scripts/backup.sh

restore:
	@test -n "$(BACKUP)" || (echo "Usage: make restore BACKUP=backups/YYYY-MM-DD_HHMMSS" >&2; exit 2)
	./scripts/restore.sh "$(BACKUP)"

health:
	./scripts/healthcheck.sh

verify:
	./scripts/verify-deployment.sh

offline-bundle:
	./scripts/prepare-offline-bundle.sh

config:
	$(COMPOSE) config

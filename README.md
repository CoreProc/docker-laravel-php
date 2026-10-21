# docker-laravel-php

Base PHP Docker images for CoreProc Laravel apps, published to Docker Hub as [`coreproc/laravel-php`](https://hub.docker.com/r/coreproc/laravel-php). Each image includes common PHP extensions, Composer, [Supercronic](https://github.com/aptible/supercronic) for cron jobs, and supervisor.

Release history: see [CHANGELOG.md](CHANGELOG.md) and the [GitHub releases](../../releases).

## Branch-per-variant model

**Each git branch is a separate image variant, and the branch name is the Docker tag.** This `main` branch holds no Dockerfile — switch to a variant branch to work on an image.

| Branch / Docker tag | Base image | Platforms |
|---|---|---|
| [`8.5-fpm-alpine`](../../tree/8.5-fpm-alpine) | `php:8.5-fpm-alpine` | amd64, arm64 |
| [`8.4-fpm-alpine`](../../tree/8.4-fpm-alpine) | `php:8.4-fpm-alpine` | amd64, arm64 |
| [`8.3-fpm-alpine`](../../tree/8.3-fpm-alpine) | `php:8.3-fpm-alpine3.20` | amd64, arm64 |
| [`8.5-frankenphp-alpine`](../../tree/8.5-frankenphp-alpine) | `dunglas/frankenphp:php8.5-alpine` | amd64, arm64 |
| [`8.4-frankenphp-alpine`](../../tree/8.4-frankenphp-alpine) | `dunglas/frankenphp:php8.4-alpine` | amd64, arm64 |
| [`8.3-frankenphp-alpine`](../../tree/8.3-frankenphp-alpine) | `dunglas/frankenphp:php8.3-alpine` | amd64, arm64 |

## What's inside

- PHP extensions: `gd`, `mysqli`, `pdo`, `pdo_mysql`, `bcmath`, `curl`, `opcache`, `mbstring`, `exif`, `pcntl`, `zip`, `redis`
- Composer 2
- [Supercronic](https://github.com/aptible/supercronic) at `/usr/local/bin/supercronic` (cron replacement for containers)
- supervisor
- nginx (`*-fpm-alpine` variants only; the FrankenPHP variants serve HTTP via FrankenPHP's built-in Caddy)
- `xdebug` and `pcov` are pre-installed via pecl but **not enabled** — enable them in dev images with `docker-php-ext-enable`

## Typical usage

Your application image builds on top of a variant and adds app-specific packages, extensions, and configuration:

```dockerfile
FROM coreproc/laravel-php:8.4-fpm-alpine

# Match www-data to the host user so bind-mounted files keep sane permissions.
ARG WEB_UID=1000
ARG WEB_GID=1000
RUN apk add --no-cache shadow \
    && usermod -u $WEB_UID www-data \
    && groupmod -g $WEB_GID www-data \
    && apk del shadow

# Add whatever your app needs on top of the base image.
RUN apk add --no-cache nodejs npm git

# Extra PHP extensions, e.g. PostgreSQL.
RUN apk add --no-cache postgresql-dev \
    && docker-php-ext-install pdo_pgsql pgsql

# Your own PHP / web server configuration.
# (nginx config applies to the *-fpm-alpine variants, which ship nginx.)
COPY docker/php.ini /usr/local/etc/php/php.ini
COPY docker/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY docker/nginx.conf /etc/nginx/nginx.conf

# xdebug and pcov are pre-installed but disabled; enable them for dev builds.
ARG XDEBUG_ENABLED=false
RUN if [ "$XDEBUG_ENABLED" = "true" ]; then \
    docker-php-ext-enable xdebug pcov; \
fi

WORKDIR /app
COPY --chown=www-data:www-data . .

COPY docker/entrypoint /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Run as the non-root user.
USER www-data
ENTRYPOINT ["entrypoint"]
```

On the FrankenPHP variants the pattern is the same, minus the nginx config; if you remap `www-data`'s UID, also `chown -R www-data:www-data /config /data/caddy` so Caddy can write its state.

Cron jobs run through Supercronic, typically as a supervisor program:

```ini
[program:cron]
command=supercronic /app/docker/crontab
```

## Building

On a variant branch:

```bash
# Build multi-arch (amd64 + arm64) and push to Docker Hub
make build-push

# Local test build
docker build -t laravel-php-test .
```

## Automation

Two scheduled workflows on `main` keep the published tags current:

- **Supercronic version check** (Mondays 16:00 UTC, or run by hand): when Supercronic has a new release, it updates each variant's pinned version and checksums, then builds and smoke-tests the image natively on amd64 and arm64. Variants that pass are committed straight to their branch. A variant that fails gets a pull request instead, and the run fails so the failure is noticed. A manual run also starts the rebuild below.
- **Build and push images** (Mondays 18:00 UTC, or run by hand for one variant): rebuilds every variant from its floating base tag, smoke-tests both arches, and only then moves the Docker Hub tag. It then scans each published tag with [Grype](https://github.com/anchore/grype) and keeps one issue per variant, labelled [`vulnerability-scan`](../../issues?q=label%3Avulnerability-scan), listing fixable high and critical findings. The issue closes itself once the tag scans clean. Findings never block publishing.

GitHub disables scheduled workflows in a public repository after 60 days without activity. Both workflows re-enable themselves and each other on every run, which resets that timer. If they are ever found disabled anyway, re-enable them on the Actions tab or with `gh workflow enable`.

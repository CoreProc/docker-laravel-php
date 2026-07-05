# docker-laravel-php

Base PHP Docker images for CoreProc Laravel apps, published to Docker Hub as [`coreproc/laravel-php`](https://hub.docker.com/r/coreproc/laravel-php). Each image includes common PHP extensions, Composer, [Supercronic](https://github.com/aptible/supercronic) for cron jobs, and supervisor.

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

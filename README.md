# docker-laravel-php

Base PHP Docker images for CoreProc Laravel apps, published to Docker Hub as [`coreproc/laravel-php`](https://hub.docker.com/r/coreproc/laravel-php). Each image includes common PHP extensions, Composer, [Supercronic](https://github.com/aptible/supercronic) for cron jobs, and supervisor.

## Branch-per-variant model

**Each git branch is a separate image variant, and the branch name is the Docker tag.** This `main` branch holds no Dockerfile — switch to a variant branch to work on an image.

| Branch / Docker tag | Base image | Platforms |
|---|---|---|
| [`8.4-fpm-alpine`](../../tree/8.4-fpm-alpine) | `php:8.4-fpm-alpine` | amd64, arm64 |
| [`8.3-fpm-alpine`](../../tree/8.3-fpm-alpine) | `php:8.3-fpm-alpine3.20` | amd64, arm64 |
| [`8.4-frankenphp-alpine`](../../tree/8.4-frankenphp-alpine) | `dunglas/frankenphp:php8.4-alpine` | amd64, arm64 |
| [`8.3-frankenphp-alpine`](../../tree/8.3-frankenphp-alpine) | `dunglas/frankenphp:php8.3-alpine` | amd64, arm64 |

## Usage

```dockerfile
FROM coreproc/laravel-php:8.4-fpm-alpine
```

## Building

On a variant branch:

```bash
# Build multi-arch (amd64 + arm64) and push to Docker Hub
make build-push

# Local test build
docker build -t laravel-php-test .
```

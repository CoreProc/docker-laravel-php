# Changelog

Notable changes to the [`coreproc/laravel-php`](https://hub.docker.com/r/coreproc/laravel-php) images, tracked per GitHub release. Releases are tagged `vYYYY.MM.DD[.N]` and may span multiple image variants; each entry lists the Docker tags it affects. History before the first release lives in the private archive repo (`docker-laravel-php-archive`).

## [v2026.07.06.1] — 2026-07-06

### Added

- New PHP 8.5 variants: `8.5-fpm-alpine` (from `php:8.5-fpm-alpine`) and `8.5-frankenphp-alpine` (from `dunglas/frankenphp:php8.5-alpine`), both `linux/amd64` + `linux/arm64`. Registered in the weekly rebuild and Supercronic auto-bump workflows.

### Changed

- On the 8.5 variants, `opcache` is no longer passed to `docker-php-ext-install`: PHP 8.5 builds OPcache statically, so it is present and loaded by default in the base image.

## [v2026.07.06] — 2026-07-06

Affects all variants: `8.3-fpm-alpine`, `8.3-frankenphp-alpine`, `8.4-fpm-alpine`, `8.4-frankenphp-alpine`.

### Changed

- Supercronic updated to v0.2.47 (previously v0.2.32; v0.2.33 on `8.4-frankenphp-alpine`).
- Supercronic is now installed per-architecture via the `TARGETARCH` build arg, with a pinned SHA1 checksum per arch. Previously the amd64 binary was installed unconditionally, so `linux/arm64` images shipped a cron binary that could not execute.

### Breaking

- Supercronic now lives only at `/usr/local/bin/supercronic`. The arch-suffixed path `/usr/local/bin/supercronic-linux-amd64` (and its symlink) no longer exists.

[v2026.07.06.1]: https://github.com/CoreProc/docker-laravel-php/releases/tag/v2026.07.06.1
[v2026.07.06]: https://github.com/CoreProc/docker-laravel-php/releases/tag/v2026.07.06

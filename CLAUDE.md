# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Base PHP Docker images for CoreProc Laravel apps, published to Docker Hub as `coreproc/laravel-php`. Each image contains PHP + common extensions, Composer, Supercronic (cron), and supervisor — downstream Laravel projects build on top of these.

## Branch-per-variant model (important)

**Each git branch is a separate image variant, and the branch name is the Docker tag.** There is no shared trunk for the Dockerfile — `main` holds only the landing README and the GitHub Actions automation. Active variant branches: `8.3-fpm-alpine`, `8.3-frankenphp-alpine`, `8.4-fpm-alpine`, `8.4-frankenphp-alpine`, `8.5-fpm-alpine`, `8.5-frankenphp-alpine`. Older variants (7.2–8.2) live only in the private archive repo `CoreProc/docker-laravel-php-archive`.

Consequences:

- Work on the branch matching the variant you're changing. A fix that applies to all variants (e.g. a Supercronic version bump) must be applied to each branch separately — check the other branches for how it was done there.
- To add a new PHP version: branch from the closest existing variant; update the `FROM` line in the Dockerfile, the tag in the Makefile's `build-push` target, and the README. Then on `main`: add the branch to `.github/workflows/build-images.yml` (the branch list in the detect job's `select` step + dispatch options), `.github/workflows/supercronic-bump.yml` (matrix), and the variant table in README.md.
- The two variant families differ only in the base image: `php:X.Y-fpm-alpine` vs `dunglas/frankenphp:phpX.Y-alpine`.

## Commands

```bash
# Build multi-arch (amd64 + arm64) and PUSH to Docker Hub — publishes immediately
make build-push

# Local test build without publishing
docker build -t laravel-php-test .
```

Preferred publishing path: the "Build and push images" workflow (Actions tab, or its daily cron, which rebuilds a variant only when its inputs changed) — it builds each arch on native runners and smoke-tests before the Docker Hub tag moves. `make build-push` publishes directly with no such gate. There are no tests or linters; verification is building the image.

## Dockerfile conventions

- Build-only packages go in the `.build-deps` virtual apk package and are removed in the final cleanup step (`apk del .build-deps`) to keep the image small.
- `xdebug` and `pcov` are installed via PIE (not pecl) but intentionally **not enabled** — downstream dev environments enable them.
- `gd-dev` is deliberately removed after the gd extension is built (`apk del gd-dev`) to drop libtiff CVEs from the final image — don't "clean up" that line.
- `RUN apk upgrade --no-cache` comes right after `FROM` so Alpine fixes to packages from the base image ship without waiting for upstream to rebuild it. Keep it before any `apk add`. The smoke test on `main` (`.github/scripts/smoke-test.sh`) loads every extension, which catches an upgrade that breaks a library under PHP; add new extensions there too.

## Releases

Cross-variant changes are published as GitHub releases tagged `vYYYY.MM.DD[.N]`, targeting a variant branch. When publishing a release, also add an entry to `CHANGELOG.md` on `main`.

## Recurring task: updating Supercronic

The `supercronic-bump.yml` workflow on `main` checks https://github.com/aptible/supercronic/releases daily, computes fresh per-arch SHA1 checksums, and smoke-tests the bump on both arches. A variant that passes is committed straight to its branch and the next daily build publishes it; a variant that fails gets a PR instead, which publishes with the next daily build once merged.

For a manual bump:

1. Find the latest release version and compute the SHA1 sum of each arch's
   binary yourself (`curl -fsSL <release-url> | sha1sum`) — the Supercronic
   README no longer lists per-binary sums. Sanity-check a downloaded binary
   with `./supercronic-linux-amd64 -version` before pinning.
2. In the Dockerfile, update `SUPERCRONIC_VERSION` and both per-arch checksums
   (`SUPERCRONIC_SHA1SUM_AMD64` and `SUPERCRONIC_SHA1SUM_ARM64` — the build is
   multi-arch, so the `TARGETARCH`-based install needs both).
3. Repeat on every active variant branch (each branch has its own Dockerfile),
   then publish each branch via the build workflow or `make build-push`.

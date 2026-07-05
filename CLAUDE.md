# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Base PHP Docker images for CoreProc Laravel apps, published to Docker Hub as `coreproc/laravel-php`. Each image contains PHP + common extensions, Composer, Supercronic (cron), and supervisor — downstream Laravel projects build on top of these.

## Branch-per-variant model (important)

**Each git branch is a separate image variant, and the branch name is the Docker tag.** There is no shared trunk for the Dockerfile — `main` is legacy/stale. Local branches: `8.3-fpm-alpine`, `8.3-frankenphp-alpine`, `8.4-fpm-alpine`, `8.4-frankenphp-alpine`; older variants (7.2–8.2) exist on the remote.

Consequences:

- Work on the branch matching the variant you're changing. A fix that applies to all variants (e.g. a Supercronic version bump) must be applied to each branch separately — check the other branches' history for how it was done there.
- To add a new PHP version: branch from the closest existing variant, update the `FROM` line in the Dockerfile, the tag in the Makefile's `build-push` target, and the README.
- The two variant families differ only in the base image: `php:X.Y-fpm-alpine` vs `dunglas/frankenphp:phpX.Y-alpine`.
- Branch READMEs can lag behind (e.g. an 8.4 branch README titled "PHP-FPM 8.2").

## Commands

```bash
# Build multi-arch (amd64 + arm64) and PUSH to Docker Hub — this publishes immediately, there is no CI
make build-push

# Local test build without publishing
docker build -t laravel-php-test .
```

The tag in the Makefile must match the branch name. There are no tests or linters; verification is building the image.

## Dockerfile conventions

- Build-only packages go in the `.build-deps` virtual apk package and are removed in the final cleanup step (`apk del .build-deps`) to keep the image small.
- `xdebug` and `pcov` are installed via pecl but intentionally **not enabled** — downstream dev environments enable them.
- `gd-dev` is deliberately removed after the gd extension is built (`apk del gd-dev`) to drop libtiff CVEs from the final image — don't "clean up" that line.

## Recurring task: updating Supercronic

Supercronic is updated from time to time based on new releases at
https://github.com/aptible/supercronic/releases. It is pinned in the Dockerfile
by version **and SHA1 checksum** — both must change together:

1. Find the latest release version and compute the SHA1 sum of each arch's
   binary yourself (`curl -fsSL <release-url> | sha1sum`) — the Supercronic
   README no longer lists per-binary sums. Sanity-check a downloaded binary
   with `./supercronic-linux-amd64 -version` before pinning.
2. In the Dockerfile, update `SUPERCRONIC_VERSION` and both per-arch checksums
   (`SUPERCRONIC_SHA1SUM_AMD64` and `SUPERCRONIC_SHA1SUM_ARM64` — the build is
   multi-arch, so the `TARGETARCH`-based install needs both). Branches not yet
   migrated to this pattern still use a single `SUPERCRONIC_URL` +
   `SUPERCRONIC_SHA1SUM` pair pointing at the amd64 binary.
3. Repeat on every active variant branch (each branch has its own Dockerfile —
   see the "Update supercronic" commits in past branch histories), then
   `make build-push` on each branch to publish.

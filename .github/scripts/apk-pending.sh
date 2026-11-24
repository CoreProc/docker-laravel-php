#!/usr/bin/env bash
# Print the Alpine packages an image could upgrade, one "name=new-version" per
# line, sorted. Usage: apk-pending.sh <image> [amd64|arm64]
#
# The build records this list in a label on the image it publishes: those are
# upgrades a rebuild does not apply (the Dockerfiles never run `apk upgrade`,
# so packages that come with the base image only move when upstream rebuilds
# it). The daily check compares against that label, so it rebuilds for a newly
# released package once instead of every day.
set -euo pipefail

docker run --rm --platform "linux/${2:-amd64}" "$1" sh -c \
  'apk update -q >/dev/null && apk upgrade --simulate --no-cache 2>&1' \
  | sed -nE 's/.*Upgrading ([^ ]+) \([^ ]+ -> ([^ )]+)\).*/\1=\2/p' \
  | sort -u

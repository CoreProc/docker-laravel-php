#!/usr/bin/env bash
# Decide which variants the daily build has to rebuild.
#
# Every published image carries two labels written by build-images.yml:
#   com.coreproc.laravel-php.inputs       what it was built from (see below)
#   com.coreproc.laravel-php.apk-pending  Alpine upgrades the build could not apply
# A variant is rebuilt when its current inputs differ from the label, when an
# Alpine package upgrade appears that is not in apk-pending, when the tag has
# no labels yet, or when FORCE=true.
#
# Inputs, one "key=value" token each:
#   revision=<sha>             the variant branch HEAD: any Dockerfile change,
#                              including Supercronic bumps and PIE pins
#   <image>=<digest>           every FROM and COPY --from image not pinned by
#                              digest: the PHP/FrankenPHP base and composer:2
#   <package>=<version>        newest stable Packagist release in the same major
#                              as each `pie install vendor/pkg:^X.Y`
#
# Env: BRANCHES (space-separated), FORCE, REPO (owner/name), IMAGE, PLAN_FILE.
# Writes to $GITHUB_OUTPUT: build, a JSON array of the branches to rebuild.
# Writes to $PLAN_FILE (if set) a JSON array of {branch, sha, inputs,
# contexts} for them, where contexts pins each image to the digest recorded in
# inputs (docker/build-push-action build-contexts). These details cannot be a
# job output: GitHub drops any job output that contains a value matching one
# of the workflow's secrets, and they did. Writes a table to
# $GITHUB_STEP_SUMMARY. Output and summary default to stdout for local runs.
#
# Only the linux/amd64 image is compared; arm64 is built from the same inputs.
# Any failed lookup stops the run, so a registry or Packagist outage fails the
# day's build loudly instead of reading as "no change".
set -euo pipefail
shopt -s inherit_errexit

: "${BRANCHES:?}" "${REPO:?}" "${IMAGE:=coreproc/laravel-php}" "${FORCE:=false}"
out=${GITHUB_OUTPUT:-/dev/stdout}
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
here=$(dirname "$0")
label=com.coreproc.laravel-php

# Image references in FROM and COPY --from, minus build stages (by name or
# number), scratch, ARG-built references, and references already pinned by
# digest (those change only with a commit).
image_refs() {
  awk '
    toupper($1) == "FROM" {
      for (i = 2; i <= NF && $i ~ /^--/; i++) ;
      r[$i]
      if (toupper($(i + 1)) == "AS") s[tolower($(i + 2))]
    }
    toupper($1) == "COPY" { for (i = 2; i <= NF; i++) if (sub(/^--from=/, "", $i)) r[$i] }
    END {
      for (x in r)
        if (!(tolower(x) in s) && x != "scratch" && x !~ /^[0-9]+$/ && x !~ /[$@]/) print x
    }' <<<"$1" | sort
}

# vendor/package[:constraint] arguments to `pie install`.
pie_packages() {
  grep -E '\bpie install\b' <<<"$1" \
    | grep -oE '(^|[[:space:]])[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(:[^[:space:]]+)?' \
    | sed 's/^[[:space:]]*//' | sort -u || true
}

# Newest stable version of a Packagist package, limited to the constraint's
# major version for a caret constraint (^6.3 -> 6.x).
packagist_latest() {
  local name=${1%%:*} major=''
  [[ $1 =~ :\^v?([0-9]+) ]] && major=${BASH_REMATCH[1]}
  curl -fsSL "https://repo.packagist.org/p2/${name}.json" \
    | jq -r --arg p "$name" '.packages[$p][].version' \
    | grep -E "^v?${major:-[0-9]+}(\.[0-9]+)*$" \
    | sort -V | tail -1
}

# Space-separated tokens in $2 that are not in $1.
added() {
  comm -13 <(tr ' ' '\n' <<<"$1" | sort) <(tr ' ' '\n' <<<"$2" | sort) | paste -sd ' ' -
}

# Why ${IMAGE}:$1 needs a rebuild for inputs $2; prints nothing if it does not.
reason() {
  local labels old_inputs old_pending pending
  [ "$FORCE" != true ] || { echo forced; return; }
  if ! labels=$(docker buildx imagetools inspect "${IMAGE}:$1" \
      --format '{{json (index .Image "linux/amd64").Config.Labels}}' 2>&1); then
    [[ $labels == *": not found"* ]] || { echo "$labels" >&2; return 1; }
    echo 'tag not published'
    return
  fi
  { read -r old_inputs; read -r old_pending; } < <(jq -r --arg l "$label" \
    '(. // {}) | .[$l + ".inputs"] // "", .[$l + ".apk-pending"] // ""' <<<"$labels")
  [ -n "$old_inputs" ] || { echo 'published image has no build labels'; return; }
  if [ "$old_inputs" != "$2" ]; then
    added "$old_inputs" "$2" | grep . || echo 'an input was removed'
    return
  fi
  pending=$("${here}/apk-pending.sh" "${IMAGE}:$1" | paste -sd ' ' -)
  added "$old_pending" "$pending" | sed -n 's/./apk: &/p'
}

# Run "${@:2}" once per key $1 and leave the result in $REPLY: the same base
# image, composer:2 and PIE packages recur across variants.
declare -A resolved
resolve() {
  [ -n "${resolved[$1]:-}" ] || resolved[$1]=$("${@:2}")
  REPLY=${resolved[$1]}
}

build='[]'
{
  echo '| Variant | Rebuild | Why |'
  echo '|---|---|---|'
} >>"$summary"

for b in $BRANCHES; do
  sha=$(gh api "repos/${REPO}/commits/${b}" --jq .sha)
  dockerfile=$(gh api -H 'Accept: application/vnd.github.raw' "repos/${REPO}/contents/Dockerfile?ref=${sha}")

  tokens=("revision=${sha}")
  contexts=''
  while read -r ref; do
    resolve "$ref" docker buildx imagetools inspect "$ref" --format '{{.Manifest.Digest}}'
    tokens+=("${ref}=${REPLY}")
    contexts+="${ref}=docker-image://${ref}@${REPLY}"$'\n'
  done < <(image_refs "$dockerfile")
  while read -r pkg; do
    resolve "$pkg" packagist_latest "$pkg"
    tokens+=("${pkg%%:*}=${REPLY}")
  done < <(pie_packages "$dockerfile")
  inputs="${tokens[*]}"

  why=$(reason "$b" "$inputs")
  if [ -n "$why" ]; then
    build=$(jq -c --arg b "$b" --arg sha "$sha" --arg i "$inputs" --arg c "$contexts" \
      '. + [{branch: $b, sha: $sha, inputs: $i, contexts: $c}]' <<<"$build")
    echo "| \`${b}\` | yes | ${why} |" >>"$summary"
  else
    echo "| \`${b}\` | no | unchanged |" >>"$summary"
  fi
done

echo "build=$(jq -c 'map(.branch)' <<<"$build")" >>"$out"
[ -z "${PLAN_FILE:-}" ] || echo "$build" >"$PLAN_FILE"

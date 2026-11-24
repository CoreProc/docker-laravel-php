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
# Env: BRANCHES (space-separated), FORCE, REPO (owner/name), IMAGE.
# Writes to $GITHUB_OUTPUT: build, a JSON array of {branch, sha, inputs} for
# the variants to rebuild. Writes a table to $GITHUB_STEP_SUMMARY. Both
# default to stdout for local runs.
set -euo pipefail
# A failed lookup inside $(...) must stop the run, not read as "no change".
shopt -s inherit_errexit

: "${BRANCHES:?}" "${REPO:?}" "${IMAGE:=coreproc/laravel-php}" "${FORCE:=false}"
out=${GITHUB_OUTPUT:-/dev/stdout}
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
here=$(dirname "$0")
label=com.coreproc.laravel-php

# Image references in FROM and COPY --from, minus build stage names and
# references already pinned by digest (those change only with a commit).
image_refs() {
  awk '
    toupper($1) == "FROM" {
      for (i = 2; i <= NF && $i ~ /^--/; i++) ;
      r[$i]
      if (toupper($(i + 1)) == "AS") s[$(i + 2)]
    }
    toupper($1) == "COPY" { for (i = 2; i <= NF; i++) if (sub(/^--from=/, "", $i)) r[$i] }
    END { for (x in r) if (!(x in s) && x !~ /@sha256:/) print x }' <<<"$1" | sort
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
  local labels old_inputs old_pending
  [ "$FORCE" != true ] || { echo forced; return; }
  labels=$(docker buildx imagetools inspect "${IMAGE}:$1" \
    --format '{{json (index .Image "linux/amd64").Config.Labels}}' 2>/dev/null) \
    || { echo 'tag not published'; return; }
  { read -r old_inputs; read -r old_pending; } < <(jq -r --arg l "$label" \
    '(. // {}) | .[$l + ".inputs"] // "", .[$l + ".apk-pending"] // ""' <<<"$labels")
  [ -n "$old_inputs" ] || { echo 'published image has no build labels'; return; }
  if [ "$old_inputs" != "$2" ]; then
    added "$old_inputs" "$2" | grep . || echo 'an input was removed'
    return
  fi
  added "$old_pending" "$("${here}/apk-pending.sh" "${IMAGE}:$1" | paste -sd ' ' -)" | sed -n 's/./apk: &/p'
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
  while read -r ref; do
    resolve "$ref" docker buildx imagetools inspect "$ref" --format '{{.Manifest.Digest}}'
    tokens+=("${ref}=${REPLY}")
  done < <(image_refs "$dockerfile")
  while read -r pkg; do
    resolve "$pkg" packagist_latest "$pkg"
    tokens+=("${pkg%%:*}=${REPLY}")
  done < <(pie_packages "$dockerfile")
  inputs="${tokens[*]}"

  why=$(reason "$b" "$inputs")
  if [ -n "$why" ]; then
    build=$(jq -c --arg b "$b" --arg sha "$sha" --arg i "$inputs" '. + [{branch: $b, sha: $sha, inputs: $i}]' <<<"$build")
    echo "| \`${b}\` | yes | ${why} |" >>"$summary"
  else
    echo "| \`${b}\` | no | unchanged |" >>"$summary"
  fi
done

echo "build=${build}" >>"$out"

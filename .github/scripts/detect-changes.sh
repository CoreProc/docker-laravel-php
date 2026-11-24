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
# Writes to $GITHUB_OUTPUT: build (JSON array of branches to rebuild) and
# inputs (JSON object branch -> {sha, inputs}). Writes a table to
# $GITHUB_STEP_SUMMARY. Both default to stdout for local runs.
set -euo pipefail

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
      print "ref " $i
      if (toupper($(i + 1)) == "AS") print "stage " $(i + 2)
    }
    toupper($1) == "COPY" {
      for (i = 2; i <= NF; i++) if ($i ~ /^--from=/) { sub(/^--from=/, "", $i); print "ref " $i }
    }' <<<"$1" \
  | awk '$1 == "stage" { s[$2] = 1; next } { r[$2] = 1 }
         END { for (x in r) if (!(x in s) && x !~ /@sha256:/) print x }' \
  | sort
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
  local name=${1%%:*} constraint major=''
  [[ $1 == *:* ]] && constraint=${1#*:} || constraint=''
  [[ $constraint =~ ^\^v?([0-9]+) ]] && major=${BASH_REMATCH[1]}
  curl -fsSL "https://repo.packagist.org/p2/${name}.json" \
    | jq -r --arg p "$name" '.packages[$p][].version' \
    | grep -E '^v?[0-9]+(\.[0-9]+)*$' \
    | { if [ -n "$major" ]; then grep -E "^v?${major}\." || true; else cat; fi; } \
    | sort -V | tail -1
}

build=()
inputs_json='{}'
{
  echo '| Variant | Rebuild | Why |'
  echo '|---|---|---|'
} >>"$summary"

for b in $BRANCHES; do
  sha=$(gh api "repos/${REPO}/commits/${b}" --jq .sha)
  dockerfile=$(gh api -H 'Accept: application/vnd.github.raw' "repos/${REPO}/contents/Dockerfile?ref=${sha}")

  tokens=("revision=${sha}")
  while read -r ref; do
    [ -n "$ref" ] || continue
    tokens+=("${ref}=$(docker buildx imagetools inspect "$ref" --format '{{.Manifest.Digest}}')")
  done < <(image_refs "$dockerfile")
  while read -r pkg; do
    [ -n "$pkg" ] || continue
    tokens+=("${pkg%%:*}=$(packagist_latest "$pkg")")
  done < <(pie_packages "$dockerfile")
  inputs="${tokens[*]}"
  inputs_json=$(jq -c --arg b "$b" --arg sha "$sha" --arg i "$inputs" '.[$b] = {sha: $sha, inputs: $i}' <<<"$inputs_json")

  why=''
  if [ "$FORCE" = true ]; then
    why='forced'
  elif ! labels=$(docker buildx imagetools inspect "${IMAGE}:${b}" \
      --format '{{json (index .Image "linux/amd64").Config.Labels}}' 2>/dev/null); then
    why='tag not published'
  else
    old_inputs=$(jq -r --arg k "${label}.inputs" '(. // {})[$k] // ""' <<<"$labels")
    if [ -z "$old_inputs" ]; then
      why='published image has no build labels'
    elif [ "$old_inputs" != "$inputs" ]; then
      why=$(comm -13 <(tr ' ' '\n' <<<"$old_inputs" | sort) <(tr ' ' '\n' <<<"$inputs" | sort) | paste -sd ' ' -)
      [ -n "$why" ] || why='an input was removed'
    else
      old_pending=$(jq -r --arg k "${label}.apk-pending" '(. // {})[$k] // ""' <<<"$labels")
      new_apk=$(comm -13 <(tr ' ' '\n' <<<"$old_pending" | sed '/^$/d' | sort) \
        <("${here}/apk-pending.sh" "${IMAGE}:${b}") | paste -sd ' ' -)
      [ -z "$new_apk" ] || why="apk: ${new_apk}"
    fi
  fi

  if [ -n "$why" ]; then
    build+=("$b")
    echo "| \`${b}\` | yes | ${why} |" >>"$summary"
  else
    echo "| \`${b}\` | no | unchanged |" >>"$summary"
  fi
done

echo "build=$(jq -cn '$ARGS.positional' --args "${build[@]}")" >>"$out"
echo "inputs=${inputs_json}" >>"$out"

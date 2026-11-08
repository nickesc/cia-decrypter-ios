#!/bin/bash
set -euo pipefail

tag="v$1"
if [[ -n "${REQUESTED_TAG:-}" && "$REQUESTED_TAG" != "$tag" ]]; then
  echo "Requested tag does not match the app version ($tag)." >&2
  exit 1
fi

tags="$(gh api "repos/$GITHUB_REPOSITORY/releases" --paginate --jq '.[].tag_name')"
if grep -Fxq -- "$tag" <<< "$tags"; then
  publish=false
  echo "Release $tag already exists; skipping."
else
  publish=true
  echo "Preparing release $tag."
fi

printf 'tag=%s\npublish=%s\n' "$tag" "$publish" >> "$GITHUB_OUTPUT"

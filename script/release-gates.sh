#!/usr/bin/env bash
# Shared by local release validation and publication. No credentials or bypass flags.

require_release_snapshot() {
  local expected_sha="$1" tree_status
  if [ "$(git rev-parse HEAD)" != "$expected_sha" ]; then
    echo "Release HEAD changed since the build started; refusing publication." >&2
    return 1
  fi
  if ! tree_status="$(git status --porcelain --untracked-files=normal)"; then
    echo "Could not inspect release working tree; refusing publication." >&2
    return 1
  fi
  if [ -n "$tree_status" ]; then
    echo "--publish requires a clean tracked and untracked working tree." >&2
    echo "Commit the release changes, or use a separate clean checkout; existing work is preserved." >&2
    return 1
  fi
}

# Results live outside the checkout and are written only after all checks pass.
require_release_ci() {
  local expected_sha="$1" result="${ALTILLO_VALIDATION_DIR:-$HOME/Library/Developer/BuildCache/altillo/ReleaseValidation}/$1/passed"
  if [ ! -f "$result" ] || [ "$(cat "$result")" != "$expected_sha" ]; then
    echo "Run script/validate-release.sh on $expected_sha before publishing." >&2
    return 1
  fi
  echo "    Local validation verified: $result"
}

require_release_tag() {
  local remote="$1" tag="$2" expected_sha="$3" refs tag_sha
  if ! refs="$(git ls-remote "$remote" "refs/tags/$tag" "refs/tags/$tag^{}")"; then
    echo "Could not verify remote release tag; refusing publication." >&2
    return 1
  fi
  # Prefer the peeled commit of an annotated tag; lightweight tags already name the commit.
  tag_sha="$(printf '%s\n' "$refs" | awk '$2 ~ /\^\{\}$/ { peeled=$1; next } { direct=$1 } END { print (peeled != "" ? peeled : direct) }')"
  if [ -n "$tag_sha" ] && [ "$tag_sha" != "$expected_sha" ]; then
    echo "Remote tag $tag identifies $tag_sha, not built commit $expected_sha." >&2
    return 1
  fi
}

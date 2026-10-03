#!/usr/bin/env bash
# Shared by local and GitHub Actions publication. No credentials or bypass flags.

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

require_release_ci() {
  local repo="$1" expected_sha="$2"
  local result ci_sha ci_status ci_conclusion ci_run_id extra
  command -v gh >/dev/null 2>&1 || { echo "--publish needs the gh CLI." >&2; return 1; }
  # Do not filter by success: a newer failing, cancelled or pending run must block publication.
  # Restrict to push/main: an unrelated PR run cannot authorize a public artifact.
  if ! result="$(gh run list --repo "$repo" --workflow ci.yml --branch main --event push \
    --commit "$expected_sha" --limit 1 --json headSha,status,conclusion,databaseId \
    --template '{{range .}}{{.headSha}} {{.status}} {{.conclusion}} {{.databaseId}}{{end}}')"; then
    echo "Could not verify CI for $expected_sha; refusing publication." >&2
    return 1
  fi
  read -r ci_sha ci_status ci_conclusion ci_run_id extra <<< "$result"
  if [ "$ci_sha" != "$expected_sha" ] || [ "$ci_status" != completed ] \
    || [ "$ci_conclusion" != success ] || ! [[ "$ci_run_id" =~ ^[0-9]+$ ]] \
    || [ -n "$extra" ] || [[ "$result" == *$'\n'* ]]; then
    echo "--publish requires the latest CI run on main to be completed/success for exact commit $expected_sha." >&2
    echo "Push that commit to main, wait for every CI job, then retry (no publication occurred)." >&2
    return 1
  fi
  echo "    CI verified: https://github.com/$repo/actions/runs/$ci_run_id ($expected_sha)"
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

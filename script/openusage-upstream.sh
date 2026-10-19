#!/usr/bin/env bash
set -euo pipefail

# Tracks upstream changes in openusage's provider code (https://github.com/robinebers/openusage, MIT) for the
# files Altillo's native AI-usage collectors (Packages/AltilloKit/Sources/AltilloUsage, AltilloCore) are adapted
# from. Reads script/openusage-upstream.json (provider -> upstream paths + last reviewed commit), and for each
# provider reports the commits and files that changed upstream since that commit. See docs/proveedores.md.
#
# Usage:
#   script/openusage-upstream.sh                        Report changes for every provider in the manifest.
#   script/openusage-upstream.sh <provider>              Report changes for one provider only.
#   script/openusage-upstream.sh --mark-reviewed <provider|all>
#                                                         Set the provider's (or every provider's)
#                                                         last_reviewed_sha to the current upstream HEAD.
#                                                         Does not print a report.
#
# Exit code: 0 when nothing changed upstream (or after --mark-reviewed), 10 when at least one tracked path
# changed, 1 on a usage or tooling error.
#
# Requires the GitHub CLI (`gh`) and `jq`. `gh` must be authenticated: `gh auth login` locally, or a
# GITHUB_TOKEN / GH_TOKEN environment variable in CI (gh picks these up automatically, no login step needed).

usage() {
  cat <<'EOF'
Usage:
  openusage-upstream.sh                                Report changes for every provider.
  openusage-upstream.sh <provider>                      Report changes for one provider.
  openusage-upstream.sh --mark-reviewed <provider|all>  Record the upstream HEAD as reviewed.

Exit code: 0 nothing changed, 10 something changed, 1 usage/tooling error.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="${OPENUSAGE_UPSTREAM_MANIFEST:-$script_dir/openusage-upstream.json}"

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required: https://cli.github.com"
command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -f "$manifest" ]] || die "manifest not found: $manifest"

repo="$(jq -r '.repo // empty' "$manifest")"
[[ -n "$repo" ]] || die "manifest is missing .repo: $manifest"

mark_reviewed=""
provider_filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mark-reviewed)
      [[ $# -ge 2 ]] || die "--mark-reviewed needs an argument (a provider name or 'all')"
      mark_reviewed="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "unknown flag: $1 (see --help)"
      ;;
    *)
      [[ -z "$provider_filter" ]] || die "only one provider can be given"
      provider_filter="$1"
      shift
      ;;
  esac
done

known_provider() {
  jq -e --arg p "$1" '.providers[$p] // empty' "$manifest" >/dev/null
}

current_head() {
  gh api "repos/$repo/commits/HEAD" -q '.sha' \
    || die "couldn't read $repo's current HEAD via the GitHub API (check gh auth status / network)"
}

# --- --mark-reviewed: update the manifest in place, no report. ---
if [[ -n "$mark_reviewed" ]]; then
  head_sha="$(current_head)"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT

  if [[ "$mark_reviewed" == "all" ]]; then
    jq --arg sha "$head_sha" \
      '.providers |= with_entries(.value.last_reviewed_sha = $sha)' \
      "$manifest" >"$tmp"
    updated="every provider"
  else
    known_provider "$mark_reviewed" || die "unknown provider: $mark_reviewed"
    jq --arg p "$mark_reviewed" --arg sha "$head_sha" \
      '.providers[$p].last_reviewed_sha = $sha' \
      "$manifest" >"$tmp"
    updated="$mark_reviewed"
  fi
  mv "$tmp" "$manifest"
  trap - EXIT
  echo "Marked $updated as reviewed at $repo@$head_sha."
  exit 0
fi

# --- Report mode ---
if [[ -n "$provider_filter" ]]; then
  known_provider "$provider_filter" || die "unknown provider: $provider_filter"
  providers="$provider_filter"
else
  providers="$(jq -r '.providers | keys[]' "$manifest")"
fi

head_sha="$(current_head)"
any_changes=0

while IFS= read -r provider; do
  [[ -n "$provider" ]] || continue

  label="$(jq -r --arg p "$provider" '.providers[$p].label' "$manifest")"
  base_sha="$(jq -r --arg p "$provider" '.providers[$p].last_reviewed_sha' "$manifest")"
  paths="$(jq -r --arg p "$provider" '.providers[$p].upstream_paths[]' "$manifest")"

  echo "## $label ($provider)"
  echo "Reviewed at $base_sha; upstream HEAD is $head_sha."

  if [[ "$base_sha" == "$head_sha" ]]; then
    echo "Up to date."
    echo
    continue
  fi

  # Compare commit membership, rather than dates: Git timestamps may be equal or out of
  # order, and the commits endpoint's `since` boundary includes the reviewed commit.
  comparison="$(gh api --method GET --paginate --slurp \
    "repos/$repo/compare/$base_sha...$head_sha" -f per_page=100)" \
    || die "couldn't compare $base_sha to $head_sha (check gh auth status / network and reviewed SHA)"
  jq -e 'length > 0 and all(.[]; .status == "ahead" or .status == "identical")' \
    <<<"$comparison" >/dev/null \
    || die "reviewed commit $base_sha is not an ancestor of upstream HEAD; review the rewritten history manually"
  new_shas="$(jq '[.[].commits[].sha] | unique' <<<"$comparison")"

  provider_changed=0
  commit_lines=""

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    # Fetch every page. Filter by the exact comparison range so old commits and
    # timestamp skew cannot produce false positives or hide a newer commit.
    commits_json="$(gh api --method GET --paginate --slurp "repos/$repo/commits" \
      -f path="$path" -f sha="$head_sha" -f per_page=100)" \
      || die "couldn't read commit history for $path (check gh auth status / network)"
    commits_json="$(jq -e --argjson shas "$new_shas" \
      '[.[][] | select(.sha as $sha | $shas | index($sha))]' <<<"$commits_json")" \
      || die "invalid commit history for $path"
    [[ "$(jq 'length' <<<"$commits_json")" -gt 0 ]] || continue

    provider_changed=1
    echo "- changed: $path (https://github.com/$repo/commits/$head_sha/$path)"
    lines="$(jq -r '.[] | [.commit.committer.date, .sha, (.commit.message | split("\n")[0]), ("https://github.com/" + $repo + "/commit/" + .sha)] | join("  ")' \
      --arg repo "$repo" <<<"$commits_json")"
    commit_lines="${commit_lines}${lines}
"
  done <<<"$paths"

  if [[ "$provider_changed" -eq 1 ]]; then
    any_changes=1
    echo "Commits since $base_sha:"
    printf '%s' "$commit_lines" | sort -ru | sed 's/^/  /'
  else
    echo "No changes in tracked paths (upstream moved on, but not there)."
  fi
  echo
done <<<"$providers"

if [[ "$any_changes" -eq 1 ]]; then
  exit 10
fi
exit 0

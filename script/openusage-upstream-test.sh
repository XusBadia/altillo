#!/usr/bin/env bash
# Hermetic regression tests; deliberately runs with macOS-compatible /bin/bash.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat >"$tmp/manifest.json" <<'JSON'
{"repo":"test/upstream","providers":{"test":{"label":"Test","last_reviewed_sha":"base","upstream_paths":["first.swift","second.swift"]}}}
JSON
cat >"$tmp/bin/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEST_CALLS"
case "$*" in
  *commits/HEAD*) echo "${TEST_HEAD:-head}" ;;
  *compare/*)
    [[ "$TEST_CASE" != compare_error ]] || { echo 'API unavailable' >&2; exit 1; }
    [[ "$*" == *--paginate* && "$*" == *--slurp* ]] || exit 2
    if [[ "$TEST_CASE" == diverged ]]; then
      echo '[{"status":"diverged","commits":[]}]'
    else
      echo '[{"status":"ahead","commits":[{"sha":"new1"}]},{"status":"ahead","commits":[{"sha":"new2"}]}]'
    fi
    ;;
  *repos/test/upstream/commits*)
    [[ "$TEST_CASE" != history_error ]] || { echo 'API unavailable' >&2; exit 1; }
    [[ "$*" == *--paginate* && "$*" == *--slurp* ]] || exit 2
    [[ "$*" != *since=* ]] || exit 2
    if [[ "$TEST_CASE" == unchanged ]]; then
      echo '[[{"sha":"base","commit":{"committer":{"date":"2026-01-01"},"message":"already reviewed"}}]]'
    else
      # A commit on page two predates the reviewed timestamp. It must still count.
      echo '[[{"sha":"base","commit":{"committer":{"date":"2026-01-01"},"message":"already reviewed"}}],[{"sha":"new2","commit":{"committer":{"date":"2025-01-01"},"message":"new change"}}]]'
    fi
    ;;
  *) echo "Unexpected gh call: $*" >&2; exit 2 ;;
esac
MOCK
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" OPENUSAGE_UPSTREAM_MANIFEST="$tmp/manifest.json"
export TEST_CALLS="$tmp/calls" TEST_CASE=unchanged
run_case() {
  local expected="$1" actual=0
  /bin/bash "$script_dir/openusage-upstream.sh" test >"$tmp/output" 2>"$tmp/error" || actual=$?
  [[ "$actual" -eq "$expected" ]] || { cat "$tmp/output" "$tmp/error"; echo "Expected $expected, got $actual ($TEST_CASE)" >&2; exit 1; }
}
run_case 0
! grep -q '^- changed:' "$tmp/output"
TEST_CASE=changed
run_case 10
[[ "$(grep -c 'https://github.com/test/upstream/commit/new2$' "$tmp/output")" -eq 1 ]]
[[ "$(grep -c '^- changed:' "$tmp/output")" -eq 2 ]]
for TEST_CASE in compare_error history_error diverged; do
  run_case 1
  grep -q 'error:' "$tmp/error"
done
TEST_HEAD=base
export TEST_HEAD
: >"$TEST_CALLS"
run_case 0
[[ "$(wc -l <"$TEST_CALLS" | tr -d ' ')" -eq 1 ]]
grep -q 'Up to date' "$tmp/output"
unset TEST_HEAD
/bin/bash "$script_dir/openusage-upstream.sh" --mark-reviewed test >"$tmp/output"
[[ "$(jq -r '.providers.test.last_reviewed_sha' "$tmp/manifest.json")" == head ]]
echo 'openusage-upstream: all regression tests passed'

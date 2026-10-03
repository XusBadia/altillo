#!/usr/bin/env bash
set -euo pipefail

# Exercises publication authorization using a real disposable git repository and mocked gh.
# No Xcode, secrets, network or publication; works on macOS and Linux.
GATES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release-gates.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/bin" "$FIXTURE/repo"
cat > "$FIXTURE/bin/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ALTILLO_TEST_GH_ARGS"
[ "${ALTILLO_TEST_GH_FAIL:-0}" = 0 ] || exit 1
cat "$ALTILLO_TEST_GH_RESPONSE"
MOCK
chmod +x "$FIXTURE/bin/gh"
export PATH="$FIXTURE/bin:$PATH"
export ALTILLO_TEST_GH_ARGS="$FIXTURE/args" ALTILLO_TEST_GH_RESPONSE="$FIXTURE/response"
cd "$FIXTURE/repo"
git init --quiet
git config user.email release-test@example.invalid
git config user.name release-test
printf 'source\n' > source.txt
printf 'build/\n' > .gitignore
git add source.txt .gitignore
git commit --quiet -m fixture
SOURCE_SHA="$(git rev-parse HEAD)"
# shellcheck source=script/release-gates.sh
source "$GATES"

reject() {
  local label="$1"
  shift
  if "$@" > "$FIXTURE/output" 2>&1; then
    echo "FAIL: $label authorized publication" >&2
    exit 1
  fi
  echo "PASS: $label rejected"
}

require_release_snapshot "$SOURCE_SHA"
printf 'changed\n' >> source.txt
reject 'dirty tracked source' require_release_snapshot "$SOURCE_SHA"
git add source.txt
reject 'staged source' require_release_snapshot "$SOURCE_SHA"
git restore --staged source.txt
git restore source.txt
touch untracked.txt
reject 'untracked source' require_release_snapshot "$SOURCE_SHA"
rm untracked.txt
mkdir build
touch build/ignored-artifact
require_release_snapshot "$SOURCE_SHA"
echo 'PASS: clean source with ignored build output accepted'
printf 'next commit\n' >> source.txt
git add source.txt
git commit --quiet -m next
reject 'HEAD changed after build' require_release_snapshot "$SOURCE_SHA"

git tag v-lightweight "$SOURCE_SHA"
git tag -a v-annotated "$SOURCE_SHA" -m fixture
git tag v-mismatch HEAD
require_release_tag "$FIXTURE/repo" v-lightweight "$SOURCE_SHA"
require_release_tag "$FIXTURE/repo" v-annotated "$SOURCE_SHA"
require_release_tag "$FIXTURE/repo" v-new "$SOURCE_SHA"
echo 'PASS: lightweight, annotated and absent remote tags accepted'
reject 'tag for a different SHA' require_release_tag "$FIXTURE/repo" v-mismatch "$SOURCE_SHA"
reject 'unavailable remote tag lookup' require_release_tag "$FIXTURE/missing-repo" v-new "$SOURCE_SHA"

printf '%s completed success 123\n' "$SOURCE_SHA" > "$ALTILLO_TEST_GH_RESPONSE"
require_release_ci XusBadia/altillo "$SOURCE_SHA"
# The query must select the exact workflow/main/push/SHA and latest run, without success filtering.
python3 - "$ALTILLO_TEST_GH_ARGS" "$SOURCE_SHA" <<'PY'
import pathlib, sys
args = pathlib.Path(sys.argv[1]).read_text().splitlines()
for flag, value in [('--workflow', 'ci.yml'), ('--branch', 'main'), ('--event', 'push'),
                    ('--commit', sys.argv[2]), ('--limit', '1')]:
    assert args[args.index(flag) + 1] == value, (flag, args)
assert '--status' not in args, 'Filtering by success could accept an older green run'
PY
echo 'PASS: latest exact CI query'
for conclusion in failure cancelled skipped neutral timed_out; do
  printf '%s completed %s 123\n' "$SOURCE_SHA" "$conclusion" > "$ALTILLO_TEST_GH_RESPONSE"
  reject "CI $conclusion" require_release_ci XusBadia/altillo "$SOURCE_SHA"
done
printf '%s in_progress success 123\n' "$SOURCE_SHA" > "$ALTILLO_TEST_GH_RESPONSE"
reject 'CI incomplete' require_release_ci XusBadia/altillo "$SOURCE_SHA"
printf '%s completed success 123\n' "$(git rev-parse HEAD)" > "$ALTILLO_TEST_GH_RESPONSE"
reject 'green CI for a different SHA' require_release_ci XusBadia/altillo "$SOURCE_SHA"
: > "$ALTILLO_TEST_GH_RESPONSE"
reject 'no CI run' require_release_ci XusBadia/altillo "$SOURCE_SHA"
printf '%s completed success invalid\n' "$SOURCE_SHA" > "$ALTILLO_TEST_GH_RESPONSE"
reject 'malformed CI response' require_release_ci XusBadia/altillo "$SOURCE_SHA"
printf '%s completed success 123\n%s completed success 456\n' "$SOURCE_SHA" "$SOURCE_SHA" > "$ALTILLO_TEST_GH_RESPONSE"
reject 'multiple CI response rows' require_release_ci XusBadia/altillo "$SOURCE_SHA"
export ALTILLO_TEST_GH_FAIL=1
reject 'GitHub API failure' require_release_ci XusBadia/altillo "$SOURCE_SHA"
echo 'All release publication gate checks passed.'

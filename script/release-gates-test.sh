#!/usr/bin/env bash
set -euo pipefail

# Exercises publication authorization using a real disposable git repository and local results.
# No Xcode, secrets, network or publication; works on macOS and Linux.
GATES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release-gates.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/repo"
export ALTILLO_VALIDATION_DIR="$FIXTURE/validation"
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

reject 'missing local validation' require_release_ci "$SOURCE_SHA"
mkdir -p "$ALTILLO_VALIDATION_DIR/$SOURCE_SHA"
result="$ALTILLO_VALIDATION_DIR/$SOURCE_SHA/passed"
git rev-parse HEAD > "$result"
reject 'validation for a different SHA' require_release_ci "$SOURCE_SHA"
printf '%s\n' "$SOURCE_SHA" > "$result"
require_release_ci "$SOURCE_SHA"
echo 'All release publication gate checks passed.'

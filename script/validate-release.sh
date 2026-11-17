#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source script/release-gates.sh
sha=$(git rev-parse HEAD)
require_release_snapshot "$sha"
cache="${ALTILLO_DERIVED_DATA_PATH:-$HOME/Library/Developer/BuildCache/altillo}"
results="${ALTILLO_VALIDATION_DIR:-$HOME/Library/Developer/BuildCache/altillo/ReleaseValidation}/$sha"
mkdir -p "$results"
if [ -f "$results/passed" ]; then rm "$results/passed"; fi
exec > >(tee "$results/validation.log") 2>&1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
printf 'Validating %s\n' "$sha"

bash script/release-gates-test.sh
python3 script/check-mail-signing-test.py
gitleaks git --redact --no-banner .
swift test --package-path Packages/AltilloKit --scratch-path "$cache/SwiftPM"
xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme Altillo -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$cache" -parallel-testing-enabled NO -quiet test
python3 script/check-localization.py "$cache"
xcodebuild -project Altillo.xcodeproj -scheme AltilloiOS -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$cache" CODE_SIGNING_ALLOWED=NO -quiet build
(
  cd website
  npm ci
  npx playwright install chromium webkit
  npm run build
  npm test -- --workers=1 --fail-on-flaky-tests --forbid-only
)
require_release_snapshot "$sha"
printf '%s\n' "$sha" > "$results/passed"

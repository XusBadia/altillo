#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data=${TMPDIR:-/tmp}/altillo-release-diagnostics-smoke
binary="$derived_data/Build/Products/Release/Altillo.app/Contents/MacOS/Altillo"

if [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d /Applications/Xcode.app ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

cd "$project_dir"
xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme Altillo -configuration Release \
  -derivedDataPath "$derived_data" build

if strings "$binary" | grep -E 'Drag spike log|Design review|Spike log'; then
  echo "Internal diagnostic UI leaked into the Release executable." >&2
  exit 1
fi

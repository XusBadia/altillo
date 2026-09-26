#!/usr/bin/env bash
# Recomputes the sha256 of a published Altillo DMG and rewrites
# packaging/homebrew/Casks/altillo.rb with the new version + sha256.
#
# Usage: script/update-cask.sh <version>   (e.g. script/update-cask.sh 0.5.1)
#
# Does not tap, publish, or push anything — it only edits the local cask
# file in this repo. Run it after script/release.sh has published a
# version to GitHub Releases.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: script/update-cask.sh <version>" >&2
  exit 1
fi

version="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cask_file="$repo_root/packaging/homebrew/Casks/altillo.rb"

if [[ ! -f "$cask_file" ]]; then
  echo "error: cask file not found at $cask_file" >&2
  exit 1
fi

url="https://github.com/XusBadia/altillo/releases/download/v${version}/Altillo-${version}.dmg"
tmp_dmg="$(mktemp -t "Altillo-${version}.XXXXXX.dmg")"
cleanup() { rm -f "$tmp_dmg"; }
trap cleanup EXIT

echo "Downloading ${url} …"
http_status="$(curl -sL -w '%{http_code}' -o "$tmp_dmg" "$url")"
if [[ "$http_status" != "200" ]]; then
  echo "error: download failed (HTTP ${http_status}) for ${url}" >&2
  echo "Is v${version} published on GitHub Releases yet?" >&2
  exit 1
fi

new_sha256="$(shasum -a 256 "$tmp_dmg" | awk '{print $1}')"
if [[ -z "$new_sha256" ]]; then
  echo "error: could not compute sha256 for the downloaded DMG" >&2
  exit 1
fi

if ! grep -qE '^  version "[^"]*"$' "$cask_file"; then
  echo "error: could not find a 'version \"...\"' line to replace in $cask_file" >&2
  exit 1
fi
if ! grep -qE '^  sha256 "[^"]*"$' "$cask_file"; then
  echo "error: could not find a 'sha256 \"...\"' line to replace in $cask_file" >&2
  exit 1
fi

old_version="$(grep -E '^  version "[^"]*"$' "$cask_file" | head -1 | sed -E 's/^  version "([^"]*)"$/\1/')"
old_sha256="$(grep -E '^  sha256 "[^"]*"$' "$cask_file" | head -1 | sed -E 's/^  sha256 "([^"]*)"$/\1/')"

tmp_cask="$(mktemp)"
sed -E \
  -e "s/^  version \"[^\"]*\"\$/  version \"${version}\"/" \
  -e "s/^  sha256 \"[^\"]*\"\$/  sha256 \"${new_sha256}\"/" \
  "$cask_file" > "$tmp_cask"
mv "$tmp_cask" "$cask_file"

echo ""
echo "Updated ${cask_file}:"
echo "  version: ${old_version} -> ${version}"
echo "  sha256:  ${old_sha256} -> ${new_sha256}"

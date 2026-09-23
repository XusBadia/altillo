#!/usr/bin/env bash
set -euo pipefail

# Builds a distributable, Developer ID-signed, notarized Altillo.app, wraps it in a DMG, and updates the
# Sparkle appcast. Runs locally and in CI (.github/workflows/release.yml). See docs/release.md for the
# one-time setup (notarytool profile, Sparkle key, GitHub Pages) and the per-release steps.
#
# Usage: script/release.sh <version> [--dry-run] [--publish]
#
#   <version>    Marketing version, e.g. 0.2.0 (MARKETING_VERSION / CFBundleShortVersionString).
#
# Flags (mutually exclusive):
#   --dry-run    Skip notarization and stop after producing dist/ artifacts. No network writes: does
#                 not touch GitHub or gh-pages, even to read. Equivalent to ALLOW_UNNOTARIZED=1 with
#                 publishing forced off. Use this to prove the pipeline works without real credentials.
#   --publish    After building, notarizing, and packaging, create the GitHub release (`gh release
#                 create`) and push the updated appcast.xml to the gh-pages branch. Requires
#                 notarization (never publishes an un-notarized build) and a `gh` CLI authenticated with
#                 push access to XusBadia/altillo.
#
# Without either flag, the script does everything --publish does except the final publish step: it
# still notarizes and produces a real, ready-to-upload dist/Altillo-<version>.dmg and dist/appcast.xml.
#
# Required env (unless --dry-run):
#   Notarization credentials, either:
#     - a notarytool keychain profile named `altillo-notary`
#       (xcrun notarytool store-credentials altillo-notary --apple-id … --team-id 9L2TD7KVV9), or
#     - ALTILLO_NOTARY_APPLE_ID / ALTILLO_NOTARY_APP_PASSWORD / ALTILLO_NOTARY_TEAM_ID (CI).
#   The Developer ID Application identity for team 9L2TD7KVV9 must be in the signing keychain.
#   Config/Local.xcconfig must set ALTILLO_SPARKLE_PUBLIC_KEY (or pass ALTILLO_SPARKLE_PUBLIC_KEY env).
#
# Optional env:
#   ALTILLO_TEAM_ID               Developer Team ID. Default: 9L2TD7KVV9.
#   ALTILLO_RELEASE_BUILD          CURRENT_PROJECT_VERSION override. Default: `git rev-list --count HEAD`.
#   ALTILLO_FEED_URL               Appcast URL baked into the app. Default: the project's GitHub Pages URL.
#   ALTILLO_SPARKLE_PUBLIC_KEY     Overrides the value read from Config/Local.xcconfig.
#   ALTILLO_SPARKLE_PRIVATE_KEY    Base64 EdDSA private key (CI secret). When set, generate_appcast signs
#                                   with this instead of reading the key from the login keychain.
#   ALTILLO_DERIVED_DATA_PATH      Default: build/dd-release (shared with the test suite — see
#                                   CONTRIBUTING.md — to keep disk usage down on a constrained machine).
#   ALLOW_UNNOTARIZED=1             Same effect as --dry-run's notarization skip, without forcing
#                                   --publish off. Only ever use this for a throwaway local build.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO_SLUG="XusBadia/altillo"
APP_NAME="Altillo"
NOTARY_PROFILE="altillo-notary"

# ---- args -------------------------------------------------------------------------------------------

VERSION=""
DRY_RUN=0
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help)
      sed -n '3,40p' "$0"
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -n "$VERSION" ]; then
        echo "Unexpected extra argument: $arg (version already set to $VERSION)" >&2
        exit 1
      fi
      VERSION="$arg"
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: script/release.sh <version> [--dry-run] [--publish]" >&2
  exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "Version must look like 0.2.0 or 0.2.0-beta.1, got: $VERSION" >&2
  exit 1
fi
if [ "$DRY_RUN" = 1 ] && [ "$PUBLISH" = 1 ]; then
  echo "--dry-run and --publish are mutually exclusive." >&2
  exit 1
fi

# ---- prerequisites ------------------------------------------------------------------------------------

echo "==> checking prerequisites"

if [ "${DEVELOPER_DIR:-}" != "/Applications/Xcode.app/Contents/Developer" ]; then
  echo "Set: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found. Install: brew install xcodegen" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild not found (check DEVELOPER_DIR)." >&2; exit 1; }

TEAM_ID="${ALTILLO_TEAM_ID:-9L2TD7KVV9}"

# The Developer ID Application identity, resolved by team ID so the script doesn't hardcode a name.
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application:" | grep "($TEAM_ID)" | head -n1 \
  | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)"$/\1/')"
if [ -z "$SIGN_IDENTITY" ]; then
  echo "No 'Developer ID Application' identity for team $TEAM_ID in the signing keychain." >&2
  echo "Check: security find-identity -v -p codesigning" >&2
  exit 1
fi
echo "    signing identity: $SIGN_IDENTITY"

SPARKLE_PUBLIC_KEY="${ALTILLO_SPARKLE_PUBLIC_KEY:-}"
if [ -z "$SPARKLE_PUBLIC_KEY" ] && [ -f "$ROOT_DIR/Config/Local.xcconfig" ]; then
  SPARKLE_PUBLIC_KEY="$(sed -n -E 's/^ALTILLO_SPARKLE_PUBLIC_KEY[[:space:]]*=[[:space:]]*(.+)$/\1/p' "$ROOT_DIR/Config/Local.xcconfig" | tail -n1 | xargs)"
fi
if [ -z "$SPARKLE_PUBLIC_KEY" ]; then
  echo "No Sparkle public key. Set ALTILLO_SPARKLE_PUBLIC_KEY or add it to Config/Local.xcconfig." >&2
  echo "Generate one with: script's Sparkle package artifact bin/generate_keys --account altillo" >&2
  echo "(see docs/release.md)." >&2
  exit 1
fi
echo "    Sparkle public key: $SPARKLE_PUBLIC_KEY"

FEED_URL="${ALTILLO_FEED_URL:-https://xusbadia.github.io/altillo/appcast.xml}"
BUILD="${ALTILLO_RELEASE_BUILD:-$(git rev-list --count HEAD)}"

NOTARIZE=0
if [ "$DRY_RUN" = 1 ]; then
  echo "WARNING: --dry-run — build will NOT be notarized and nothing will be published." >&2
elif [ "${ALLOW_UNNOTARIZED:-}" = "1" ]; then
  echo "WARNING: ALLOW_UNNOTARIZED=1 — build will NOT be notarized (Gatekeeper will block it elsewhere)." >&2
elif [ -n "${ALTILLO_NOTARY_APPLE_ID:-}" ] && [ -n "${ALTILLO_NOTARY_APP_PASSWORD:-}" ] && [ -n "${ALTILLO_NOTARY_TEAM_ID:-}" ]; then
  NOTARIZE=1
  echo "    notarization: Apple ID + app-specific password (CI env)"
elif xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  NOTARIZE=1
  echo "    notarization: keychain profile '$NOTARY_PROFILE'"
else
  echo "No notarization credentials found." >&2
  echo "Either: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id $TEAM_ID" >&2
  echo "Or set ALTILLO_NOTARY_APPLE_ID / ALTILLO_NOTARY_APP_PASSWORD / ALTILLO_NOTARY_TEAM_ID." >&2
  echo "Or pass --dry-run for a local build with no notarization." >&2
  exit 1
fi

if [ "$PUBLISH" = 1 ]; then
  [ "$NOTARIZE" = 1 ] || { echo "--publish requires notarization — refusing to publish an un-notarized build." >&2; exit 1; }
  command -v gh >/dev/null 2>&1 || { echo "--publish needs the gh CLI." >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated (gh auth status failed)." >&2; exit 1; }
fi

DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA_PATH="${ALTILLO_DERIVED_DATA_PATH:-$ROOT_DIR/build/dd-release}"
ARCHIVE_PATH="$DERIVED_DATA_PATH/$APP_NAME.xcarchive"
EXPORT_OPTIONS="$DERIVED_DATA_PATH/ExportOptions.plist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RELEASES_DIR="$DIST_DIR/appcast-feed"

mkdir -p "$DIST_DIR"

notarize() {  # $1: artifact to submit (.zip or .dmg)
  if [ -n "${ALTILLO_NOTARY_APPLE_ID:-}" ]; then
    xcrun notarytool submit "$1" \
      --apple-id "$ALTILLO_NOTARY_APPLE_ID" --password "$ALTILLO_NOTARY_APP_PASSWORD" \
      --team-id "$ALTILLO_NOTARY_TEAM_ID" --wait
  else
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
}

# ---- archive ------------------------------------------------------------------------------------------

echo "==> xcodegen generate"
xcodegen generate

echo "==> archiving $APP_NAME $VERSION ($BUILD)"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$ROOT_DIR/Altillo.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  ALTILLO_SPARKLE_FEED_URL="$FEED_URL" \
  ALTILLO_SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

echo "==> exporting $APP_PATH"
rm -rf "$DIST_DIR/export" "$APP_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$DIST_DIR/export" \
  -exportOptionsPlist "$EXPORT_OPTIONS"
mv "$DIST_DIR/export/$APP_NAME.app" "$APP_PATH"
rmdir "$DIST_DIR/export" 2>/dev/null || rm -rf "$DIST_DIR/export"

# The archive itself (a full copy of build products + dSYMs + Info.plist) isn't needed once exported —
# remove it to keep this disk-constrained machine's build/ directory small.
rm -rf "$ARCHIVE_PATH"

echo "==> verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
CODESIGN_INFO="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1)"
echo "$CODESIGN_INFO" | grep -q "Authority=Developer ID Application" \
  || { echo "Signed app's authority chain does not start with Developer ID Application." >&2; echo "$CODESIGN_INFO" >&2; exit 1; }
echo "    Gatekeeper readiness (spctl) — expected to fail until notarized/stapled below:"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true

# ---- notarize the app -----------------------------------------------------------------------------

if [ "$NOTARIZE" = 1 ]; then
  echo "==> notarizing app (this can take a few minutes)"
  APP_ZIP="$DIST_DIR/$APP_NAME-notarize.zip"
  ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
  notarize "$APP_ZIP"
  xcrun stapler staple "$APP_PATH"
  rm -f "$APP_ZIP"
fi

# ---- DMG --------------------------------------------------------------------------------------------

echo "==> building $DMG_PATH"
STAGE="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

if [ "$NOTARIZE" = 1 ]; then
  echo "==> notarizing dmg"
  notarize "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  echo "==> notarized + stapled"
fi

# ---- appcast ------------------------------------------------------------------------------------------

echo "==> generating appcast"
rm -rf "$RELEASES_DIR"
mkdir -p "$RELEASES_DIR"

if [ "$DRY_RUN" = 0 ]; then
  # Carry forward the live feed so older versions (and other channels) aren't dropped. Best-effort:
  # only replaces the fresh, empty feed when gh-pages genuinely has no appcast yet; any other failure
  # to read it aborts, so a network blip can never silently truncate the published history.
  set +e
  git ls-remote --exit-code --heads "https://github.com/$REPO_SLUG.git" gh-pages >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    TMP_CLONE="$(mktemp -d)"
    git clone --quiet --branch gh-pages --single-branch --depth 1 "https://github.com/$REPO_SLUG.git" "$TMP_CLONE"
    cp "$TMP_CLONE/appcast.xml" "$RELEASES_DIR/appcast.xml"
    rm -rf "$TMP_CLONE"
    echo "    loaded existing appcast from gh-pages"
  elif [ "$rc" -eq 2 ]; then
    echo "    no gh-pages branch yet — starting a fresh feed"
  else
    echo "Could not reach GitHub to check for gh-pages — aborting to protect the live feed." >&2
    echo "(pass --dry-run to skip this check entirely)" >&2
    exit 1
  fi
fi

cp "$DMG_PATH" "$RELEASES_DIR/$DMG_NAME"

GENERATE_APPCAST="$(find "$DERIVED_DATA_PATH/SourcePackages/artifacts" -type f -name generate_appcast 2>/dev/null | head -n1)"
[ -x "$GENERATE_APPCAST" ] || { echo "generate_appcast not found under $DERIVED_DATA_PATH/SourcePackages/artifacts" >&2; exit 1; }

DOWNLOAD_PREFIX="https://github.com/$REPO_SLUG/releases/download/v$VERSION/"
CHANNEL_ARGS=()
[[ "$VERSION" == *-* ]] && CHANNEL_ARGS=(--channel beta)

if [ -n "${ALTILLO_SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$ALTILLO_SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - --download-url-prefix "$DOWNLOAD_PREFIX" --maximum-versions 0 \
    "${CHANNEL_ARGS[@]}" "$RELEASES_DIR"
else
  "$GENERATE_APPCAST" --account altillo \
    --download-url-prefix "$DOWNLOAD_PREFIX" --maximum-versions 0 \
    "${CHANNEL_ARGS[@]}" "$RELEASES_DIR"
fi

grep -Eq "$DMG_NAME\"[^>]*sparkle:edSignature" "$RELEASES_DIR/appcast.xml" \
  || { echo "New item for $DMG_NAME is missing or unsigned (public/private Sparkle key mismatch?)." >&2; exit 1; }

cp "$RELEASES_DIR/appcast.xml" "$DIST_DIR/appcast.xml"
rm -rf "$RELEASES_DIR"

echo "==> done"
echo "    App:      $APP_PATH"
echo "    DMG:      $DMG_PATH"
echo "    Appcast:  $DIST_DIR/appcast.xml"
[ "$NOTARIZE" = 1 ] || echo "    NOT notarized (dry run / ALLOW_UNNOTARIZED)."

# ---- publish ------------------------------------------------------------------------------------------

if [ "$PUBLISH" = 0 ]; then
  echo "    Stopping here (pass --publish to create the GitHub release and push the appcast)."
  exit 0
fi

echo "==> publishing v$VERSION"
PRERELEASE_ARGS=()
[[ "$VERSION" == *-* ]] && PRERELEASE_ARGS=(--prerelease)
gh release create "v$VERSION" "$DMG_PATH" \
  --repo "$REPO_SLUG" \
  --title "Altillo $VERSION" \
  --generate-notes \
  "${PRERELEASE_ARGS[@]}"

echo "==> publishing appcast to gh-pages"
PAGES_DIR="$(mktemp -d)"
if git ls-remote --exit-code --heads "https://github.com/$REPO_SLUG.git" gh-pages >/dev/null 2>&1; then
  git clone --quiet --branch gh-pages --single-branch --depth 1 "https://github.com/$REPO_SLUG.git" "$PAGES_DIR"
else
  git -C "$PAGES_DIR" init --quiet
  git -C "$PAGES_DIR" checkout --quiet -b gh-pages
fi
cp "$DIST_DIR/appcast.xml" "$PAGES_DIR/appcast.xml"
git -C "$PAGES_DIR" add appcast.xml
if ! git -C "$PAGES_DIR" diff --cached --quiet; then
  git -C "$PAGES_DIR" -c user.name="altillo-release" -c user.email="noreply@altillo.local" \
    commit --quiet -m "chore: publish appcast for v$VERSION"
  git -C "$PAGES_DIR" push --quiet "https://github.com/$REPO_SLUG.git" gh-pages
else
  echo "    appcast.xml unchanged — nothing to push"
fi
rm -rf "$PAGES_DIR"

echo "==> published: https://github.com/$REPO_SLUG/releases/tag/v$VERSION"

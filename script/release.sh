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
#   ALTILLO_ICLOUD_PROFILE         Developer ID provisioning profile with iCloud (iCloud.me.badia.ailimits) for
#                                   the legacy iPhone export. Default: ALTILLO_ICLOUD_PROFILE in
#                                   Config/Local.xcconfig (created by script/icloud-profile.py). Relative paths
#                                   are relative to the repo root. Without it the app is built WITHOUT iCloud (a
#                                   warning, not an error): the legacy export then stays off in that build.
#   ALTILLO_ICLOUD_PROFILE_BASE64  The same profile, base64-encoded (CI secret). Wins over ALTILLO_ICLOUD_PROFILE.
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
      sed -n '3,48p' "$0"
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
SIGN_IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application:" | grep "($TEAM_ID)" | head -n1)"
SIGN_IDENTITY="$(printf '%s' "$SIGN_IDENTITY_LINE" | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)"$/\1/')"
SIGN_SHA1="$(printf '%s' "$SIGN_IDENTITY_LINE" | sed -E 's/^[[:space:]]*[0-9]+\) ([0-9A-F]+) .*$/\1/')"
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

# ---- iCloud (legacy iPhone export, optional) ------------------------------------------------------------
# A Developer ID profile for $BUNDLE_ID that allows iCloud.me.badia.ailimits turns on the iCloud entitlements
# (Apps/macOS/App/Altillo.release.entitlements), so the release can write the old TestFlight iPhone app's file
# (docs/release.md, docs/uso-ia.md). Without one the release is exactly what it was before, minus that export.

ICLOUD_CONTAINER="iCloud.me.badia.ailimits"
RELEASE_ENTITLEMENTS="$ROOT_DIR/Apps/macOS/App/Altillo.release.entitlements"
BUNDLE_ID="$(sed -n -E 's/^ALTILLO_BUNDLE_PREFIX[[:space:]]*=[[:space:]]*(.+)$/\1/p' "$ROOT_DIR/Config/Local.xcconfig" 2>/dev/null | tail -n1 | xargs)"
BUNDLE_ID="${BUNDLE_ID:-dev.altillo}"

ICLOUD_PROFILE="${ALTILLO_ICLOUD_PROFILE:-}"
ICLOUD_PROFILE_TMP=""
if [ -n "${ALTILLO_ICLOUD_PROFILE_BASE64:-}" ]; then
  ICLOUD_PROFILE_TMP="$(mktemp -t altillo-icloud)"
  printf '%s' "$ALTILLO_ICLOUD_PROFILE_BASE64" | base64 -D > "$ICLOUD_PROFILE_TMP"
  ICLOUD_PROFILE="$ICLOUD_PROFILE_TMP"
elif [ -z "$ICLOUD_PROFILE" ] && [ -f "$ROOT_DIR/Config/Local.xcconfig" ]; then
  ICLOUD_PROFILE="$(sed -n -E 's/^ALTILLO_ICLOUD_PROFILE[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$ROOT_DIR/Config/Local.xcconfig" | tail -n1 | xargs)"
fi
[ -n "$ICLOUD_PROFILE" ] && [[ "$ICLOUD_PROFILE" != /* ]] && ICLOUD_PROFILE="$ROOT_DIR/$ICLOUD_PROFILE"
PROFILE_PLIST=""
cleanup_icloud() { rm -f "$PROFILE_PLIST" "$ICLOUD_PROFILE_TMP"; }
trap cleanup_icloud EXIT

ICLOUD=0
PROFILE_APP_ID=""
if [ -n "$ICLOUD_PROFILE" ]; then
  # Configured means it must be right: a broken profile fails the release instead of silently dropping iCloud.
  [ -f "$ICLOUD_PROFILE" ] || { echo "iCloud profile not found: $ICLOUD_PROFILE (run script/icloud-profile.py)." >&2; exit 1; }
  PROFILE_PLIST="$(mktemp -t altillo-profile)"
  security cms -D -i "$ICLOUD_PROFILE" > "$PROFILE_PLIST" 2>/dev/null \
    || { echo "Can't decode the iCloud profile: $ICLOUD_PROFILE" >&2; exit 1; }
  pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$PROFILE_PLIST" 2>/dev/null; }
  PROFILE_TEAM="$(pb TeamIdentifier:0)"
  PROFILE_APP_ID="$(pb Entitlements:com.apple.application-identifier)"
  [ "$PROFILE_TEAM" = "$TEAM_ID" ] || { echo "iCloud profile is for team '$PROFILE_TEAM', not $TEAM_ID." >&2; exit 1; }
  [ "$PROFILE_APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] \
    || { echo "iCloud profile is for '$PROFILE_APP_ID', not $TEAM_ID.$BUNDLE_ID." >&2; exit 1; }
  pb Entitlements:com.apple.developer.icloud-container-identifiers | grep -Fxq "    $ICLOUD_CONTAINER" \
    || { echo "iCloud profile doesn't allow $ICLOUD_CONTAINER (assign the container to the App ID, then rerun script/icloud-profile.py)." >&2; exit 1; }
  if pb ProvisionedDevices:0 >/dev/null; then
    echo "iCloud profile is a development profile (it lists devices); a release needs a Developer ID one." >&2; exit 1
  fi
  EXPIRES="$(plutil -extract ExpirationDate raw -o - "$PROFILE_PLIST")"
  if [ "$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$EXPIRES" +%s 2>/dev/null || echo 0)" -le "$(date +%s)" ]; then
    echo "iCloud profile expired ($EXPIRES). Rerun script/icloud-profile.py." >&2; exit 1
  fi
  CERT_MATCH=0
  i=0
  while CERT_B64="$(plutil -extract "DeveloperCertificates.$i" raw -o - "$PROFILE_PLIST" 2>/dev/null)"; do
    if [ "$(printf '%s' "$CERT_B64" | base64 -D | shasum -a 1 | awk '{print toupper($1)}')" = "$SIGN_SHA1" ]; then
      CERT_MATCH=1
    fi
    i=$((i + 1))
  done
  [ "$CERT_MATCH" = 1 ] \
    || { echo "iCloud profile doesn't include the signing certificate ($SIGN_SHA1). Rerun script/icloud-profile.py." >&2; exit 1; }
  ICLOUD=1
  echo "    iCloud: $ICLOUD_CONTAINER via profile $(pb Name) ($(pb UUID), expires $EXPIRES)"
else
  echo "WARNING: no iCloud profile (ALTILLO_ICLOUD_PROFILE) — building WITHOUT iCloud: this release can't feed" >&2
  echo "         the old iPhone app. See docs/release.md \"iCloud (transición)\"." >&2
fi

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

# ---- iCloud: embed the profile and re-sign the app with the release entitlements --------------------------
# Only the outer bundle is re-signed (no --deep): Sparkle and altillo-hook keep the signatures the export gave
# them. codesign doesn't inject the profile's identity entitlements the way Xcode does, so they're added here —
# without them taskgated/AMFI refuses to launch an app that claims iCloud.

if [ "$ICLOUD" = 1 ]; then
  echo "==> enabling iCloud ($ICLOUD_CONTAINER)"
  cp "$ICLOUD_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
  # Same declaration the bridge (and the iPhone app) use; not public, so it never shows up in iCloud Drive.
  plutil -replace NSUbiquitousContainers -json \
    "{\"$ICLOUD_CONTAINER\":{\"NSUbiquitousContainerIsDocumentScopePublic\":false,\"NSUbiquitousContainerName\":\"OpenUsage\",\"NSUbiquitousContainerSupportedFolderLevels\":\"None\"}}" \
    "$APP_PATH/Contents/Info.plist"
  RESOLVED_ENTITLEMENTS="$DERIVED_DATA_PATH/Altillo.release.resolved.entitlements"
  mkdir -p "$DERIVED_DATA_PATH"
  cp "$RELEASE_ENTITLEMENTS" "$RESOLVED_ENTITLEMENTS"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $PROFILE_APP_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
    "$RESOLVED_ENTITLEMENTS"
  plutil -lint "$RESOLVED_ENTITLEMENTS" >/dev/null
  codesign --force --timestamp --options runtime \
    --entitlements "$RESOLVED_ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"
fi

echo "==> verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
CODESIGN_INFO="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1)"
echo "$CODESIGN_INFO" | grep -q "Authority=Developer ID Application" \
  || { echo "Signed app's authority chain does not start with Developer ID Application." >&2; echo "$CODESIGN_INFO" >&2; exit 1; }
echo "$CODESIGN_INFO" | grep -q "flags=.*runtime" \
  || { echo "Signed app lacks the hardened runtime flag." >&2; exit 1; }
if [ "$ICLOUD" = 1 ]; then
  SIGNED_ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null)"
  for needle in "$PROFILE_APP_ID" "$ICLOUD_CONTAINER" "com.apple.developer.team-identifier" "CloudDocuments"; do
    printf '%s' "$SIGNED_ENTITLEMENTS" | grep -Fq "$needle" \
      || { echo "Signed entitlements are missing $needle." >&2; exit 1; }
  done
  echo "    iCloud entitlements + embedded profile: OK ($PROFILE_APP_ID)"
fi
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
if [ "$ICLOUD" = 1 ]; then
  echo "    iCloud:   on ($ICLOUD_CONTAINER, legacy iPhone export)"
else
  echo "    iCloud:   OFF (no ALTILLO_ICLOUD_PROFILE) — the old iPhone app won't get data from this build."
fi
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

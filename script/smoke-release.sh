#!/usr/bin/env bash
set -euo pipefail

# Verify the exact DMG users will download. This script is intentionally
# independent from release.sh so a downloaded GitHub artifact can be checked too.
# Usage: script/smoke-release.sh path/to/Altillo-X.Y.Z.dmg

DMG_PATH="${1:-}"
if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "Usage: $0 path/to/Altillo-X.Y.Z.dmg" >&2
  exit 2
fi

MOUNT_POINT="$(mktemp -d)"
APP_PROCESS=""
cleanup() {
  if [[ -n "$APP_PROCESS" ]] && kill -0 "$APP_PROCESS" 2>/dev/null; then
    kill "$APP_PROCESS" 2>/dev/null || true
    wait "$APP_PROCESS" 2>/dev/null || true
  fi
  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> mounting $(basename "$DMG_PATH")"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" -quiet
APP_PATH="$MOUNT_POINT/Altillo.app"
[[ -d "$APP_PATH" ]] || { echo "Altillo.app is missing from the DMG." >&2; exit 1; }

echo "==> checking Developer ID signature and Gatekeeper"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "==> checking embedded signed code"
while IFS= read -r -d '' item; do
  codesign --verify --strict --verbose=2 "$item"
done < <(find "$APP_PATH/Contents" \( -name '*.framework' -o -name '*.xpc' -o -name '*.appex' \) -print0)

INFO_PLIST="$APP_PATH/Contents/Info.plist"
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")"
[[ "$FEED_URL" == https://* ]] || { echo "Sparkle feed must use HTTPS." >&2; exit 1; }
[[ -n "$PUBLIC_KEY" ]] || { echo "Sparkle public key is empty." >&2; exit 1; }

if [[ "${ALTILLO_SMOKE_SKIP_LAUNCH:-0}" != 1 ]]; then
  echo "==> launching mounted app"
  "$APP_PATH/Contents/MacOS/Altillo" >/tmp/altillo-release-smoke.log 2>&1 &
  APP_PROCESS=$!
  sleep 5
  kill -0 "$APP_PROCESS" 2>/dev/null || {
    echo "Altillo exited during the launch smoke test." >&2
    sed -n '1,120p' /tmp/altillo-release-smoke.log >&2 || true
    exit 1
  }
fi

echo "==> release smoke passed"

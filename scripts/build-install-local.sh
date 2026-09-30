#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="Spaceman"
SCHEME="Spaceman"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/.derivedData}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PROJECT.app"
DEST_PATH="$INSTALL_DIR/$PROJECT.app"

# Stable local identity from mactools' scripts/create-signing-identity.sh keeps
# macOS privacy grants across rebuilds; otherwise sign ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -q '"KobeTools Dev"' && echo "KobeTools Dev" || echo -)}"

echo "Building $PROJECT ($CONFIGURATION) without code signing..."

xcodebuild \
  -project "$REPO_ROOT/$PROJECT.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app was not found at:"
  echo "  $APP_PATH"
  exit 1
fi

mkdir -p "$INSTALL_DIR"

if pgrep -x "$PROJECT" >/dev/null 2>&1; then
  echo "Stopping running $PROJECT instance..."
  pkill -x "$PROJECT" || true
fi

# macOS ties privacy grants to the signature they were granted to; remember the
# installed build's so a change can be detected after installing.
OLD_REQ="$(codesign -d -r- "$DEST_PATH" 2>/dev/null | sed -n 's/^designated => //p' || true)"

echo "Installing to $DEST_PATH..."
ditto "$APP_PATH" "$DEST_PATH"

echo "Signing installed app ($SIGN_IDENTITY)..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$DEST_PATH"

# A different signature (ad-hoc builds, or the first build with a new identity)
# leaves the old grant listed as allowed but ignored. Clear it so macOS asks again.
NEW_REQ="$(codesign -d -r- "$DEST_PATH" 2>/dev/null | sed -n 's/^designated => //p' || true)"
if [[ -n "$OLD_REQ" && "$OLD_REQ" != "$NEW_REQ" ]]; then
  APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST_PATH/Contents/Info.plist")"
  echo "Signature changed: resetting privacy grants for $APP_ID so macOS asks again."
  tccutil reset All "$APP_ID" >/dev/null 2>&1 || true
fi

echo "Opening installed app..."
open "$DEST_PATH"

echo
echo "Installed $PROJECT to:"
echo "  $DEST_PATH"

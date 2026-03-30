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

echo "Installing to $DEST_PATH..."
ditto "$APP_PATH" "$DEST_PATH"

echo "Ad-hoc signing installed app..."
codesign --force --deep --sign - "$DEST_PATH"

echo "Opening installed app..."
open "$DEST_PATH"

echo
echo "Installed $PROJECT to:"
echo "  $DEST_PATH"

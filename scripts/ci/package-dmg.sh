#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <App.app> <Output.dmg> [Volume Name]" >&2
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

APP_PATH="$1"
DMG_PATH="$2"
VOLUME_NAME="${3:-$(basename "$APP_PATH" .app)}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
DMG_DIR="$(dirname "$DMG_PATH")"
TMP_DIR="$(mktemp -d)"
STAGING_DIR="$TMP_DIR/dmg-root"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR" "$DMG_DIR"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

test -f "$DMG_PATH"

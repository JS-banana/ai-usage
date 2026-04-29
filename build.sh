#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AiUsage"
BUNDLE_ID="com.jsbanana.aiusage"
VERSION="0.1.1"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"
BUILD_CONFIGURATION="release"

INSTALL_APP=false
OPEN_APP=false

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL_APP=true ;;
    --open) OPEN_APP=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: ./build.sh [--install] [--open]" >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

echo "==> Building $APP_NAME ($BUILD_CONFIGURATION)"
swift build -c "$BUILD_CONFIGURATION" --product "$APP_NAME"

BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BINARY_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Expected binary not found: $BINARY_PATH" >&2
  exit 1
fi

DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> Copying executable"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> Copying SwiftPM bundles"
find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print0 | while IFS= read -r -d '' bundle; do
  cp -R "$bundle" "$RESOURCES_DIR/"
done

echo "==> Normalizing app bundle permissions"
# Some SwiftPM resource bundles ship files as read-only (for example GRDB's
# PrivacyInfo.xcprivacy). If we keep those modes in the distributed app,
# `xattr -rd com.apple.quarantine` can fail with "Permission denied" after
# users install the app. Normalize the bundle so the owner can update xattrs.
chmod -R u+rwX,go+rX "$APP_DIR"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> Writing Info.plist"
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  echo "==> Ad-hoc signing app bundle"
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Built app bundle:"
echo "    $APP_DIR"

if [[ "$INSTALL_APP" == true ]]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  echo "    Installed: /Applications/$APP_NAME.app"
fi

if [[ "$OPEN_APP" == true ]]; then
  TARGET_APP="$APP_DIR"
  if [[ "$INSTALL_APP" == true ]]; then
    TARGET_APP="/Applications/$APP_NAME.app"
  fi
  echo "==> Opening $TARGET_APP"
  open "$TARGET_APP"
fi

echo
echo "Done."
echo "You can launch the local bundle with:"
echo "  open \"$APP_DIR\""
echo "Or install and open in one step with:"
echo "  ./build.sh --install --open"

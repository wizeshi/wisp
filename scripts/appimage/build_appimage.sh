#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="wisp"
APP_ID="com.wizeshi.wisp"
BUILD_DIR="$ROOT_DIR/build"
LINUX_BUNDLE_DIR="$BUILD_DIR/linux/x64/release/bundle"
APPDIR="$BUILD_DIR/appimage/AppDir"
DESKTOP_TEMPLATE="$ROOT_DIR/linux/packaging/appimage/wisp.desktop"
ICON_SOURCE="$ROOT_DIR/assets/wisp.png"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found in PATH" >&2
  exit 1
fi

if ! command -v appimagetool >/dev/null 2>&1; then
  echo "appimagetool not found in PATH" >&2
  exit 1
fi

flutter build linux --release

if [[ ! -d "$LINUX_BUNDLE_DIR" ]]; then
  echo "Linux bundle not found at $LINUX_BUNDLE_DIR" >&2
  exit 1
fi

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib/$APP_NAME"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

cp -r "$LINUX_BUNDLE_DIR"/* "$APPDIR/usr/lib/$APP_NAME/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/wisp/wisp" "$@"
EOF
chmod +x "$APPDIR/AppRun"

cp "$DESKTOP_TEMPLATE" "$APPDIR/$APP_NAME.desktop"
cp "$DESKTOP_TEMPLATE" "$APPDIR/usr/share/applications/$APP_NAME.desktop"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APPDIR/$APP_NAME.png"
  cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
else
  echo "Icon not found at $ICON_SOURCE" >&2
fi

APPIMAGE_OUT="$BUILD_DIR/${APP_NAME}-linux-x86_64.AppImage"
appimagetool "$APPDIR" "$APPIMAGE_OUT"

echo "AppImage created at $APPIMAGE_OUT"

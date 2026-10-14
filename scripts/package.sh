#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" != --no-build ]]; then "$ROOT/scripts/build.sh"; fi
APP="$ROOT/dist/ScrollCap.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
if [[ -n "${SCROLLSHOT_ARCH:-}" ]]; then ARCH="$SCROLLSHOT_ARCH"; fi
NAME="ScrollCap-$VERSION-macOS-$ARCH"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/scrollcap-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ScrollCap.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/USER_GUIDE.zh-CN.md" "$STAGE/使用说明.md"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
hdiutil create -volname "ScrollCap $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$ROOT/dist/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/$NAME.zip"
hdiutil verify "$ROOT/dist/$NAME.dmg"
(cd "$ROOT/dist" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME-SHA256SUMS.txt")
printf 'Packaged %s\n' "$NAME"

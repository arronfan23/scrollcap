#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${SCROLLSHOT_ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac

if [[ -x /Library/Developer/CommandLineTools/usr/bin/swiftc && -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk ]]; then
    COMPILER=/Library/Developer/CommandLineTools/usr/bin/swiftc
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
else
    COMPILER="$(xcrun --find swiftc)"
    SDK="$(xcrun --show-sdk-path)"
fi

APP="$ROOT/dist/ScrollCap.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
"$COMPILER" -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx14.0" \
    -module-cache-path "$ROOT/.build/module-cache" \
    "$ROOT"/Sources/ScrollCap/*.swift -o "$APP/Contents/MacOS/ScrollCap"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier io.github.arronfan23.scrollcap "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s (%s)\n' "$APP" "$ARCH"

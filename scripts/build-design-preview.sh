#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"
if [[ -x /Library/Developer/CommandLineTools/usr/bin/swiftc && -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk ]]; then
    COMPILER=/Library/Developer/CommandLineTools/usr/bin/swiftc
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
else
    COMPILER="$(xcrun --find swiftc)"
    SDK="$(xcrun --show-sdk-path)"
fi
APP="$ROOT/work/ui-design/ScrollCap Design.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
"$COMPILER" -swift-version 5 -O -D DESIGN_PREVIEW -sdk "$SDK" -target "$ARCH-apple-macosx14.0" \
    -module-cache-path "$ROOT/.build/module-cache" \
    "$ROOT"/Sources/ScrollCap/*.swift -o "$APP/Contents/MacOS/ScrollCap"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.arronfan23.scrollcap.designpreview' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName ScrollCap Design' "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/GitHubMark.svg" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/ThirdParty"
cp "$ROOT/Resources/ThirdParty/Octicons-LICENSE.txt" "$APP/Contents/Resources/ThirdParty/"
codesign --force --sign - --identifier io.github.arronfan23.scrollcap.designpreview "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built isolated design preview: %s\n' "$APP"

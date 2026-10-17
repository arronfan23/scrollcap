#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${SCROLLSHOT_ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac

SIGN_IDENTITY="${SCROLLCAP_SIGN_IDENTITY:-}"
if [[ "$SIGN_IDENTITY" == - ]]; then
    echo 'SCROLLCAP_SIGN_IDENTITY must name a certificate, not the ad hoc identity (-).' >&2
    exit 1
fi
if [[ "${SCROLLCAP_REQUIRE_SIGNING:-0}" == 1 && -z "$SIGN_IDENTITY" ]]; then
    echo 'Set SCROLLCAP_SIGN_IDENTITY to an installed signing certificate before building this release.' >&2
    exit 1
fi

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
cp "$ROOT/Resources/GitHubMark.svg" "$APP/Contents/Resources/GitHubMark.svg"
mkdir -p "$APP/Contents/Resources/ThirdParty"
cp "$ROOT/Resources/ThirdParty/Octicons-LICENSE.txt" "$APP/Contents/Resources/ThirdParty/Octicons-LICENSE.txt"
if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
        --identifier io.github.arronfan23.scrollcap "$APP"
else
    echo 'Local test signing: each changed build has a new identity and may need fresh macOS permissions. See docs/SIGNING.md.' >&2
    codesign --force --sign - --identifier io.github.arronfan23.scrollcap "$APP"
fi
codesign --verify --deep --strict "$APP"
printf 'Built %s (%s)\n' "$APP" "$ARCH"

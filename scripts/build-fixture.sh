#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ROOT/work/ScrollCapFixture.app"
mkdir -p "$FIXTURE/Contents/MacOS"
/Library/Developer/CommandLineTools/usr/bin/swiftc -swift-version 5 -O \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -module-cache-path "$ROOT/.build/module-cache" \
    "$ROOT/Tests/Fixtures/ScrollFixture.swift" -o "$FIXTURE/Contents/MacOS/ScrollCapFixture"
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ScrollCapFixture</string>
<key>CFBundleIdentifier</key><string>io.github.arronfan23.scrollcap.fixture</string>
<key>CFBundleName</key><string>ScrollCapFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$FIXTURE"
printf 'Built %s\n' "$FIXTURE"

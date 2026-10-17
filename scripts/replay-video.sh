#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/work/diagnostics" "$ROOT/.build/module-cache"
files=("$ROOT"/Sources/ScrollCap/*.swift)
files=(${files:#*/main.swift})
/Library/Developer/CommandLineTools/usr/bin/swiftc -swift-version 5 -O \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -module-cache-path "$ROOT/.build/module-cache" \
    "${files[@]}" "$ROOT/Tests/Diagnostics/ReplayMovie.swift" -o "$ROOT/work/diagnostics/replay-video"
exec "$ROOT/work/diagnostics/replay-video" "$@"

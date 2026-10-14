#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" != --no-build ]]; then "$ROOT/scripts/build.sh"; fi
EXECUTABLE="$ROOT/dist/ScrollCap.app/Contents/MacOS/ScrollCap"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scrollcap-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
"$EXECUTABLE" --self-test
"$EXECUTABLE" --video-test "$TEST_DIR"

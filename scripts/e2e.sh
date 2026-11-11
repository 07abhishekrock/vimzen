#!/usr/bin/env bash
# Builds the app and runs the Vimzen E2E suite (serial, black-box).
#
# Usage:
#   scripts/e2e.sh                      # full suite
#   scripts/e2e.sh ModeTests            # one suite
#   scripts/e2e.sh NavigationTests/testReload   # one test
set -euo pipefail

cd "$(dirname "$0")/../vimzen"

echo "▸ Building Vimzen (debug)…"
swift build

FILTER="${1:-}"
if [ -n "$FILTER" ]; then
    exec swift test --filter "$FILTER"
else
    exec swift test
fi

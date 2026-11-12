#!/usr/bin/env bash
# Renders the main window off-screen to PNG (no screen-recording permission needed).
# Usage: scripts/ui-snapshot.sh <out-dir>   -> <out-dir>/ui-empty.png, <out-dir>/ui-results.png
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs}"
BIN="$ROOT/build/obj/ui-snapshot"
mkdir -p "$ROOT/build/obj" "$OUT"
swiftc -swift-version 5 -D UI_SNAPSHOT -parse-as-library -target "$(uname -m)-apple-macos13" \
  "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/App/*.swift "$ROOT/tests/ui-snapshot.swift" -o "$BIN"
"$BIN" "$OUT/ui-empty.png"
"$BIN" "$OUT/ui-results.png" --results
FEATHERPIX_LANG=es "$BIN" "$OUT/ui-results-es.png" --results

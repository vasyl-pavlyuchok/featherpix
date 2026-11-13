#!/usr/bin/env bash
# Renders the main window off-screen to PNG (no screen-recording permission needed).
# Usage: scripts/ui-snapshot.sh <out-dir>   -> <out-dir>/ui-*.png (both tabs)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs}"
BIN="$ROOT/build/obj/ui-snapshot"
mkdir -p "$ROOT/build/obj" "$OUT"
swiftc -swift-version 5 -D UI_SNAPSHOT -parse-as-library -target "$(uname -m)-apple-macos13" \
  "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/App/*.swift "$ROOT/tests/ui-snapshot.swift" -o "$BIN"
# Photos tab (mint) and Videos tab (ember), empty / working / results, English and Spanish.
"$BIN" "$OUT/ui-empty.png" --dark
"$BIN" "$OUT/ui-results.png" --dark --results
FEATHERPIX_LANG=es "$BIN" "$OUT/ui-results-es.png" --dark --results
"$BIN" "$OUT/ui-video.png" --dark --video
FEATHERPIX_LANG=es "$BIN" "$OUT/ui-video-working-es.png" --dark --video --working
FEATHERPIX_LANG=es "$BIN" "$OUT/ui-video-results-es.png" --dark --video --results

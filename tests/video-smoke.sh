#!/bin/bash
# Video smoke test: builds synthetic videos (never real footage) and runs every preset through featherpix-cli.
# Usage: tests/video-smoke.sh "build/Featherpix.app"   (runs in CI; locally the CEO can run it too)
set -euo pipefail
APP="${1:?usage: video-smoke.sh path/to/Featherpix.app}"
CLI="$APP/Contents/Resources/bin/featherpix-cli"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/featherpix-video-smoke.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "VIDEO SMOKE FAIL: $*"; exit 1; }

swiftc -swift-version 5 -O "$ROOT/tests/make-test-video.swift" -o "$WORK/mkvid" 2>/dev/null
"$WORK/mkvid" "$WORK/clip.mp4" 4 1920 1080 >/dev/null
"$WORK/mkvid" "$WORK/vertical \$(x).mov" 3 1280 720 --rotate90 >/dev/null
"$WORK/mkvid" "$WORK/silent.m4v" 2 640 360 --no-audio >/dev/null
printf 'not a video' > "$WORK/broken.mp4"
orig_sum=$(shasum "$WORK/clip.mp4" | cut -d' ' -f1)

echo "• web preset"
"$CLI" video -p web --keep-larger "$WORK/clip.mp4" | tee "$WORK/web.log"
[ -s "$WORK/clip-web.mp4" ] || fail "web output missing"

echo "• loop preset (poster + snippet, no audio)"
"$CLI" video -p loop --keep-larger "$WORK/clip.mp4" | tee "$WORK/loop.log"
[ -s "$WORK/clip-loop.mp4" ] || fail "loop output missing"
[ -s "$WORK/clip-poster.webp" ] || fail "poster missing"
grep -q '<video autoplay muted loop playsinline' "$WORK/loop.log" || fail "snippet missing"
grep -q 'sin audio' "$WORK/loop.log" || fail "loop kept audio"
grep -q '1280×720' "$WORK/loop.log" || fail "loop not scaled to 1280"

echo "• max preset, HEVC"
"$CLI" video -p max -c hevc --keep-larger "$WORK/clip.mp4" | tee "$WORK/max.log"
[ -s "$WORK/clip-max.mp4" ] || fail "max output missing"

echo "• rotated .mov with a hostile name"
"$CLI" video -p web --keep-larger "$WORK/vertical \$(x).mov" | tee "$WORK/rot.log"
grep -q '720×1280' "$WORK/rot.log" || fail "rotation lost"

echo "• silent .m4v with web preset (no audio track to keep)"
"$CLI" video -p web --keep-larger "$WORK/silent.m4v" >/dev/null || fail "silent input failed"

echo "• broken file must fail, not crash"
if "$CLI" video "$WORK/broken.mp4" > "$WORK/broken.log" 2>&1; then fail "broken file reported success"; fi
grep -q FAIL "$WORK/broken.log" || fail "broken file not reported"

echo "• name clash gets (2), original untouched"
"$CLI" video -p web --keep-larger "$WORK/clip.mp4" >/dev/null
[ -s "$WORK/clip-web (2).mp4" ] || fail "clash not handled"
[ "$(shasum "$WORK/clip.mp4" | cut -d' ' -f1)" = "$orig_sum" ] || fail "original modified"

echo "VIDEO SMOKE OK"

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

echo "• WebM (VP9 via the bundled LGPL ffmpeg)"
FF="$APP/Contents/Resources/bin/ffmpeg"
[ -x "$FF" ] || fail "ffmpeg not bundled"
"$FF" -hide_banner -L 2>/dev/null | grep -q "Lesser General Public License" || fail "bundled ffmpeg is not LGPL"
if "$FF" -hide_banner -buildconf 2>/dev/null | grep -q -- "--enable-gpl"; then fail "bundled ffmpeg has GPL parts"; fi
# The bundled ffmpeg must be the hardened one scripts/build-ffmpeg.sh describes (council PR117).
PROTOS="$("$FF" -hide_banner -protocols 2>/dev/null | grep -v -E '^(Supported file protocols:|Input:|Output:)$' | tr -d ' ' | sort -u | tr '\n' ' ')"
[ "$PROTOS" = "file pipe " ] || fail "ffmpeg has unexpected protocols: $PROTOS"
CONF="$("$FF" -hide_banner -buildconf 2>/dev/null)"
for want in --disable-network --disable-autodetect --disable-gpl --disable-nonfree pcm_s16le; do
  printf '%s' "$CONF" | grep -q -- "$want" || fail "ffmpeg built without $want"
done
W="$WORK/webm"
probe() { "$FF" -hide_banner -f matroska -i "file:$1" 2>&1 || true; }
decodes() { "$FF" -nostdin -hide_banner -loglevel error -f matroska -i "file:$1" -c:v wrapped_avframe -c:a pcm_s16le -f null - || fail "$1 does not decode"; }

echo "  · loop + MP4 fallback + snippet with both sources"
"$CLI" video -p loop -c vp9 --keep-larger -o "$W" "$WORK/clip.mp4" | tee "$WORK/wloop.log"
[ -s "$W/clip-loop.webm" ] || fail "webm loop missing"
[ -s "$W/clip-loop.mp4" ] || fail "mp4 fallback missing"
[ -s "$W/clip-poster.webp" ] || fail "webm poster missing"
decodes "$W/clip-loop.webm"
probe "$W/clip-loop.webm" | grep -q "Video: vp9" || fail "loop is not VP9"
if probe "$W/clip-loop.webm" | grep -q "Audio:"; then fail "webm loop kept audio"; fi
grep -q 'type="video/webm"' "$WORK/wloop.log" || fail "snippet lacks webm source"
grep -q 'type="video/mp4"' "$WORK/wloop.log" || fail "snippet lacks mp4 fallback"
[ "$(grep -n 'video/webm' "$WORK/wloop.log" | cut -d: -f1)" -lt "$(grep -n 'video/mp4' "$WORK/wloop.log" | cut -d: -f1)" ] || fail "webm must come first"

echo "  · web with Opus audio, no fallback"
"$CLI" video -p web -c vp9 --no-fallback --keep-larger -o "$W" "$WORK/clip.mp4" | tee "$WORK/wweb.log"
[ -s "$W/clip-web.webm" ] || fail "webm web missing"
[ ! -e "$W/clip-web.mp4" ] || fail "--no-fallback still wrote an mp4"
decodes "$W/clip-web.webm"
probe "$W/clip-web.webm" | grep -q "Audio: opus" || fail "webm web lost the audio"

echo "  · rotated .mov with a hostile name"
"$CLI" video -p web -c vp9 --no-fallback --keep-larger -o "$W" "$WORK/vertical \$(x).mov" | tee "$WORK/wrot.log"
grep -q '720×1280' "$WORK/wrot.log" || fail "webm rotation lost"
probe "$W/vertical \$(x)-web.webm" | grep -q "720x1280" || fail "webm file is not 720x1280"
[ ! -e "$WORK/x" ] && [ ! -e "$W/x" ] || fail "a file name was executed"

echo "  · hostile names: leading dash, protocol-looking, quotes (snippet must stay inert)"
H="$WORK/hostile"; mkdir -p "$H"
cp "$WORK/silent.m4v" "$H/-x.m4v"
cp "$WORK/silent.m4v" "$H/a:b|concat:c.m4v"
cp "$WORK/silent.m4v" "$H/x\" onerror=\"alert(1).m4v"
"$CLI" video -c vp9 --no-fallback --keep-larger -o "$H/out" -- "$H/-x.m4v" "$H/a:b|concat:c.m4v" >/dev/null || fail "hostile names failed"
[ -s "$H/out/-x-web.webm" ] && [ -s "$H/out/a:b|concat:c-web.webm" ] || fail "hostile-name outputs missing"
"$CLI" video -p loop -c vp9 --keep-larger -o "$H/out" -- "$H/x\" onerror=\"alert(1).m4v" > "$H/xss.log" || fail "quote name failed"
grep -E '^ *<(video|source) ' "$H/xss.log" > "$H/snippet.html" || fail "no snippet printed"
if grep -q 'onerror="' "$H/snippet.html"; then fail "snippet lets a file name inject HTML"; fi
grep -q 'src="x%22%20onerror' "$H/snippet.html" || fail "snippet name not encoded"

echo "  · broken file must fail with WebM too"
if "$CLI" video -c vp9 "$WORK/broken.mp4" > "$WORK/wbroken.log" 2>&1; then fail "broken webm reported success"; fi
[ "$(shasum "$WORK/clip.mp4" | cut -d' ' -f1)" = "$orig_sum" ] || fail "original modified by webm"

echo "VIDEO SMOKE OK"

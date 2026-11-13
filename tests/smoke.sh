#!/usr/bin/env bash
# End-to-end smoke test of the built app's engine (via the bundled CLI).
# Usage: tests/smoke.sh build/Featherpix.app
set -euo pipefail
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$APP/Contents/Resources/bin/featherpix-cli"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cp -R "$ROOT/tests/fixtures/." "$WORK/"
before="$(cd "$WORK" && find . -type f -exec shasum {} + | sort)"

for fmt in webp avif jpeg; do
  out="$WORK/out-$fmt"
  set +e; (cd "$WORK" && "$CLI" -f "$fmt" -w 1200 --keep-larger -o "$out" "$WORK/folder" "$WORK/photo-rotated.jpg") > "$WORK/log-$fmt" 2>&1; rc=$?; set -e
  cat "$WORK/log-$fmt"
  # broken.jpg must fail loudly -> exit code 1, never 0.
  [[ $rc -eq 1 ]] || fail "$fmt: expected exit 1 (one broken input), got $rc"
  grep -q "FAIL  folder/broken.jpg" "$WORK/log-$fmt" || fail "$fmt: broken.jpg not reported"
  ext=$([[ $fmt == jpeg ]] && echo jpg || echo $fmt)
  # a.jpg and a.png both exist -> two distinct outputs, nothing overwritten.
  [[ -f "$out/folder/a.$ext" && -f "$out/folder/a (2).$ext" ]] || fail "$fmt: name collision not handled"
  [[ -f "$out/folder/sub/small.$ext" ]] || fail "$fmt: subfolder not mirrored"
  ls "$out/folder/" | grep -q '^odd name' || fail "$fmt: odd filename not processed"
  # Orientation applied + width limited: source is 1600x1000 shown rotated -> 1000x1600 -> max width 1200 stays 1000.
  dims="$(sips -g pixelWidth -g pixelHeight "$out/photo-rotated.$ext" | awk '/pixel/{print $2}' | tr '\n' 'x')"
  [[ "$dims" == "1000x1600x" ]] || fail "$fmt: rotated photo has dims $dims, expected 1000x1600"
  dims="$(sips -g pixelWidth "$out/folder/a.$ext" | awk '/pixelWidth/{print $2}')"
  [[ "$dims" == "1200" ]] || fail "$fmt: a.$ext width $dims, expected 1200"
  dims="$(sips -g pixelWidth "$out/folder/sub/small.$ext" | awk '/pixelWidth/{print $2}')"
  [[ "$dims" == "400" ]] || fail "$fmt: small image was upscaled to $dims"
  # Output really is the requested format.
  magic="$(xxd -l 12 -p "$out/folder/a.$ext")"
  case $fmt in
    webp) [[ "$magic" == 52494646*57454250 ]] || fail "webp magic $magic";;
    avif) [[ "$magic" == *6674797061766966* ]] || fail "avif magic $magic";;
    jpeg) [[ "$magic" == ffd8ff* ]] || fail "jpeg magic $magic";;
  esac
done

# "Keep original if not smaller": JPEG q95 of a q92 JPEG cannot win -> reported as kept, nothing written.
(cd "$WORK" && "$CLI" -f jpeg -q 95 -o "$WORK/out-keep" "$WORK/photo-rotated.jpg") > "$WORK/log-keep" 2>&1 || true
grep -q "^kept  photo-rotated.jpg" "$WORK/log-keep" || { cat "$WORK/log-keep"; fail "skip-if-larger not applied"; }
[[ ! -e "$WORK/out-keep/photo-rotated.jpg" ]] || fail "skip-if-larger still wrote a file"

# Nothing executed from a filename, originals untouched, no temp files left behind.
[[ ! -e "$WORK/PWNED" && ! -e "$ROOT/PWNED" ]] || fail "filename was executed by a shell"
after="$(cd "$WORK" && find . -path './out-*' -prune -o -type f -name '*' ! -name 'log-*' -exec shasum {} + | sort)"
[[ "$before" == "$after" ]] || fail "originals changed"
! find "$WORK" -name '.featherpix-*' | grep -q . || fail "temp files left behind"
# --about and --formats must tell the truth about the bundle
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
"$CLI" --about | grep -q "$VER" || fail "--about does not show version $VER"
FORMATS=$("$CLI" --formats)
for f in WebP AVIF JPEG HEIC MP4 WebM; do printf '%s' "$FORMATS" | grep -qi "$f" || fail "--formats misses $f"; done
# Installed as a symlink (README) and run from a folder that holds a planted "cwebp": the bundled one must run,
# never the planted one, never anything from the current directory.
TRAP="$WORK/trap"; mkdir -p "$TRAP/bin"
ln -s "$CLI" "$TRAP/bin/featherpix"
printf '#!/bin/sh\ntouch "%s/PLANTED_RAN"\nexit 0\n' "$TRAP" > "$TRAP/cwebp"; chmod +x "$TRAP/cwebp"
cp "$WORK/photo-rotated.jpg" "$TRAP/p.jpg"
(cd "$TRAP" && PATH="$TRAP/bin:$PATH" featherpix -f webp -o "$TRAP/out" p.jpg) > "$WORK/log-symlink" 2>&1 || { cat "$WORK/log-symlink"; fail "CLI via symlink failed"; }
[[ ! -e "$TRAP/PLANTED_RAN" ]] || fail "a planted encoder in the current folder was executed"
[[ -s "$TRAP/out/p.webp" ]] || fail "CLI via symlink did not use the bundled encoder"
echo "SMOKE OK"

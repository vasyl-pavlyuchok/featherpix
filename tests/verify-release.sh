#!/usr/bin/env bash
# Verifies a published release end to end, exactly as a user would get it.
# Usage: tests/verify-release.sh [tag] [folder-of-images-for-the-size-check]
# Downloads into a temp dir; never installs anything, never touches /Applications or the images.
set -euo pipefail
TAG="${1:-v$(cat "$(dirname "$0")/../VERSION")}"
LOTE="${2:-}"
REPO=vasyl-pavlyuchok/featherpix
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
ok() { echo "✅ $*"; }
fail() { echo "❌ $*"; exit 1; }

gh release download "$TAG" -R "$REPO" -D "$W/dl" >/dev/null
(cd "$W/dl" && shasum -a 256 -c ./*.sha256 >/dev/null) && ok "SHA-256 of pkg and zip match"
for f in Featherpix-macOS.pkg Featherpix-macOS.zip; do
  gh attestation verify "$W/dl/$f" -R "$REPO" >/dev/null 2>&1 && ok "attestation verified: $f" || fail "attestation: $f"
done

ditto -x -k "$W/dl/Featherpix-macOS.zip" "$W/app"
APP="$W/app/Featherpix.app"
codesign --verify --deep --strict "$APP" && ok "codesign --verify --deep --strict"
for b in "$APP/Contents/MacOS/Featherpix" "$APP"/Contents/Resources/bin/*; do
  a="$(lipo -archs "$b")"; [[ "$a" == *x86_64* && "$a" == *arm64* ]] || fail "$b is not universal ($a)"
done && ok "every executable is universal (x86_64 + arm64)"
[[ -n "$(ls "$APP/Contents/Resources/licenses/")" ]] && ok "third-party licenses inside the app ($(ls "$APP/Contents/Resources/licenses/" | wc -l | tr -d ' ') files)"

pkgutil --expand "$W/dl/Featherpix-macOS.pkg" "$W/pkg"
grep -q 'install-location="/Applications"' "$W/pkg/PackageInfo" && ok ".pkg installs into /Applications"
pkgutil --payload-files "$W/dl/Featherpix-macOS.pkg" | grep -q '^./Featherpix.app/Contents/MacOS/Featherpix$' && ok ".pkg contains Featherpix.app"

"$ROOT/tests/smoke.sh" "$APP" | tail -1 | grep -q "SMOKE OK" && ok "smoke test on the downloaded app"

if [[ -n "$LOTE" ]]; then
  n0=$(find "$LOTE" -type f | wc -l | tr -d ' '); s0=$(du -sk "$LOTE" | cut -f1)
  "$APP/Contents/Resources/bin/featherpix-cli" --preset smallest -o "$W/out" "$LOTE" | tail -1
  n1=$(find "$W/out" -type f | wc -l | tr -d ' ')
  bytes=$(find "$W/out" -type f -exec stat -f %z {} + | awk '{s+=$1} END {print s}')
  echo "   $n1 output files, $(echo "scale=2; $bytes/1000000" | bc) MB"
  [[ "$bytes" -lt 10000000 ]] && ok "batch under 10 MB with --preset smallest" || fail "batch is $bytes bytes"
  [[ "$n0" == "$(find "$LOTE" -type f | wc -l | tr -d ' ')" && "$s0" == "$(du -sk "$LOTE" | cut -f1)" ]] && ok "originals unchanged"
fi
echo "RELEASE $TAG VERIFIED"

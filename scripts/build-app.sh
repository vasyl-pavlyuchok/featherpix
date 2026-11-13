#!/usr/bin/env bash
# Builds Featherpix.app (and featherpix-cli) from source with swiftc — no Xcode project needed.
# Usage: scripts/build-app.sh            -> universal (x86_64 + arm64) if vendor/ has both encoder sets
#        ARCHS=x86_64 scripts/build-app.sh
# Needs: vendor/<arch>/{cwebp,avifenc,cjpeg,ffmpeg} from scripts/build-encoders.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(cat VERSION)"
ARCHS="${ARCHS:-x86_64 arm64}"
MIN_MACOS=13.0
BUILD="$ROOT/build"
APP="$BUILD/Featherpix.app"
rm -rf "$BUILD"; mkdir -p "$BUILD/obj"

CORE=(Sources/Core/*.swift)
APP_SRC=(Sources/App/*.swift)
CLI_SRC=(Sources/CLI/*.swift)

lipo_or_copy() { # out in...
  local out="$1"; shift
  if [[ $# -eq 1 ]]; then cp "$1" "$out"; else lipo -create "$@" -output "$out"; fi
}

app_bins=(); cli_bins=(); cwebp_bins=(); avif_bins=(); cjpeg_bins=(); ffmpeg_bins=()
for a in $ARCHS; do
  [[ -x "vendor/$a/cwebp" && -x "vendor/$a/avifenc" && -x "vendor/$a/cjpeg" && -x "vendor/$a/ffmpeg" ]] || { echo "missing vendor/$a encoders (run scripts/build-encoders.sh on $a)" >&2; exit 1; }
  echo "• swiftc $a"
  swiftc -swift-version 5 -O -parse-as-library -target "$a-apple-macos$MIN_MACOS" \
    "${CORE[@]}" "${APP_SRC[@]}" -o "$BUILD/obj/Featherpix-$a"
  swiftc -swift-version 5 -O -target "$a-apple-macos$MIN_MACOS" \
    "${CORE[@]}" "${CLI_SRC[@]}" -o "$BUILD/obj/featherpix-cli-$a"
  app_bins+=("$BUILD/obj/Featherpix-$a"); cli_bins+=("$BUILD/obj/featherpix-cli-$a")
  cwebp_bins+=("vendor/$a/cwebp"); avif_bins+=("vendor/$a/avifenc"); cjpeg_bins+=("vendor/$a/cjpeg"); ffmpeg_bins+=("vendor/$a/ffmpeg")
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
lipo_or_copy "$APP/Contents/MacOS/Featherpix" "${app_bins[@]}"
lipo_or_copy "$APP/Contents/Resources/bin/cwebp" "${cwebp_bins[@]}"
lipo_or_copy "$APP/Contents/Resources/bin/avifenc" "${avif_bins[@]}"
lipo_or_copy "$APP/Contents/Resources/bin/cjpeg" "${cjpeg_bins[@]}"
lipo_or_copy "$APP/Contents/Resources/bin/ffmpeg" "${ffmpeg_bins[@]}"
lipo_or_copy "$APP/Contents/Resources/bin/featherpix-cli" "${cli_bins[@]}"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/licenses"
for a in $ARCHS; do cp -n vendor/$a/licenses/* "$APP/Contents/Resources/licenses/" 2>/dev/null || true; done
for l in libavif libwebp-COPYING libwebp-PATENTS mozjpeg-LICENSE ffmpeg-COPYING.LGPLv2.1 ffmpeg-LICENSE.md ffmpeg-SOURCE-AND-BUILD libvpx-LICENSE libvpx-PATENTS opus-COPYING; do
  ls "$APP/Contents/Resources/licenses/" | grep -q "$l" || { echo "third-party license text missing: $l" >&2; exit 1; }
done
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature, inside-out (nested executables first). Required on Apple Silicon.
for b in "$APP/Contents/Resources/bin/"*; do codesign --force --sign - --timestamp=none "$b"; done
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

# Every shipped executable must contain every requested architecture.
for b in "$APP/Contents/MacOS/Featherpix" "$APP/Contents/Resources/bin/"*; do
  [[ -d "$b" ]] && continue
  got="$(lipo -archs "$b")"
  for a in $ARCHS; do [[ " $got " == *" $a "* ]] || { echo "$b lacks $a (has: $got)" >&2; exit 1; }; done
done

# Stable artifact name (no version) so releases/latest/download/Featherpix-macOS.zip never breaks.
suffix="$(echo "$ARCHS" | tr ' ' '\n' | sort | tr '\n' '-' | sed 's/-$//')"
if [[ "$suffix" == "arm64-x86_64" ]]; then ZIP="$BUILD/Featherpix-macOS.zip"; else ZIP="$BUILD/Featherpix-macOS-$suffix.zip"; fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Double-click installer: puts Featherpix.app in /Applications (never "relocated" elsewhere).
PKG="${ZIP%.zip}.pkg"
mkdir -p "$BUILD/pkgroot"; cp -R "$APP" "$BUILD/pkgroot/"
pkgbuild --analyze --root "$BUILD/pkgroot" "$BUILD/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$BUILD/component.plist"
pkgbuild --root "$BUILD/pkgroot" --component-plist "$BUILD/component.plist" \
  --identifier com.vasylpavlyuchok.featherpix --version "$VERSION" --install-location /Applications "$PKG" >/dev/null
rm -rf "$BUILD/pkgroot" "$BUILD/component.plist"

(cd "$BUILD" && for f in "$(basename "$ZIP")" "$(basename "$PKG")"; do shasum -a 256 "$f" > "$f.sha256"; done)
echo "OK: $ZIP"
echo "OK: $PKG"
cat "$ZIP.sha256" "$PKG.sha256"

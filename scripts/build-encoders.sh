#!/usr/bin/env bash
# Builds static cwebp and avifenc for ONE architecture from pinned sources.
# Usage: scripts/build-encoders.sh [x86_64|arm64]   (defaults to the host arch)
# Output: vendor/<arch>/cwebp, vendor/<arch>/avifenc
#
# Versions are pinned by commit, not by tag, so a moved tag cannot change what we ship.
set -euo pipefail

LIBWEBP_REPO=https://github.com/webmproject/libwebp.git
LIBWEBP_COMMIT=4fa21912338357f89e4fd51cf2368325b59e9bd9   # v1.6.0
LIBAVIF_REPO=https://github.com/AOMediaCodec/libavif.git
LIBAVIF_COMMIT=c5240fc79fe5c2407e10afd35f5505ef6333ea49   # v1.4.2
MOZJPEG_REPO=https://github.com/mozilla/mozjpeg.git
MOZJPEG_COMMIT=6c9f0897afa1c2738d7222a0a9ab49e8b536a267   # v4.1.5

ARCH="${1:-$(uname -m)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build-encoders/$ARCH"
OUT="$ROOT/vendor/$ARCH"
MIN_MACOS=13.0
JOBS="$(sysctl -n hw.ncpu)"
mkdir -p "$WORK" "$OUT"

if [[ "$ARCH" != "$(uname -m)" ]]; then
  echo "Cross-building is not supported: build $ARCH on a $ARCH machine (CI uses one runner per arch)." >&2
  exit 1
fi

fetch() { # repo commit dir
  if [[ ! -d "$3/.git" ]]; then git init -q "$3"; git -C "$3" remote add origin "$1"; fi
  git -C "$3" fetch -q --depth 1 origin "$2"
  git -C "$3" checkout -q --force FETCH_HEAD
  git -C "$3" clean -q -xdf
  [[ "$(git -C "$3" rev-parse HEAD)" == "$2" ]] || { echo "commit mismatch in $3" >&2; exit 1; }
}

COMMON=(-G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS")

# ---- cwebp (no external image libs: Featherpix feeds it PAM, which libwebp reads natively)
fetch "$LIBWEBP_REPO" "$LIBWEBP_COMMIT" "$WORK/libwebp"
cmake -S "$WORK/libwebp" -B "$WORK/libwebp/build" "${COMMON[@]}" \
  -DWEBP_BUILD_CWEBP=ON -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
  -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
  -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_USE_THREAD=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_PNG=ON -DCMAKE_DISABLE_FIND_PACKAGE_JPEG=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON -DCMAKE_DISABLE_FIND_PACKAGE_GIF=ON >/dev/null
cmake --build "$WORK/libwebp/build" --target cwebp -j "$JOBS" >/dev/null
cp "$WORK/libwebp/build/cwebp" "$OUT/cwebp"

# ---- avifenc (libaom + libyuv + libpng/zlib built locally and linked statically)
fetch "$LIBAVIF_REPO" "$LIBAVIF_COMMIT" "$WORK/libavif"
cmake -S "$WORK/libavif" -B "$WORK/libavif/build" "${COMMON[@]}" \
  -DAVIF_BUILD_APPS=ON -DAVIF_CODEC_AOM=LOCAL -DAVIF_CODEC_AOM_DECODE=OFF -DAVIF_CODEC_AOM_ENCODE=ON \
  -DAVIF_LIBYUV=LOCAL -DAVIF_LIBSHARPYUV=OFF -DAVIF_JPEG=LOCAL -DAVIF_ZLIBPNG=LOCAL \
  -DAVIF_LIBXML2=OFF -DAVIF_BUILD_TESTS=OFF >/dev/null
cmake --build "$WORK/libavif/build" --target avifenc -j "$JOBS" >/dev/null
cp "$WORK/libavif/build/avifenc" "$OUT/avifenc"

# ---- cjpeg from mozjpeg (much smaller JPEGs than macOS ImageIO; reads PPM natively)
fetch "$MOZJPEG_REPO" "$MOZJPEG_COMMIT" "$WORK/mozjpeg"
cmake -S "$WORK/mozjpeg" -B "$WORK/mozjpeg/build" "${COMMON[@]}" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DPNG_SUPPORTED=OFF -DWITH_TURBOJPEG=OFF -DWITH_JAVA=OFF >/dev/null
cmake --build "$WORK/mozjpeg/build" --target cjpeg-static -j "$JOBS" >/dev/null
cp "$WORK/mozjpeg/build/cjpeg-static" "$OUT/cjpeg"

# Collect the license texts of everything linked in (BSD/zlib licenses require shipping them).
LIC="$OUT/licenses"; mkdir -p "$LIC"
cp "$WORK/libwebp/COPYING" "$LIC/libwebp-COPYING.txt"
cp "$WORK/libwebp/PATENTS" "$LIC/libwebp-PATENTS.txt"
cp "$WORK/libavif/LICENSE" "$LIC/libavif-LICENSE.txt"
cp "$WORK/mozjpeg/LICENSE.md" "$LIC/mozjpeg-LICENSE.md.txt"
cp "$WORK/mozjpeg/README.ijg" "$LIC/mozjpeg-README.ijg.txt"
find "$WORK/libavif/build/_deps" "$WORK/libavif/build/libjpeg/src" "$WORK/libavif/ext" -maxdepth 3 -type f \
  \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'PATENTS*' -o -iname 'README.ijg' \) 2>/dev/null |
  while read -r f; do
    dep="$(echo "$f" | sed -E 's#.*/(_deps|ext|src)/([^/]+)/.*#\2#')"
    cp "$f" "$LIC/${dep}-$(basename "$f").txt"
  done

strip -x "$OUT/cwebp" "$OUT/avifenc" "$OUT/cjpeg"
for b in "$OUT/cwebp" "$OUT/avifenc" "$OUT/cjpeg"; do
  # Must not depend on anything outside the system (no Homebrew dylibs).
  if otool -L "$b" | tail -n +2 | grep -v -E '^\s*/(usr/lib|System)/' | grep -q .; then
    echo "$b links a non-system library:" >&2; otool -L "$b" >&2; exit 1
  fi
done
"$OUT/cwebp" -version
"$OUT/avifenc" --version | head -3
"$OUT/cjpeg" -version 2>&1 | head -1

# ---- ffmpeg (LGPL, VP9 + Opus for WebM) has its own script
"$ROOT/scripts/build-ffmpeg.sh" "$ARCH"
echo "OK: $OUT"

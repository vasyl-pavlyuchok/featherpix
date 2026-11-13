#!/usr/bin/env bash
# Builds a small, static, LGPL-only ffmpeg for ONE architecture: VP9 (libvpx) + Opus (libopus) into WebM.
# Usage: scripts/build-ffmpeg.sh [x86_64|arm64]   (defaults to the host arch)
# Output: vendor/<arch>/ffmpeg + its licenses in vendor/<arch>/licenses
#
# Rules (council PR117): no GPL parts (no x264/x265, no --enable-gpl), no network protocols,
# no autodetected system libraries, sources pinned by commit. H.264/HEVC stay with macOS VideoToolbox.
set -euo pipefail

FFMPEG_REPO=https://github.com/FFmpeg/FFmpeg.git
FFMPEG_COMMIT=3a0867c2bfda4a4d4309ca1a8cbdc6175e67f587   # n7.1.5
LIBVPX_REPO=https://github.com/webmproject/libvpx.git
LIBVPX_COMMIT=d168454ecd099805c675d4a98c66f4891373302a   # v1.15.2
OPUS_REPO=https://github.com/xiph/opus.git
OPUS_COMMIT=ddbe48383984d56acd9e1ab6a090c54ca6b735a6     # v1.5.2

ARCH="${1:-$(uname -m)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build-encoders/$ARCH"
PREFIX="$WORK/ffprefix"
OUT="$ROOT/vendor/$ARCH"
MIN_MACOS=13.0
JOBS="$(sysctl -n hw.ncpu)"
mkdir -p "$WORK" "$OUT" "$PREFIX"

if [[ "$ARCH" != "$(uname -m)" ]]; then
  echo "Cross-building is not supported: build $ARCH on a $ARCH machine." >&2
  exit 1
fi

fetch() { # repo commit dir
  if [[ ! -d "$3/.git" ]]; then git init -q "$3"; git -C "$3" remote add origin "$1"; fi
  git -C "$3" fetch -q --depth 1 origin "$2"
  git -C "$3" checkout -q --force FETCH_HEAD
  git -C "$3" clean -q -xdf
  [[ "$(git -C "$3" rev-parse HEAD)" == "$2" ]] || { echo "commit mismatch in $3" >&2; exit 1; }
}

SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -isysroot $SDK -O2"
export CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -isysroot $SDK"
# Some Command Line Tools installs lose their own libc++ headers; the SDK still has them.
CXX_FIX=()
if ! printf '#include <cstdint>\nint main(){}\n' | clang++ $FLAGS -x c++ -fsyntax-only - 2>/dev/null; then
  CXXFLAGS="$CXXFLAGS -I$SDK/usr/include/c++/v1"; export CXXFLAGS
  CXX_FIX=(--extra-cxxflags="-I$SDK/usr/include/c++/v1")
fi

# ---- libopus (BSD)
fetch "$OPUS_REPO" "$OPUS_COMMIT" "$WORK/opus"
cmake -S "$WORK/opus" -B "$WORK/opus/build" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null
cmake --build "$WORK/opus/build" -j "$JOBS" >/dev/null
cmake --install "$WORK/opus/build" >/dev/null

# ---- libvpx (BSD), VP9 only
fetch "$LIBVPX_REPO" "$LIBVPX_COMMIT" "$WORK/libvpx"
case "$ARCH" in
  x86_64) VPX_TARGET=x86_64-darwin22-gcc; VPX_AS=(--as=nasm) ;;
  arm64)  VPX_TARGET=arm64-darwin22-gcc;  VPX_AS=() ;;
esac
( cd "$WORK/libvpx" && make distclean >/dev/null 2>&1 || true
  ./configure --target="$VPX_TARGET" ${VPX_AS[@]+"${VPX_AS[@]}"} ${CXX_FIX[@]+"${CXX_FIX[@]}"} --prefix="$PREFIX" \
    --disable-shared --enable-static --enable-pic --disable-vp8 --enable-vp9 \
    --disable-examples --disable-tools --disable-docs --disable-unit-tests \
    --enable-vp9-highbitdepth --disable-webm-io --disable-libyuv >/dev/null
  make -j "$JOBS" >/dev/null && make install >/dev/null )

# ---- ffmpeg (LGPL 2.1+): only what Featherpix needs, nothing autodetected, files and pipes only
fetch "$FFMPEG_REPO" "$FFMPEG_COMMIT" "$WORK/ffmpeg"
FF_CONF=(
  --prefix="$PREFIX" --arch="$ARCH" --cc=clang
  --extra-cflags="$FLAGS -I$PREFIX/include" --extra-ldflags="$LDFLAGS -L$PREFIX/lib"
  --pkg-config-flags=--static
  --disable-gpl --disable-nonfree --disable-version3
  --disable-autodetect --disable-everything --disable-network --disable-doc --disable-debug
  --disable-ffplay --disable-ffprobe --disable-shared --enable-static
  --enable-ffmpeg --enable-avcodec --enable-avformat --enable-avfilter --enable-swscale --enable-swresample
  --enable-libvpx --enable-libopus
  --enable-protocol=file,pipe
  --enable-demuxer=mov,matroska
  --enable-muxer=webm,null
  --enable-decoder=h264,hevc,prores,mpeg4,mjpeg,vp9,aac,alac,mp3,opus,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_f32le
  --enable-encoder=libvpx_vp9,libopus,wrapped_avframe,pcm_s16le
  --enable-parser=h264,hevc,aac,vp9,opus,mpegaudio
  --enable-bsf=vp9_superframe,vp9_superframe_split
  --enable-filter=scale,format,aresample,aformat,anull,null,transpose,hflip,vflip,setsar,fps
)
[[ "$ARCH" == x86_64 ]] || FF_CONF+=(--disable-x86asm)
( cd "$WORK/ffmpeg" && make distclean >/dev/null 2>&1 || true
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ./configure "${FF_CONF[@]}" >/dev/null
  make -j "$JOBS" ffmpeg >/dev/null )
cp "$WORK/ffmpeg/ffmpeg" "$OUT/ffmpeg"
strip -x "$OUT/ffmpeg"

# No GPL, no non-system libraries.
"$OUT/ffmpeg" -hide_banner -L 2>/dev/null | grep -q "Lesser General Public License" \
  || { echo "ffmpeg is not LGPL" >&2; exit 1; }
if "$OUT/ffmpeg" -hide_banner -buildconf 2>/dev/null | grep -q -- "--enable-gpl"; then
  echo "ffmpeg was built with GPL parts" >&2; exit 1
fi
if otool -L "$OUT/ffmpeg" | tail -n +2 | grep -v -E '^\s*/(usr/lib|System)/' | grep -q .; then
  echo "ffmpeg links a non-system library:" >&2; otool -L "$OUT/ffmpeg" >&2; exit 1
fi

LIC="$OUT/licenses"; mkdir -p "$LIC"
cp "$WORK/ffmpeg/COPYING.LGPLv2.1" "$LIC/ffmpeg-COPYING.LGPLv2.1.txt"
cp "$WORK/ffmpeg/LICENSE.md" "$LIC/ffmpeg-LICENSE.md.txt"
cp "$WORK/libvpx/LICENSE" "$LIC/libvpx-LICENSE.txt"
cp "$WORK/libvpx/PATENTS" "$LIC/libvpx-PATENTS.txt"
cp "$WORK/opus/COPYING" "$LIC/opus-COPYING.txt"
{ echo "FFmpeg source: $FFMPEG_REPO at commit $FFMPEG_COMMIT (n7.1.5), unmodified."
  echo "libvpx source: $LIBVPX_REPO at commit $LIBVPX_COMMIT (v1.15.2), unmodified."
  echo "Opus source:   $OPUS_REPO at commit $OPUS_COMMIT (v1.5.2), unmodified."
  echo "The same source is attached to every Featherpix release as ffmpeg-n7.1.5-source.tar.gz:"
  echo "  https://github.com/vasyl-pavlyuchok/featherpix/releases"
  echo "You may replace Contents/Resources/bin/ffmpeg with your own build; then re-sign with"
  echo "  codesign --force --sign - Featherpix.app/Contents/Resources/bin/ffmpeg && codesign --force --sign - Featherpix.app"
  echo "Built by scripts/build-ffmpeg.sh in https://github.com/vasyl-pavlyuchok/featherpix with:"
  "$OUT/ffmpeg" -hide_banner -buildconf 2>/dev/null
} > "$LIC/ffmpeg-SOURCE-AND-BUILD.txt"

"$OUT/ffmpeg" -hide_banner -version | head -1
echo "OK: $OUT/ffmpeg"

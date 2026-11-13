# Third-party software bundled in Featherpix.app

Featherpix ships four command-line tools, built from source at pinned commits
(see `scripts/build-encoders.sh` and `scripts/build-ffmpeg.sh`) and statically linked:

| Component | Version | License | Source |
|---|---|---|---|
| libwebp / cwebp | 1.6.0 | BSD-3-Clause | https://chromium.googlesource.com/webm/libwebp |
| libavif / avifenc | 1.4.2 | BSD-2-Clause | https://github.com/AOMediaCodec/libavif |
| mozjpeg / cjpeg | 4.1.5 | IJG + BSD-3-Clause + zlib | https://github.com/mozilla/mozjpeg |
| libaom (AV1 encoder, inside avifenc) | as pinned by libavif 1.4.2 | BSD-2-Clause + AOM Patent License 1.0 | https://aomedia.googlesource.com/aom |
| libyuv (inside avifenc) | as pinned by libavif 1.4.2 | BSD-3-Clause | https://chromium.googlesource.com/libyuv/libyuv |
| libjpeg-turbo (inside avifenc) | as pinned by libavif 1.4.2 | IJG + BSD-3-Clause + zlib | https://github.com/libjpeg-turbo/libjpeg-turbo |
| libpng + zlib (inside avifenc) | as pinned by libavif 1.4.2 | libpng / zlib licenses | https://github.com/pnggroup/libpng · https://zlib.net |
| FFmpeg / ffmpeg | n7.1.5 (commit 3a0867c2), unmodified | LGPL-2.1-or-later | https://github.com/FFmpeg/FFmpeg |
| libvpx (VP9, inside ffmpeg) | v1.15.2 (commit d168454e) | BSD-3-Clause + patent grant | https://github.com/webmproject/libvpx |
| libopus (Opus, inside ffmpeg) | v1.5.2 (commit ddbe4838) | BSD-3-Clause | https://github.com/xiph/opus |

**About FFmpeg (LGPL).** This product uses FFmpeg (https://ffmpeg.org), licensed under the GNU Lesser General
Public License v2.1 or later, built unmodified with `--disable-gpl --disable-nonfree --disable-version3`. It runs as a
separate program (`Featherpix.app/Contents/Resources/bin/ffmpeg`); Featherpix does not link it.

- **Corresponding source:** every Featherpix release on GitHub (from 2.1.0) includes `ffmpeg-n7.1.5-source.tar.gz`
  (commit 3a0867c2) with its sha256, together with the libvpx and opus sources. The exact configure line ships inside
  the app in `licenses/ffmpeg-SOURCE-AND-BUILD.txt`, and `scripts/build-ffmpeg.sh` rebuilds the binary.
- **Replacing it:** you may replace that file with your own build, then re-sign the app:
  `codesign --force --sign - Featherpix.app/Contents/Resources/bin/ffmpeg` and
  `codesign --force --sign - Featherpix.app`. Nothing in the Featherpix license restricts modifying or
  reverse-engineering FFmpeg for that purpose.
- FFmpeg is a trademark of Fabrice Bellard. This ffmpeg build includes software decoders for H.264, HEVC, AAC, MP3
  and MPEG-4 (to read your videos); they may be covered by third-party patents in some jurisdictions. H.264 and HEVC
  are *encoded* by macOS (VideoToolbox); no x264 or x265 (GPL) is included.

The full license texts ship inside the app in `Featherpix.app/Contents/Resources/licenses/`.
This software is based in part on the work of the Independent JPEG Group.

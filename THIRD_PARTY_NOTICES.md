# Third-party software bundled in Featherpix.app

Featherpix ships three command-line encoders, built from source at pinned commits
(see `scripts/build-encoders.sh`) and statically linked:

| Component | Version | License | Source |
|---|---|---|---|
| libwebp / cwebp | 1.6.0 | BSD-3-Clause | https://chromium.googlesource.com/webm/libwebp |
| libavif / avifenc | 1.4.2 | BSD-2-Clause | https://github.com/AOMediaCodec/libavif |
| mozjpeg / cjpeg | 4.1.5 | IJG + BSD-3-Clause + zlib | https://github.com/mozilla/mozjpeg |
| libaom (AV1 encoder, inside avifenc) | as pinned by libavif 1.4.2 | BSD-2-Clause + AOM Patent License 1.0 | https://aomedia.googlesource.com/aom |
| libyuv (inside avifenc) | as pinned by libavif 1.4.2 | BSD-3-Clause | https://chromium.googlesource.com/libyuv/libyuv |
| libjpeg-turbo (inside avifenc) | as pinned by libavif 1.4.2 | IJG + BSD-3-Clause + zlib | https://github.com/libjpeg-turbo/libjpeg-turbo |
| libpng + zlib (inside avifenc) | as pinned by libavif 1.4.2 | libpng / zlib licenses | https://github.com/pnggroup/libpng · https://zlib.net |

The full license texts ship inside the app in `Featherpix.app/Contents/Resources/licenses/`.
This software is based in part on the work of the Independent JPEG Group.

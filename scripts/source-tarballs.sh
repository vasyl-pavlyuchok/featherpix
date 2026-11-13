#!/usr/bin/env bash
# Corresponding source for the bundled LGPL ffmpeg (LGPL 2.1 §4) and its BSD libraries, attached to every release.
# Usage: scripts/source-tarballs.sh   -> build/<name>-source.tar.gz + .sha256
# Commits are read from scripts/build-ffmpeg.sh so the source always matches what was built.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"; mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
val() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$ROOT/scripts/build-ffmpeg.sh"; }

pack() { # name repo commit
  local d="$WORK/$1"
  git init -q "$d"; git -C "$d" remote add origin "$2"
  git -C "$d" fetch -q --depth 1 origin "$3"
  git -C "$d" checkout -q FETCH_HEAD
  [[ "$(git -C "$d" rev-parse HEAD)" == "$3" ]] || { echo "commit mismatch for $1" >&2; exit 1; }
  git -C "$d" archive --format=tar.gz --prefix="$1/" HEAD > "$OUT/$1-source.tar.gz"
  ( cd "$OUT" && shasum -a 256 "$1-source.tar.gz" > "$1-source.tar.gz.sha256" )
  echo "packed $1 ($3)"
}
pack ffmpeg-n7.1.5 "$(val FFMPEG_REPO)" "$(val FFMPEG_COMMIT)"
pack libvpx-v1.15.2 "$(val LIBVPX_REPO)" "$(val LIBVPX_COMMIT)"
pack opus-v1.5.2 "$(val OPUS_REPO)" "$(val OPUS_COMMIT)"

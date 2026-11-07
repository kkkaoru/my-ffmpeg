#!/usr/bin/env bash
# Builds ffmpeg and ffprobe for each flavor into out/<platform>/<flavor>/.
# ./build.sh [macos-arm64] [windows-x64]     Needs clang, make, ninja and python3.
set -euo pipefail
cd "$(dirname "$0")"
root=$PWD
# shellcheck disable=SC1091
. ./versions.sh
export TMPDIR=$root/tmp
# The caller's flags would reach meson and pkgconf.
unset CFLAGS CPPFLAGS LDFLAGS PKG_CONFIG_PATH
export PATH=$root/tools/bin:$root/tools/llvm-mingw/bin:$PATH
mkdir -p "$TMPDIR" downloads tools/bin src
# Low priority: a build must not starve whatever else the machine is doing.
jobs=${JOBS:-6}
low="taskpolicy -b"

fetch() { # url sha256
  local file="downloads/${1##*/}"
  [ -f "$file" ] || curl -fL --retry 3 -o "$file" "$1"
  echo "$2  $file" | shasum -a 256 -c - >/dev/null
}

unpack() { # archive directory
  [ -d "$2" ] || { mkdir -p "$2"; tar xf "$1" -C "$2" --strip-components=1; }
}

tools_common() {
  fetch "https://distfiles.ariadne.space/pkgconf/pkgconf-$PKGCONF_VERSION.tar.xz" "$PKGCONF_SHA256"
  if [ ! -x tools/bin/pkg-config ]; then
    unpack "downloads/pkgconf-$PKGCONF_VERSION.tar.xz" tools/pkgconf-src
    (cd tools/pkgconf-src && ./configure --prefix="$root/tools" --disable-shared >/dev/null && $low make -j"$jobs" install >/dev/null)
    ln -sf pkgconf tools/bin/pkg-config
  fi
  fetch "https://github.com/mesonbuild/meson/releases/download/$MESON_VERSION/meson-$MESON_VERSION.tar.gz" "$MESON_SHA256"
  unpack "downloads/meson-$MESON_VERSION.tar.gz" tools/meson
}

tools_windows() {
  fetch "https://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.xz" "$NASM_SHA256"
  if [ ! -x tools/bin/nasm ]; then
    unpack "downloads/nasm-$NASM_VERSION.tar.xz" tools/nasm-src
    (cd tools/nasm-src && ./configure >/dev/null && $low make -j"$jobs" nasm >/dev/null && cp nasm "$root/tools/bin/")
  fi
  local name="llvm-mingw-$LLVM_MINGW_VERSION-ucrt-macos-universal.tar.xz"
  fetch "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/$name" "$LLVM_MINGW_SHA256"
  unpack "downloads/$name" tools/llvm-mingw
}

build_dav1d() { # platform
  local dir="build/$1/dav1d" prefix="$root/build/$1/dav1d-prefix" cross=()
  [ -f "$prefix/lib/libdav1d.a" ] && return
  if [ "$1" = windows-x64 ]; then
    cat >"build/$1/dav1d.cross" <<CROSS
[binaries]
c = 'x86_64-w64-mingw32-clang'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
windres = 'x86_64-w64-mingw32-windres'
nasm = 'nasm'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
CROSS
    cross=(--cross-file "build/$1/dav1d.cross")
  fi
  rm -rf "$dir"
  python3 tools/meson/meson.py setup "$dir" src/dav1d ${cross[@]+"${cross[@]}"} --prefix "$prefix" --libdir lib \
    --buildtype release --default-library static -Denable_tools=false -Denable_tests=false -Denable_examples=false >/dev/null
  $low python3 tools/meson/meson.py install -C "$dir" >/dev/null
}

profiles_of() { # platform flavor
  echo profiles/common.conf
  [ "$2" = video ] || echo profiles/audio.conf
  if [ "$2" != audio ]; then
    echo profiles/video.conf
    [ "$1" != macos-arm64 ] || echo profiles/video-macos.conf
  fi
}

build_flavor() { # platform flavor
  local platform=$1 flavor=$2 dir="build/$1/$2" out="out/$1/$2" exe=""
  local flags
  # shellcheck disable=SC2046
  flags=$(sed 's/#.*//' $(profiles_of "$platform" "$flavor") | tr -s ' \n' ' ')
  if [ "$platform" = windows-x64 ]; then
    exe=.exe
    flags="--enable-cross-compile --arch=x86_64 --target-os=mingw32 --cross-prefix=x86_64-w64-mingw32- --cc=x86_64-w64-mingw32-clang --pkg-config=pkg-config --extra-ldflags=-static $flags"
  fi
  mkdir -p "$dir" "$out"
  # Relative paths only: the configure line ends up inside the binary and in the release.
  if [ "$(cat "$dir/.flags" 2>/dev/null)" != "$flags" ]; then
    # shellcheck disable=SC2086
    (cd "$dir" && PKG_CONFIG_LIBDIR="$root/build/$platform/dav1d-prefix/lib/pkgconfig" ../../../src/ffmpeg/configure $flags >configure.log) ||
      { tail -20 "$dir/ffbuild/config.log"; return 1; }
    # configure makes the source path absolute and assert messages keep it; not a flag, so the configure line stays clean.
    echo "CPPFLAGS += -fmacro-prefix-map=$root/src/ffmpeg/=" >>"$dir/ffbuild/config.mak"
    echo "$flags" >"$dir/.flags"
  fi
  $low make -C "$dir" -j"$jobs" "ffmpeg$exe" "ffprobe$exe" >"$dir/make.log" 2>&1 || { tail -30 "$dir/make.log"; return 1; }
  cp "$dir/ffmpeg$exe" "$dir/ffprobe$exe" "$out/"
  echo "./configure $flags" >"$out/configure-line.txt"
  du -k "$out"/ffmpeg* "$out"/ffprobe*
}

fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
fetch "https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz" "$DAV1D_SHA256"
unpack "downloads/ffmpeg-$FFMPEG_VERSION.tar.xz" src/ffmpeg
unpack "downloads/dav1d-$DAV1D_VERSION.tar.xz" src/dav1d
tools_common

[ $# -gt 0 ] || set -- macos-arm64 windows-x64
for platform in "$@"; do
  case "$platform" in
    macos-arm64) export MACOSX_DEPLOYMENT_TARGET=$MACOS_MINIMUM ;;
    windows-x64) unset MACOSX_DEPLOYMENT_TARGET; tools_windows ;;
    *) echo "unknown platform: $platform" >&2; exit 2 ;;
  esac
  mkdir -p "build/$platform"
  build_dav1d "$platform"
  for flavor in ${FLAVORS:-av video audio}; do
    build_flavor "$platform" "$flavor"
  done
done

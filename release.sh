#!/usr/bin/env bash
# Builds, tests and packages, then publishes a GitHub release. Publishes nothing unless the tests pass.
# ./release.sh TAG     DRY_RUN=1 stops before publishing; PLATFORMS picks what is built.
# FIXTURE_FFMPEG and REF_FFMPEG go to test.sh.
set -euo pipefail
cd "$(dirname "$0")"
root=$PWD
. ./versions.sh
tag=${1:?usage: ./release.sh TAG}
platforms=${PLATFORMS:-macos-arm64 windows-x64}
if [ -z "${DRY_RUN:-}" ]; then
  [ -z "$(git status --porcelain)" ] || { echo "commit first: a release must match its tag" >&2; exit 1; }
  ! gh release view "$tag" >/dev/null 2>&1 || { echo "$tag exists; use a new tag" >&2; exit 1; }
fi
# shellcheck disable=SC2086
./build.sh $platforms
# shellcheck disable=SC2086
./test.sh $platforms

dist=dist/$tag
stage=build/package
rm -rf "$dist" "$stage"
mkdir -p "$dist" "$stage"
ffmpeg_tar=downloads/ffmpeg-$FFMPEG_VERSION.tar.xz
dav1d_tar=downloads/dav1d-$DAV1D_VERSION.tar.xz
cp "$ffmpeg_tar" "$dav1d_tar" NOTICE "$dist/"
cp src/ffmpeg/COPYING.LGPLv2.1 "$dist/LICENSE-LGPL-2.1.txt"
cp src/dav1d/COPYING "$dist/LICENSE-dav1d.txt"
: >"$dist/configure-lines.txt"

for platform in $platforms; do
  for flavor in av video audio; do
    name=my-ffmpeg-$tag-$platform-$flavor
    dir=$stage/$name
    mkdir -p "$dir"
    cp out/"$platform"/"$flavor"/ff* out/"$platform"/"$flavor"/configure-line.txt NOTICE "$dist/LICENSE-LGPL-2.1.txt" "$dir/"
    [ "$flavor" = audio ] || cp "$dist/LICENSE-dav1d.txt" "$dir/"
    echo "$platform $flavor: $(cat "$dir/configure-line.txt")" >>"$dist/configure-lines.txt"
    if [ "$platform" = windows-x64 ]; then
      cp tools/llvm-mingw/LICENSE.TXT "$dir/LICENSE-llvm.txt"
      cp tools/llvm-mingw/x86_64-w64-mingw32/share/mingw32/COPYING.MinGW-w64-runtime.txt "$dir/LICENSE-mingw-w64-runtime.txt"
      (cd "$stage" && zip -qrX "$root/$dist/$name.zip" "$name")
    else
      # No user name of the build machine and no macOS metadata in the archive.
      COPYFILE_DISABLE=1 tar -C "$stage" --no-xattrs --no-mac-metadata --uid 0 --gid 0 --uname root --gname wheel -cJf "$dist/$name.tar.xz" "$name"
    fi
  done
done
(cd "$dist" && shasum -a 256 -- * >SHA256SUMS)
cat "$dist/SHA256SUMS"
[ -z "${DRY_RUN:-}" ] || { echo "dry run: nothing published"; exit 0; }

git push origin HEAD
cat >"$stage/notes.md" <<NOTES
Unofficial minimal LGPL builds of FFmpeg $FFMPEG_VERSION with dav1d $DAV1D_VERSION. Not made or endorsed by the FFmpeg project.

| Flavor | For |
| --- | --- |
| \`av\` | audio to WAV, video to raw frames |
| \`video\` | video to raw frames |
| \`audio\` | audio to WAV |

Windows binaries were cross-built and have not been run. See the README for what is enabled and how to rebuild.
NOTES
gh release create "$tag" "$dist"/* --target "$(git rev-parse HEAD)" --title "$tag" --notes-file "$stage/notes.md"

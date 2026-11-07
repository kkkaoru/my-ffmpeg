#!/usr/bin/env bash
# Regression test on synthetic videos, with the arguments Transcribe Captions runs.
# ./test.sh [macos-arm64] [windows-x64]     (default: what out/ holds)
#   FIXTURE_FFMPEG  makes the test videos; needs libx264, libx265, libvpx, libsvtav1, libmp3lame, libopus (default: ffmpeg)
#   REF_FFMPEG      optional full build to compare WAV and frame bytes against
set -uo pipefail
cd "$(dirname "$0")" || exit
root=$PWD
export TMPDIR=$root/tmp
# shellcheck disable=SC1091
. ./versions.sh
fixture=${FIXTURE_FFMPEG:-ffmpeg}
ref=${REF_FFMPEG:-}
videos=build/fixtures
work=build/test
mkdir -p "$TMPDIR" "$videos" "$work" out
report=out/test-report.txt
: >"$report"
passes=0 fails=0 diffs=0

pass() { passes=$((passes + 1)); echo "PASS $*" >>"$report"; }
fail() { fails=$((fails + 1)); echo "FAIL $*" | tee -a "$report"; }
diffr() { diffs=$((diffs + 1)); echo "DIFF $*" | tee -a "$report"; }
check() { # label command...
  local label=$1; shift
  if "$@" >/dev/null 2>"$work/err"; then pass "$label"; else fail "$label: $(tail -1 "$work/err")"; fi
}

# name|video arguments|audio arguments  The name ends in the container's extension.
FIXTURES='
h264-aac.mp4|-c:v libx264 -pix_fmt yuv420p|-c:a aac
h264-10bit-aac.mp4|-c:v libx264 -pix_fmt yuv420p10le|-c:a aac
hevc-aac.mp4|-c:v libx265 -tag:v hvc1 -x265-params log-level=error -pix_fmt yuv420p|-c:a aac
hevc-10bit-mp3.mp4|-c:v libx265 -tag:v hvc1 -x265-params log-level=error -pix_fmt yuv420p10le|-c:a libmp3lame
av1-aac.mp4|-c:v libsvtav1 -preset 12 -pix_fmt yuv420p|-c:a aac
vp9-opus.mp4|-c:v libvpx-vp9 -cpu-used 8 -pix_fmt yuv420p|-c:a libopus
mpeg4-aac.mp4|-c:v mpeg4|-c:a aac
h264-aac.m4v|-c:v libx264 -pix_fmt yuv420p|-c:a aac
h264-alac.mov|-c:v libx264 -pix_fmt yuv420p|-c:a alac
hevc-pcm_s16le.mov|-c:v libx265 -tag:v hvc1 -x265-params log-level=error -pix_fmt yuv420p|-c:a pcm_s16le
prores-pcm_s24le.mov|-c:v prores_ks -profile:v 2 -pix_fmt yuv422p10le|-c:a pcm_s24le
dnxhd-pcm_s16be.mov|-c:v dnxhd -profile:v dnxhr_lb -pix_fmt yuv422p|-c:a pcm_s16be
mjpeg-pcm_alaw.mov|-c:v mjpeg -pix_fmt yuvj420p|-c:a pcm_alaw
h264-flac.mkv|-c:v libx264 -pix_fmt yuv420p|-c:a flac
hevc-ac3.mkv|-c:v libx265 -x265-params log-level=error -pix_fmt yuv420p|-c:a ac3
av1-10bit-opus.mkv|-c:v libsvtav1 -preset 12 -pix_fmt yuv420p10le|-c:a libopus
vp9-eac3.mkv|-c:v libvpx-vp9 -cpu-used 8 -pix_fmt yuv420p|-c:a eac3
mpeg2-mp3.mkv|-c:v mpeg2video -pix_fmt yuv420p|-c:a libmp3lame
vp8-vorbis.webm|-c:v libvpx -cpu-used 8 -pix_fmt yuv420p|-c:a vorbis -strict -2 -ac 2
vp9-opus.webm|-c:v libvpx-vp9 -cpu-used 8 -pix_fmt yuv420p|-c:a libopus
av1-opus.webm|-c:v libsvtav1 -preset 12 -pix_fmt yuv420p|-c:a libopus
h264-mp3.avi|-c:v libx264 -pix_fmt yuv420p|-c:a libmp3lame
mpeg4-pcm_s16le.avi|-c:v mpeg4|-c:a pcm_s16le
mjpeg-pcm_u8.avi|-c:v mjpeg -pix_fmt yuvj420p|-c:a pcm_u8
h264-ac3.mts|-c:v libx264 -pix_fmt yuv420p|-c:a ac3
h264-pcm_bluray.mts|-c:v libx264 -pix_fmt yuv420p -mpegts_m2ts_mode 1|-c:a pcm_bluray
hevc-aac.mts|-c:v libx265 -x265-params log-level=error -pix_fmt yuv420p|-c:a aac
mpeg2-mp2.ts|-c:v mpeg2video -pix_fmt yuv420p|-c:a mp2
h264-aac.ts|-c:v libx264 -pix_fmt yuv420p|-c:a aac
hevc-eac3.ts|-c:v libx265 -x265-params log-level=error -pix_fmt yuv420p|-c:a eac3
mpeg2-pcm_s16le.mxf|-c:v mpeg2video -pix_fmt yuv422p -b:v 20M -g 1|-c:a pcm_s16le
h264-pcm_s24le.mxf|-c:v libx264 -pix_fmt yuv420p -profile:v high -x264-params intra-refresh=0|-c:a pcm_s24le
dnxhd-pcm_s16le.mxf|-c:v dnxhd -profile:v dnxhr_lb -pix_fmt yuv422p|-c:a pcm_s16le
dvvideo-pcm_s16le.avi|-c:v dvvideo -s 720x480 -r 30000/1001 -pix_fmt yuv411p|-c:a pcm_s16le
dvvideo-pcm_s16be.mov|-c:v dvvideo -s 720x576 -r 25 -pix_fmt yuv420p|-c:a pcm_s16be
mpeg1-mp2.mkv|-c:v mpeg1video -pix_fmt yuv420p|-c:a mp2
mpeg1-mp2.avi|-c:v mpeg1video -pix_fmt yuv420p|-c:a mp2
rawvideo-adpcm_ms.avi|-c:v rawvideo -s 320x180 -pix_fmt yuv420p|-c:a adpcm_ms
rawvideo-adpcm_ima_wav.avi|-c:v rawvideo -s 320x180 -pix_fmt bgr24|-c:a adpcm_ima_wav
rawvideo-pcm_s16le.mov|-c:v rawvideo -s 320x180 -pix_fmt uyvy422|-c:a pcm_s16le
h264-truehd.mkv|-c:v libx264 -pix_fmt yuv420p|-c:a truehd -strict -2 -ac 2
h264-mlp.mkv|-c:v libx264 -pix_fmt yuv420p|-c:a mlp -strict -2 -ac 2
'

make_fixtures() {
  local name vargs aargs input
  input="-f lavfi -i testsrc2=size=1280x720:rate=30:duration=3 -f lavfi -i sine=frequency=440:sample_rate=48000:duration=3 -g 30"
  while IFS='|' read -r name vargs aargs; do
    [ -n "$name" ] && [ ! -s "$videos/$name" ] || continue
    # shellcheck disable=SC2086
    "$fixture" -hide_banner -loglevel error -y $input $vargs $aargs "$videos/$name" </dev/null ||
      fail "fixture $name could not be made"
  done <<<"$FIXTURES"
  # No encoder writes MP1, so this is silent Layer I frames by hand: 48 kHz mono 32 kb/s is 32 bytes, zero allocation.
  if [ ! -s "$videos/h264-mp1.mkv" ]; then
    python3 -c "import sys; sys.stdout.buffer.write((b'\xff\xff\x14\xc0' + bytes(28)) * 375)" >"$work/silence.mp1"
    "$fixture" -hide_banner -loglevel error -y -i "$videos/h264-aac.mp4" -f mp3 -i "$work/silence.mp1" -map 0:v -map 1:a -c copy -shortest "$videos/h264-mp1.mkv"
  fi
  # A phone video: the same pixels with a rotation the player must apply.
  [ -s "$videos/rotated-h264-aac.mp4" ] || "$fixture" -hide_banner -loglevel error -y -display_rotation 90 -i "$videos/h264-aac.mp4" -c copy "$videos/rotated-h264-aac.mp4"
  # What must be refused: a codec and a container left out of every flavor.
  # shellcheck disable=SC2086
  [ -s "$work/ffv1-flac.mkv" ] || "$fixture" -hide_banner -loglevel error -y $input -c:v ffv1 -c:a flac "$work/ffv1-flac.mkv"
  [ -s "$work/h264-aac.flv" ] || "$fixture" -hide_banner -loglevel error -y -i "$videos/h264-aac.mp4" -c copy "$work/h264-aac.flv"
}

# The app's commands, verbatim: src-tauri/src/engines.rs and face.rs.
probe() { "$1" -v error -print_format json -show_format -show_streams "$2"; }
audio_wav() { "$1" -hide_banner -nostdin -i "$2" -vn -ac 1 -ar 16000 -c:a pcm_s16le -y "$3"; }
FRAME_FILTER='fps=1,scale=640:640:force_original_aspect_ratio=decrease,pad=640:640:(ow-iw)/2:(oh-ih)/2'
faces() { # ffmpeg video [extra input options]
  local bin=$1 video=$2; shift 2
  "$bin" -hide_banner -nostdin -loglevel error "$@" -skip_frame nokey -i "$video" -an -vf "$FRAME_FILTER" -pix_fmt rgb24 -f rawvideo -
}
frames_ok() { # file: a whole number of 640x640 RGB frames, at least one
  local size; size=$(stat -f %z "$1")
  [ "$size" -gt 0 ] && [ $((size % (640 * 640 * 3))) -eq 0 ]
}
hash_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

wav_check() { # label ffmpeg video
  if audio_wav "$2" "$3" "$work/out.wav" >/dev/null 2>"$work/err" && [ "$(stat -f %z "$work/out.wav")" -gt 44 ]; then
    pass "$1"
  else
    fail "$1: $(tail -1 "$work/err")"
  fi
}

faces_check() { # label ffmpeg video [options]
  local label=$1 bin=$2 video=$3; shift 3
  if faces "$bin" "$video" "$@" >"$work/out.rgb" 2>"$work/err" && frames_ok "$work/out.rgb"; then
    pass "$label"
  else
    fail "$label: $(tail -1 "$work/err")"
  fi
}

test_static() { # platform-independent facts of one macOS binary
  local bin=$1 label=$2 found
  found=$("$bin" -version 2>&1) || fail "$label -version"
  if grep -qE -- '--enable-(gpl|nonfree|version3)' <<<"$found"; then fail "$label has a non-LGPL-2.1 flag"; else pass "$label is LGPL-2.1"; fi
  found=$(otool -L "$bin" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/)')
  if [ -n "$found" ]; then fail "$label links $found"; else pass "$label links only the system"; fi
  found=$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')
  if [ "$found" = "$MACOS_MINIMUM" ]; then pass "$label minos $found"; else fail "$label minos $found"; fi
  check "$label is signed" codesign -v "$bin"
  if strings -a "$bin" | grep -E "/(Users|home|private/tmp)/" >/dev/null; then fail "$label holds a build-machine path"; else pass "$label holds no build-machine path"; fi
}

test_macos() {
  local d=out/macos-arm64 flavor bin_mp bin_fp name label video
  make_fixtures
  for flavor in av video audio; do
    [ -x "$d/$flavor/ffmpeg" ] || { fail "$flavor is not built"; continue; }
    test_static "$d/$flavor/ffmpeg" "$flavor/ffmpeg"
    test_static "$d/$flavor/ffprobe" "$flavor/ffprobe"
    bin_mp=$d/$flavor/ffmpeg bin_fp=$d/$flavor/ffprobe
    for video in "$videos"/*; do
      name=${video##*/}
      label="$flavor $name"
      probe "$bin_fp" "$video" >"$work/probe.json" 2>"$work/err" || fail "$label probe: $(tail -1 "$work/err")"
      if [ "$flavor" != audio ]; then
        if grep -q '"width": [1-9]' "$work/probe.json"; then pass "$label probe width"; else fail "$label probe found no video size"; fi
        case "$name" in
          # shortcut: AVI has no pts, so with B-frames -skip_frame nokey leaves timestamps fps drops, in upstream FFmpeg too; a full decode must still work.
          h264-*.avi) check "$label decodes" "$bin_mp" -hide_banner -nostdin -loglevel error -i "$video" -an -f rawvideo -y /dev/null ;;
          *)
            faces_check "$label faces+vt" "$bin_mp" "$video" -hwaccel videotoolbox
            faces_check "$label faces" "$bin_mp" "$video"
            ;;
        esac
      fi
      if [ "$flavor" != video ]; then
        if grep -q '"sample_rate"' "$work/probe.json"; then pass "$label probe audio"; else fail "$label probe found no audio"; fi
        wav_check "$label wav" "$bin_mp" "$video"
      fi
      [ "$flavor" = av ] && [ -n "$ref" ] && compare "$bin_mp" "$bin_fp" "$video" "$name"
    done
    test_refusals "$flavor" "$bin_mp"
  done
  test_decoder_choice "$d/av/ffmpeg"
  test_rotation "$d/av/ffmpeg"
}

compare() { # ffmpeg ffprobe video name
  local ours theirs fields="stream=codec_type,codec_name,profile,pix_fmt,width,height,sample_rate,channels:format=format_name"
  audio_wav "$ref" "$3" "$work/ref.wav" >/dev/null 2>&1 && audio_wav "$1" "$3" "$work/out.wav" >/dev/null 2>&1
  if [ "$(hash_of "$work/ref.wav")" = "$(hash_of "$work/out.wav")" ]; then pass "$4 wav matches reference"; else diffr "$4 wav differs from reference ($(stat -f %z "$work/ref.wav") vs $(stat -f %z "$work/out.wav") bytes)"; fi
  faces "$ref" "$3" -hwaccel videotoolbox >"$work/ref.rgb" 2>/dev/null
  faces "$1" "$3" -hwaccel videotoolbox >"$work/out.rgb" 2>/dev/null
  if [ "$(hash_of "$work/ref.rgb")" = "$(hash_of "$work/out.rgb")" ]; then pass "$4 frames match reference"; else diffr "$4 frames differ from reference ($(stat -f %z "$work/ref.rgb") vs $(stat -f %z "$work/out.rgb") bytes)"; fi
  theirs=$("${ref%/*}/ffprobe" -v error -show_entries "$fields" -of compact "$3" 2>&1)
  ours=$("$2" -v error -show_entries "$fields" -of compact "$3" 2>&1)
  if [ "$theirs" = "$ours" ]; then pass "$4 probe matches reference"; else diffr "$4 probe: [$theirs] vs [$ours]"; fi
}

test_refusals() { # flavor ffmpeg: unsupported input stops with a clear error instead of hanging or writing junk
  local out
  if [ "$1" != audio ]; then
    out=$(faces "$2" "$work/ffv1-flac.mkv" 2>&1 >/dev/null) && fail "$1 ffv1 was not refused"
    if grep -qiE 'decoder|codec' <<<"$out"; then pass "$1 ffv1 refused: $(head -1 <<<"$out")"; else fail "$1 ffv1 error unclear: $out"; fi
  fi
  out=$("$2" -hide_banner -nostdin -i "$work/h264-aac.flv" -f null - 2>&1) && fail "$1 flv was not refused"
  if grep -q 'Invalid data' <<<"$out"; then pass "$1 flv refused: $(tail -1 <<<"$out")"; else fail "$1 flv error unclear: $out"; fi
  out=$("$2" -hide_banner -nostdin -i http://127.0.0.1:9/x.mp4 -f null - 2>&1) && fail "$1 http was not refused"
  if grep -q 'Protocol not found' <<<"$out"; then pass "$1 has no network"; else fail "$1 http error unclear: $out"; fi
}

test_decoder_choice() { # ffmpeg: the decoder really used, not just the exit code
  local out
  out=$("$1" -hide_banner -nostdin -hwaccel videotoolbox -loglevel verbose -i "$videos/h264-aac.mp4" -an -frames:v 1 -f rawvideo -y /dev/null 2>&1)
  if grep -qi 'videotoolbox' <<<"$out"; then pass "h264 uses VideoToolbox"; else fail "h264 did not use VideoToolbox"; fi
  for file in av1-aac.mp4 av1-opus.webm av1-10bit-opus.mkv; do
    out=$("$1" -hide_banner -nostdin -loglevel verbose -i "$videos/$file" -an -frames:v 1 -f rawvideo -y /dev/null 2>&1)
    if grep -q 'libdav1d' <<<"$out"; then pass "$file decodes with dav1d"; else fail "$file did not use dav1d"; fi
  done
}

test_rotation() { # ffmpeg: a 1280x720 video turned 90 degrees fills the height, not the width
  faces "$1" "$videos/rotated-h264-aac.mp4" >"$work/rot.rgb" 2>"$work/err" || { fail "rotation: $(tail -1 "$work/err")"; return; }
  faces "$1" "$videos/h264-aac.mp4" >"$work/flat.rgb" 2>/dev/null
  if cmp -s "$work/rot.rgb" "$work/flat.rgb"; then fail "rotation was ignored"; else pass "rotation is applied"; fi
}

test_windows() {
  local d=out/windows-x64 flavor tool
  for flavor in av video audio; do
    for tool in ffmpeg ffprobe; do
      [ -s "$d/$flavor/$tool.exe" ] || { fail "windows $flavor/$tool.exe is not built"; continue; }
      if file "$d/$flavor/$tool.exe" | grep -q 'x86-64'; then pass "windows $flavor/$tool.exe is x64"; else fail "windows $flavor/$tool.exe is not x64"; fi
      tools/llvm-mingw/bin/llvm-objdump -p "$d/$flavor/$tool.exe" | awk '/DLL Name/{print tolower($3)}' >"$work/dlls"
      # Only DLLs Windows 10 and later carry.
      if grep -vE '^(api-ms-win-crt-.*|advapi32|bcrypt|gdi32|kernel32|ole32|oleaut32|psapi|shell32|shlwapi|user32|ws2_32)\.dll$' "$work/dlls" >"$work/odd"; then
        fail "windows $flavor/$tool.exe needs $(tr '\n' ' ' <"$work/odd")"
      else
        pass "windows $flavor/$tool.exe needs only system DLLs: $(tr '\n' ' ' <"$work/dlls")"
      fi
      if strings -a "$d/$flavor/$tool.exe" | grep -E "/(Users|home|private/tmp)/" >/dev/null; then fail "windows $flavor/$tool.exe holds a build-machine path"; else pass "windows $flavor/$tool.exe holds no build-machine path"; fi
    done
    if grep -qE '^#define CONFIG_(GPL|NONFREE|VERSION3) 1' "build/windows-x64/$flavor/config.h"; then fail "windows $flavor is not LGPL-2.1"; else pass "windows $flavor is LGPL-2.1"; fi
  done
  echo "NOT RUN: Windows binaries cannot be executed on this Mac" | tee -a "$report"
}

[ $# -gt 0 ] || { [ ! -d out/macos-arm64 ] || set -- "$@" macos-arm64; [ ! -d out/windows-x64 ] || set -- "$@" windows-x64; }
for platform in "$@"; do
  case "$platform" in
    macos-arm64) test_macos ;;
    windows-x64) test_windows ;;
    *) echo "unknown platform: $platform" >&2; exit 2 ;;
  esac
done
echo "passed $passes, failed $fails, differs from reference $diffs (details: $report)"
[ "$fails" -eq 0 ]

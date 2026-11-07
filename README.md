# my-ffmpeg

Small LGPL builds of `ffmpeg` and `ffprobe`, made for the bundled tools of a desktop subtitle app. They read local video and audio files and write WAV or raw frames, and nothing else.

**This is not an official FFmpeg release.** It is not made, endorsed or supported by the FFmpeg project. FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.

Download from [Releases](https://github.com/kkkaoru/my-ffmpeg/releases), for `macos-arm64` and `windows-x64`. Every archive holds `ffmpeg`, `ffprobe`, the licenses and the configure line.

## Flavors

| Flavor | Reads | Writes | Libraries |
| --- | --- | --- | --- |
| `av` | audio and video | WAV, raw frames | swresample, swscale, dav1d |
| `video` | video | raw frames | swscale, dav1d |
| `audio` | audio | WAV | swresample |

Each flavor is the profiles in [`profiles/`](profiles) put together: `common` plus `audio` and/or `video`, and `video-macos` for VideoToolbox.

## What is enabled

Everything starts from `--disable-everything --disable-autodetect`. No network: only the `file` and `pipe` protocols.

- **Containers:** mov (mp4, m4v, mov), matroska (mkv, webm), avi, mpegts (ts, mts, m2ts), mxf. With audio: also wav, aiff, flac, mp3, ogg, aac, ac3, eac3.
- **Video decoders:** H.264, HEVC, AV1 (dav1d), VP8, VP9, MPEG-2, MPEG-4 part 2, ProRes, DNxHD/DNxHR, MJPEG.
- **Audio decoders:** AAC, AAC LATM, MP3, MP2, Opus, Vorbis, FLAC, ALAC, AC-3, E-AC-3, DTS core, SMPTE 302M, common PCM (including Blu-ray and DVD).
- **Hardware decoding (macOS):** VideoToolbox for H.264, HEVC, MPEG-2, MPEG-4, ProRes, VP9. AV1 always decodes on the CPU with dav1d, so it also works on Macs without an AV1 hardware decoder.
- **Filters:** `aresample`, `fps`, `scale`, `pad`, and those FFmpeg always pulls in (such as `format`, `transpose` for rotated videos).
- **Output:** `pcm_s16le` in WAV, `rawvideo`.

Anything else stops with an error, for example `Decoding requested, but no decoder found for: ffv1` or, for a container that is not listed, `Invalid data found when processing input`.

macOS binaries need macOS 13 or later and link only system libraries. They are ad-hoc signed by the linker, not notarized. Windows binaries need Windows 10 or later and only system DLLs.

## Building

On an Apple Silicon Mac with Xcode's command line tools, `python3` and `ninja`:

```sh
./build.sh                 # or: ./build.sh macos-arm64
FIXTURE_FFMPEG=ffmpeg ./test.sh
```

`build.sh` downloads the versions pinned in [`versions.sh`](versions.sh), checks their SHA-256 and writes to `out/<platform>/<flavor>/`. Windows is cross-built on the Mac with [llvm-mingw](https://github.com/mstorsjo/llvm-mingw). Tools go to `tools/` inside the checkout and nothing is installed elsewhere.

`test.sh` makes synthetic videos with a full FFmpeg (`FIXTURE_FFMPEG`, which needs libx264, libx265, libvpx, libsvtav1, libmp3lame and libopus) and runs the app's probe, audio and frame commands on each flavor. With `REF_FFMPEG` it also compares the WAV and frame bytes with another build. Windows binaries are checked statically only, because they cannot run on a Mac.

`./release.sh TAG` builds, tests, packages and publishes a GitHub release of what this Mac built. `DRY_RUN=1` stops before publishing. The GitHub Actions workflow runs by hand only, and only reproduces the build.

## License

- The scripts and profiles in this repository: [MIT](LICENSE).
- The binaries in the releases are not MIT:
  - FFmpeg: LGPL-2.1-or-later, built without `--enable-gpl`, `--enable-version3` or `--enable-nonfree`. The source tar of each build is attached to its release.
  - dav1d (in `av` and `video`): BSD-2-Clause, linked statically. Its source tar is attached too.
  - Windows only: the mingw-w64 runtime and LLVM compiler-rt, linked statically. Their licenses are in the archive.

Each release holds the configure lines and the license texts. See [NOTICE](NOTICE).

# Lumina

**Just another Mac slideshow app.**

Native, for Apple Silicon. SwiftUI, no framework baggage. The only network access is
the update check, and you can switch it off.

Built for photo series and cinemagraphs: pick images or whole folders, set the timing and
transition, hit play. Animated WebP, GIF and APNG actually animate instead of showing their
first frame.

> The user interface is in German. Code, commits and this document are in English.
> [Deutsche Fassung dieser Datei](README.de.md).

## Why it exists

macOS has no decent standalone slideshow app. Preview cannot do transitions, Photos insists on
importing everything into its library first, and screensavers only read from fixed folders.
Lumina reads any folder, plays it fullscreen, and forgets about it afterwards.

## Features

**Sources**

- Pick individual images, whole folders (optionally recursive), or drop files onto the window
- Recently used sources are restored on launch

**Building the set**

Selecting and including are separate, like in Finder. A click selects, Cmd and Shift extend the
selection, arrow keys move it. Delete removes images from the slideshow - they disappear from
the grid, the files on disk are never touched. The status bar offers the way back.
Double click starts the slideshow at that image.

**Transitions**

Cut, crossfade, slide, push, zoom, wipe, 3D flip, or a different one per image. Duration is
adjustable from 0 to 3 seconds.

**Image handling**

Fit, fill (cropped), or fit with a blurred backdrop filling the letterbox. A Ken Burns pan and
zoom in four strengths, reproducible per image. Adjustable background brightness.

**Animated images**

Animated WebP is decoded with libwebp rather than ImageIO. This is not a matter of taste -
measured on a 301 frame cinemagraph:

| Decoder | per frame | achievable rate |
|---|---|---|
| `CGImageSourceCreateThumbnailAtIndex` | 280 ms | 3.6 fps |
| `CGAnimateImageAtURLWithBlock` | 78 ms | 12.8 fps |
| libwebp `WebPAnimDecoder` | 1.5 ms | 652 fps |

ImageIO only offers random access into an animated WebP and recomputes the whole frame history
for every single frame, so decoding cost grows quadratically. That file needs 58.8 fps. GIF and
APNG stay on ImageIO, where the frame counts are small enough for it to keep up.

Frames are streamed through a bounded buffer, so a 400 frame file starts as fast as a JPEG and
memory stays constant regardless of length.

## Install

Download the DMG from [Releases](https://github.com/benjaminmue/lumina/releases), drag Lumina to
Applications.

The app is ad-hoc signed but **not notarized**. On first launch, right click the app and choose
*Open*, then confirm. A plain double click only shows a warning with no way forward. This is a
one-time step.

## Controls

### Library

| Key | Action |
|---|---|
| Arrow keys | Move selection |
| Shift + click | Select range |
| Cmd + click | Add to selection |
| Cmd A | Select all |
| Delete | Remove selected from the slideshow |
| Return, double click | Start slideshow here |
| Cmd O, Shift Cmd O | Add images, add folders |
| Cmd R | Start slideshow |

### Player

| Key | Action |
|---|---|
| Space | Pause and resume |
| Left, Up | Previous image |
| Right, Down, Return | Next image |
| Home, End | First, last image |
| Esc | Leave the slideshow |
| Mouse move | Show the controls |

## Build

Requires Xcode or the Command Line Tools with Swift 6, plus libwebp:

```bash
brew install webp

./scripts/build-app.sh              # builds dist/Lumina.app
./scripts/build-app.sh --install    # also copies it to /Applications
./scripts/make-dmg.sh               # builds dist/Lumina-<version>.dmg
swift test                          # 57 unit tests (XCTest needs Xcode)
swift scripts/make-icon.swift       # regenerates Resources/AppIcon.icns
```

There is no Xcode project. `build-app.sh` compiles with SwiftPM and assembles the bundle itself,
including the libwebp dylibs, so the installed app does not depend on Homebrew.

## Layout

```
Sources/LuminaCore/     Logic without UI dependencies, fully tested
  SlideshowConfig       Settings, including range clamping and tolerant decoding
  MediaItem             File scanning, sorting, supported formats
  SlideshowSequence     Advance, rewind, loop, prefetch
  ImageLoader           Actor with downsampling at decode time
  AnimationDecoder      Facade: libwebp for WebP, ImageIO for the rest
  WebPAnimationDecoder  Sequential frame decoding via libwebp
  FrameTimeline         Which frame is visible at a point in time
  KenBurnsPlan          Reproducible camera move per image
  SeededGenerator       Deterministic PRNG, so animations do not jitter on redraw

Sources/Lumina/         SwiftUI interface
  AppState              Import, selection, persistence
  SlideshowEngine       Timing, pause, image changes
  AnimationPlayback     Streams animation frames through a bounded buffer
  Views/                Library, tile, player, controls, transitions
```

Images are downsampled while decoding (`CGImageSourceCreateThumbnailAtIndex`), otherwise a
60 megapixel RAW would land in memory as a 240 MB bitmap. Thumbnails and fullscreen images use
separate caches so the many small ones cannot evict the large ones.

## Diagnostics

```bash
log stream --predicate 'subsystem == "ch.bebamu.lumina"'
```

Unreadable or undecodable files are logged there by name.

## Known quirks

- The Ken Burns move keeps running to its end point when you pause, then stops. The image change
  itself pauses correctly. Fixing this properly would trade a GPU driven animation for 60 state
  updates per second, which the edge case does not justify.
- Removing images cannot be undone with Cmd Z; the status bar is the way back.
- macOS asks once for permission the first time you read from Desktop, Documents or Downloads.

## Formats

JPEG, PNG, HEIC/HEIF, GIF, TIFF, BMP, WebP, AVIF, JPEG 2000, PSD and the common RAW formats
(DNG, CR2, CR3, NEF, ARW, ORF, RAF, RW2). Animated playback for WebP, GIF, APNG and HEICS.

## License

MIT, see [LICENSE](LICENSE).

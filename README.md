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

**Settings**

A settings window (Cmd comma) holds what you set once and forget: start in full
screen, keep the Mac awake while playing, pointer hide delay, import behaviour.
Everything a preset overwrites stays in the inspector instead, so a preset click
cannot silently change global settings.

**Languages**

English, German, French, Italian, Spanish and Japanese. The app follows your
system language. It only asks once, at first launch, if your system asks for a
language it does not have.

**Updates**

Updates install themselves. The app checks the releases page at launch, at most
once a week, and offers the usual three choices: install now, install when you
quit, or remind me later. Every update is verified against a public key built
into the app, so a tampered download is refused.

Because the app is replaced from the inside rather than downloaded through a
browser, macOS only asks about unverified software on the very first install.
The update check is the only network access and it can be turned off.

## Install

Download the DMG from [Releases](https://github.com/benjaminmue/lumina/releases), open it and
drag Lumina to Applications.

### First launch: macOS will block it

Lumina is ad-hoc signed but **not notarized**, so Gatekeeper stops it with
*"Apple could not verify … is free of malware"*. That is expected, and there is no way
around it short of an Apple Developer account. Allowing it takes about ten seconds:

1. Double-click Lumina. The warning appears. Click **Done** (not "Move to Trash").
2. Open **System Settings → Privacy & Security**.
3. Scroll to the **Security** section. There is now a line about Lumina being blocked.
   Click **Open Anyway** and confirm with your password.
4. Double-click Lumina again and confirm once more. From now on it opens normally.

The Control-click trick that used to work no longer does: Apple removed it in macOS 15.

If you prefer the terminal, this removes the quarantine flag in one step:

```bash
xattr -d com.apple.quarantine /Applications/Lumina.app
```

Both routes do the same thing: you vouch for the app instead of Apple. If that is not
acceptable to you, build it yourself from source, that takes one command.

## Controls

Marking and removing are separate, as in the Finder. You mark images to act on
them; only Delete takes them out of the slideshow, and the status bar offers the
way back.

### Library

| Key | Action |
|---|---|
| Arrow keys | Move selection |
| Shift + click | Select range |
| Cmd + click | Add to selection |
| Cmd A | Mark all |
| Shift Cmd A | Clear marks |
| Delete | Remove marked images from the slideshow |
| Return, double click | Start slideshow here |
| Cmd O, Shift Cmd O | Add images, add folders |
| Cmd R | Start slideshow |
| Cmd comma | Settings |

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
swift test                          # 85 unit tests (XCTest needs Xcode)
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

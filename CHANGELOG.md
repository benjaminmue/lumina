# Changelog

## Unreleased

- The author name is spelled with its umlaut: Benjamin Müller. This corrects the
  licence, the bundle copyright shown in Finder, and the link in the About pane
- The Help menu opens the readme at the controls section rather than the top of
  the page, and that section now lists every shortcut

## 1.5.0 - 2026-08-24

- The Help menu now opens the documentation, the two issue forms and the release
  notes. Before, macOS answered "Help isn't available for Lumina", because the app
  ships no help book

## 1.4.0 - 2026-08-23

### Updates install themselves

The update pane got a check button, and found updates install themselves. The
usual three choices are offered: install now, install when you quit, or remind
me later. Before this the app only opened the download page and left the
downloading, mounting, dragging and Gatekeeper dance to you.

Every update is verified against a public key built into the app, so a tampered
download is refused. Because the app is replaced from the inside rather than
downloaded through a browser, macOS does not ask about unverified software again
after the first install.

### Also

- The disk image now has a background with an arrow, so the window explains
  itself instead of relying on a text file
- Installation instructions corrected: Apple removed the right-click route in
  macOS 15, allowing the app now goes through System Settings

## 1.3.0 - 2026-08-23

### Settings window

A window of its own under Cmd-comma, with four panes: General, Playback, Updates,
About. The dividing line to the inspector in the main window: anything a preset
overwrites stays there. Otherwise clicking "Screen saver" would silently change
global settings too.

- New: keep the Mac awake while playing. A slideshow replaced by the screen saver
  after ten minutes misses its point
- New: how long until the pointer disappears
- New: ask before clearing the list
- New: reload the last sources at launch, can be turned off

### Updates

Optionally looks for a newer version at launch, at most once a week, and reports it
as a hint in the status bar rather than a dialog. Individual versions can be
skipped. This is the only network access the app makes and it can be switched off.

### Languages

English, German, French, Italian, Spanish and Japanese. The app follows the system
language; it only asks, once, if the system wants a language it does not have. The
menu bar switches after the next restart.

### Also

- New app icon
- Issue forms for bugs and feature requests. Version and macOS version are filled
  in by the app itself when you open them from inside it

## 1.2.0 - 2026-08-16

Reworked interface, out of two reviews: one on visual design (the idea being a
lightbox, where the interface recedes and the images carry the screen) and one on
macOS conventions.

### Library

- Selecting and including are now separate: a click selects, Cmd and Shift extend,
  arrow keys move the selection, Cmd-A selects all
- Removed images disappear from the grid instead of sitting there greyed out. The
  delete key removes the selection, the status bar leads back
- File names left the grid and appear on hover together with a play button
- One import menu instead of two near-identical buttons, one prominent play
  button, "include subfolders" moved to the import menu where it belongs

### Settings

- Presets as cards with an active state, the four settings people actually touch
  below, everything else folded away: nine visible controls instead of seventeen
- Transition duration hides rather than greying out when there is no transition

### Player

- Loading shows a blurred preview instead of a spinner on black
- Controls slimmed down, with a gradient behind them across the full width; the
  end of the show is a state of that bar, not a dialog in the middle of the image
- The progress bar is a hairline at rest

### Fixed

- Clicks on the tile buttons were swallowed by the selection gesture
- Gradient and shadow of the control bar were clipped to the width of the capsule

### From the code review

- Animated WebP was always decoded at full resolution and the buffer was capped by
  frame count: a 4000x4000 animation would have used 1.5 GB. Frames are now scaled
  to display size and the buffer is bounded to 64 MB
- The WebP decoder passed a pointer from `Data.withUnsafeBytes` to libwebp, which
  keeps it and reads from it later. It now owns its buffer; verified with 3000
  decoded frames under the address sanitizer
- When no file could be read, the image change called itself without bound. It is
  a loop with a one-round cap now, and it surfaces an error
- Ken Burns could expose an empty edge at scale 1.0 and stopped early when
  animations play in full
- Prefetch tasks were never cancelled and refilled a just-cleared cache
- The frame producer could spin at 100 Hz on unreadable files
- Two incorrect `@unchecked Sendable` claims removed
- Messages go to `os.Logger` instead of being lost silently

### From the second review pass

- An in-flight decode was shared regardless of the size it was started for, and
  its result cached under the larger request. A too-small image then counted as
  large enough for everyone after it
- Skipping unreadable files always wrapped to the start, even with repeat off: a
  show with one broken file at the end never finished
- Several fast key presses within one tick overwrote each other

## 1.1.0 - 2026-08-16

- Animated WebP, GIF and APNG are played instead of shown as a still frame
- New setting "play animations in full": a cinemagraph is not cut off mid-motion
- Badge with the frame count on animated tiles
- Memory budget for animations with adaptive downsampling
- Stored settings survive new fields instead of falling back to defaults

### Fixed

- Portrait images blew up their grid cell and overlapped their neighbours
- The fullscreen slideshow ran at the decode resolution of the small window, so
  images were blurry
- The keyboard monitor swallowed keys in other windows of the app
- Starting fullscreen failed when started right after launch
- The status bar covered the bottom row of tiles
- Tiles could only be operated with the mouse

## 1.0.0 - 2026-08-16

First version.

- Import of individual images, whole folders (optionally recursive) and by drag and drop
- Removing individual images from the imported list
- Seven transitions plus a random mode, duration adjustable
- Scaling: fit, fill, fit with blurred edges
- Ken Burns move in four strengths, reproducible per image
- Time per image 1 to 60 s, sorting by name, date, size or shuffled
- Fullscreen player with keyboard control and controls that fade in
- Three presets: screen saver, slide show, presentation
- 27 unit tests for the core logic

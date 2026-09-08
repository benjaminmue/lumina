# Lumina

A native macOS slideshow app. Distributed outside the App Store, updating itself through
Sparkle, localised into six languages.

## Stack
Swift and SwiftUI, built with Swift Package Manager. Shipped as a signed and notarised
DMG built with `dmgbuild`.

## What a review needs to know
- Sparkle's appcast and the signing chain are the update path's trust anchor. A mistake
  there ships unverified code to every installed copy.
- Screenshots and offscreen rendering need the real screen-capture entitlement.
  `ImageRenderer`, `cacheDisplay` and layer rendering all fail for this, so a change that
  claims to render offscreen deserves scepticism.
- Every user-visible string belongs in all six localisations. A hardcoded English string
  is a finding.
- The app reads the user's own photo directories. Anything widening that access, or
  sending file data anywhere, needs an explicit reason.

## Conventions
Code, comments and commit messages in English. Public repository.

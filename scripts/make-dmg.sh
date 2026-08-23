#!/bin/bash
#
# Packt Lumina.app in ein Disk-Image mit Hintergrundbild, Pfeil und Symlink
# auf den Programme-Ordner.
#
#   ./scripts/make-dmg.sh          nutzt die Version aus Info.plist
#   ./scripts/make-dmg.sh 1.3.0    erzwingt eine Version
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/Lumina.app"

if [[ ! -d "$APP" ]]; then
    echo "==> Lumina.app fehlt, baue zuerst"
    ./scripts/build-app.sh
fi

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
VOLUME="Lumina $VERSION"
DMG="$ROOT/dist/Lumina-$VERSION.dmg"
TEMP="$ROOT/build/lumina-temp.dmg"
STAGE="$ROOT/build/dmg"

echo "==> Bereite Inhalt vor (Version $VERSION)"
rm -rf "$STAGE" "$TEMP" "$DMG"
mkdir -p "$STAGE/.background"

cp -R "$APP" "$STAGE/Lumina.app"
ln -s /Applications "$STAGE/Applications"

if [[ -f "$ROOT/Resources/dmg-background.png" ]]; then
    cp "$ROOT/Resources/dmg-background.png" "$STAGE/.background/background.png"
else
    echo "Hinweis: kein Hintergrundbild, 'swift scripts/make-dmg-background.swift' erzeugt es"
fi

# Die Kurzanleitung bleibt als Datei im Image: der Terminal-Befehl und die
# einzelnen Schritte sind auf dem Hintergrundbild nicht lesbar unterzubringen.
cat > "$STAGE/Read me first.txt" <<'EOF'
Installing Lumina

1. Drag Lumina.app onto the Applications folder.

2. On first launch macOS blocks the app: "Apple could not verify that Lumina is
   free of malware". This is expected. The app is signed, but not notarized by
   Apple, which would require a paid developer account.

   To allow it:
   - Double-click Lumina, then click "Done" in the warning (not "Move to Trash")
   - Open System Settings, go to Privacy & Security
   - Scroll down to the Security section. It now mentions that Lumina was blocked.
     Click "Open Anyway" and confirm with your password.
   - Double-click Lumina again and confirm once more.

   After that it opens like any other app.

   The old trick of right-clicking and choosing "Open" no longer works; Apple
   removed it in macOS 15.

   In the terminal it is one step:
   xattr -d com.apple.quarantine /Applications/Lumina.app

Source code and documentation: https://github.com/benjaminmue/lumina
EOF

echo "==> Erzeuge beschreibbares Image"
# Beschreibbar, weil das Fenster-Layout erst im gemounteten Zustand gesetzt
# werden kann. Am Ende wird komprimiert und schreibgeschützt konvertiert.
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -ov -quiet "$TEMP"

MOUNT="/Volumes/$VOLUME"
hdiutil attach "$TEMP" -nobrowse -quiet
sleep 1

echo "==> Setze Fensterlayout"
# Die Positionen entsprechen dem Pfeil im Hintergrundbild.
if ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 860, 560}
        set theOptions to the icon view options of container window
        set arrangement of theOptions to not arranged
        set icon size of theOptions to 128
        set text size of theOptions to 13
        try
            set background picture of theOptions to file ".background:background.png"
        end try
        set position of item "Lumina.app" of container window to {180, 232}
        -- Der Symlink wird vom Finder als Alias geführt und lässt sich nur so ansprechen.
        set position of alias file "Applications" of container window to {480, 232}
        set position of item "Read me first.txt" of container window to {575, 372}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
then
    echo "Hinweis: Finder-Layout nicht gesetzt (Automation-Berechtigung fehlt?)."
    echo "         Das Image funktioniert trotzdem, nur ohne Hintergrundbild."
fi

sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet

echo "==> Komprimiere"
hdiutil convert "$TEMP" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG"
rm -f "$TEMP"
rm -rf "$STAGE"

echo "==> Signiere"
codesign --force --sign - "$DMG"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "Fertig: $DMG ($SIZE)"

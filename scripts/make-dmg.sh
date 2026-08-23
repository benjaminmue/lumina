#!/bin/bash
#
# Packt Lumina.app in ein Disk-Image mit Hintergrundbild, Pfeil und Symlink
# auf den Programme-Ordner.
#
#   ./scripts/make-dmg.sh          nutzt die Version aus Info.plist
#   ./scripts/make-dmg.sh 1.3.0    erzwingt eine Version
#
# Das Layout schreibt dmgbuild (pipx install dmgbuild) direkt ins .DS_Store.
# Der übliche Weg über AppleScript funktioniert hier nicht: der Finder führt die
# Befehle aus, legt die Einstellungen aber nie im Image ab - nachgeprüft, das
# .DS_Store blieb ohne icvp- und Iloc-Einträge. dmgbuild braucht ausserdem keinen
# laufenden Finder und funktioniert damit auch auf einem CI-Runner.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/Lumina.app"

if [[ ! -d "$APP" ]]; then
    echo "==> Lumina.app fehlt, baue zuerst"
    ./scripts/build-app.sh
fi

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="$ROOT/dist/Lumina-$VERSION.dmg"
README="$ROOT/build/Read me first.txt"

mkdir -p "$ROOT/build"
rm -f "$DMG"

# Die Kurzanleitung liegt als Datei im Image: der Terminal-Befehl und die einzelnen
# Schritte sind auf dem Hintergrundbild nicht lesbar unterzubringen.
cat > "$README" <<'EOF'
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

   You only need this once. Later updates install themselves from inside the app
   and skip this step entirely.

   The old trick of right-clicking and choosing "Open" no longer works; Apple
   removed it in macOS 15.

   In the terminal it is one step:
   xattr -d com.apple.quarantine /Applications/Lumina.app

Source code and documentation: https://github.com/benjaminmue/lumina
EOF

DMGBUILD="$(command -v dmgbuild || true)"
[[ -z "$DMGBUILD" && -x "$HOME/.local/bin/dmgbuild" ]] && DMGBUILD="$HOME/.local/bin/dmgbuild"

if [[ -n "$DMGBUILD" ]]; then
    echo "==> Baue Image mit Layout (Version $VERSION)"
    LUMINA_APP="$APP" LUMINA_README="$README" LUMINA_BACKGROUND="$ROOT/Resources/dmg-background.png" \
        "$DMGBUILD" -s "$ROOT/scripts/dmg-settings.py" "Lumina $VERSION" "$DMG"
else
    echo "==> dmgbuild fehlt, baue schlichtes Image (pipx install dmgbuild)"
    STAGE="$ROOT/build/dmg"
    rm -rf "$STAGE"; mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/Lumina.app"
    cp "$README" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Lumina $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
    rm -rf "$STAGE"
fi

[[ -f "$DMG" ]] || { echo "Image wurde nicht erzeugt" >&2; exit 1; }

echo "==> Signiere"
codesign --force --sign - "$DMG"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "Fertig: $DMG ($SIZE)"

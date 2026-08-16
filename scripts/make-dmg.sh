#!/bin/bash
#
# Packt Lumina.app in ein Disk-Image mit Symlink auf den Programme-Ordner.
#
#   ./scripts/make-dmg.sh          nutzt die Version aus Info.plist
#   ./scripts/make-dmg.sh 1.2.0    erzwingt eine Version
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
DMG="$ROOT/dist/Lumina-$VERSION.dmg"
STAGE="$ROOT/build/dmg"

echo "==> Bereite Inhalt vor (Version $VERSION)"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Lumina.app"
ln -s /Applications "$STAGE/Programme"

# Kurzanleitung ins Image, weil die App nicht notarisiert ist und macOS beim
# ersten Start sonst nur eine Fehlermeldung ohne Ausweg zeigt.
cat > "$STAGE/Bitte lesen.txt" <<'EOF'
Lumina installieren

1. Lumina.app auf den Ordner "Programme" ziehen.
2. Beim ersten Start: Rechtsklick auf Lumina.app, dann "Öffnen" wählen
   und im Dialog nochmals "Öffnen" bestätigen.

Schritt 2 ist nötig, weil die App nicht von Apple notarisiert ist. Ein
Doppelklick zeigt stattdessen nur eine Warnung ohne Möglichkeit zum Öffnen.
Nach dem ersten Mal startet Lumina wie jede andere App.

Quellcode: https://github.com/benjaminmue/lumina
EOF

echo "==> Erzeuge Disk-Image"
hdiutil create \
    -volname "Lumina $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO -quiet \
    "$DMG"

rm -rf "$STAGE"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "==> Signiere"
codesign --force --sign - "$DMG"

echo "Fertig: $DMG ($SIZE)"

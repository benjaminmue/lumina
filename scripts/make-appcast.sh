#!/bin/bash
#
# Schreibt den Sparkle-Feed für ein Release.
#
#   ./scripts/make-appcast.sh dist/Lumina-1.3.0.dmg [schluesseldatei]
#
# Ohne Schlüsseldatei nimmt sign_update den Schlüssel aus der Keychain; im CI wird
# er als Datei übergeben. Der Feed wird bewusst selbst geschrieben statt mit
# generate_appcast: das liefert für einzelne Disk-Images keine Signatur ins XML,
# und ohne Signatur weist Sparkle das Update zu Recht ab.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DMG="${1:-}"
KEYFILE="${2:-}"
[[ -f "$DMG" ]] || { echo "Disk-Image fehlt: $DMG" >&2; exit 1; }

APP="$ROOT/dist/Lumina.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"

SIGN="$(find "$ROOT/.build/artifacts" -maxdepth 6 -type f -name sign_update 2>/dev/null | head -1)"
[[ -n "$SIGN" ]] || { echo "sign_update nicht gefunden, erst 'swift build' laufen lassen" >&2; exit 1; }

echo "==> Signiere $DMG"
if [[ -n "$KEYFILE" ]]; then
    SIGNATURE_LINE="$("$SIGN" "$DMG" --ed-key-file "$KEYFILE")"
else
    SIGNATURE_LINE="$("$SIGN" "$DMG")"
fi

# sign_update gibt die fertigen Attribute aus: sparkle:edSignature="..." length="..."
[[ "$SIGNATURE_LINE" == *edSignature* ]] || { echo "Signatur fehlgeschlagen: $SIGNATURE_LINE" >&2; exit 1; }

# Die Änderungen aus dem Changelog als HTML einbetten. Ein Verweis auf die
# Release-Seite lädt sonst die ganze GitHub-Oberfläche samt Navigation in das
# kleine Fenster des Update-Dialogs.
NOTES_HTML="$(
    awk -v version="## $VERSION" '
        $0 ~ "^" version { found = 1; next }
        found && /^## / { exit }
        found { print }
    ' "$ROOT/CHANGELOG.md" |
    sed -E \
        -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
        -e 's/^### (.*)$/<h3>\1<\/h3>/' \
        -e 's/^- (.*)$/<li>\1<\/li>/' \
        -e 's/`([^`]*)`/<code>\1<\/code>/g' \
        -e 's/\*\*([^*]*)\*\*/<strong>\1<\/strong>/g'
)"

FILENAME="$(basename "$DMG")"
URL="https://github.com/benjaminmue/lumina/releases/download/v$VERSION/$FILENAME"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
OUT="$ROOT/dist/appcast.xml"

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Lumina</title>
        <link>https://github.com/benjaminmue/lumina</link>
        <description>Just another Mac slideshow app</description>
        <language>en</language>
        <item>
            <title>$VERSION</title>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <style>body{font:13px -apple-system,sans-serif;margin:0;padding:4px 2px;} h3{font-size:13px;margin:14px 0 4px;} li{margin:3px 0;} p{margin:6px 0;}</style>
                <h2 style="font-size:15px;margin:0 0 8px">Lumina $VERSION</h2>
$NOTES_HTML
                <p style="color:#888;margin-top:14px">Full notes: https://github.com/benjaminmue/lumina/releases/tag/v$VERSION</p>
            ]]></description>
            <enclosure url="$URL" $SIGNATURE_LINE type="application/octet-stream"/>
        </item>
    </channel>
</rss>
XML

echo "Fertig: $OUT"
grep -o 'sparkle:edSignature="[^"]\{0,14\}' "$OUT"

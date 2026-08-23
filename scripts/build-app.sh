#!/bin/bash
#
# Baut Lumina.app als natives Apple-Silicon-Bundle.
#
#   ./scripts/build-app.sh            Release-Build nach dist/Lumina.app
#   ./scripts/build-app.sh --install  zusätzlich nach /Applications kopieren
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/Lumina.app"
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

# Ohne Xcode-Lizenz laufen die Command Line Tools als Fallback.
if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    echo "Hinweis: Xcode nicht nutzbar, baue mit Command Line Tools"
fi

echo "==> Kompiliere (release, arm64)"
swift build -c release --arch arm64

BIN="$(swift build -c release --arch arm64 --show-bin-path)/Lumina"
[[ -f "$BIN" ]] || { echo "Binary nicht gefunden: $BIN" >&2; exit 1; }

echo "==> Baue Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Lumina"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "Hinweis: kein AppIcon.icns - 'swift scripts/make-icon.swift' erzeugt es"
fi

# Sprachdateien ins Bundle. Sie liegen unter Contents/Resources und damit im
# Suchpfad von Bundle.main - nur dort findet SwiftUI sie ohne Zutun.
echo "==> Kopiere Sprachdateien"
LANG_COUNT=0
for lproj in "$ROOT"/Resources/*.lproj; do
    [[ -d "$lproj" ]] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
    LANG_COUNT=$((LANG_COUNT + 1))
done
echo "    $LANG_COUNT Sprachen"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# libwebp mitliefern, damit die App unabhängig von Homebrew startet.
echo "==> Bette libwebp ein"
FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

WEBP_LIB="$(brew --prefix webp 2>/dev/null)/lib"
if [[ -d "$WEBP_LIB" ]]; then
    # libwebpdemux referenziert libwebp und libsharpyuv bereits über @rpath,
    # es genügt also, alle drei neben das Programm zu legen.
    for name in libwebpdemux.2.dylib libwebp.7.dylib libsharpyuv.0.dylib; do
        if [[ -f "$WEBP_LIB/$name" ]]; then
            cp "$WEBP_LIB/$name" "$FRAMEWORKS/$name"
            chmod u+w "$FRAMEWORKS/$name"
            install_name_tool -id "@rpath/$name" "$FRAMEWORKS/$name"
            codesign --force --sign - "$FRAMEWORKS/$name"
        fi
    done

    # Absolute Homebrew-Pfade im Programm auf das Bundle umbiegen.
    otool -L "$APP/Contents/MacOS/Lumina" | awk 'NR>1 {print $1}' | { grep "^/opt/homebrew" || true; } | while read -r dep; do
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$APP/Contents/MacOS/Lumina"
    done
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Lumina" 2>/dev/null || true
else
    echo "Warnung: libwebp nicht gefunden - animierte WebP laufen dann über den langsamen Systemdecoder"
fi

echo "==> Signiere ad-hoc"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "==> Prüfe Architektur"
lipo -archs "$APP/Contents/MacOS/Lumina"

if $INSTALL; then
    echo "==> Installiere nach /Applications"
    rm -rf "/Applications/Lumina.app"
    cp -R "$APP" "/Applications/Lumina.app"
    echo "Fertig: /Applications/Lumina.app"
else
    echo "Fertig: $APP"
fi

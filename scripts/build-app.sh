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

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signiere ad-hoc"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

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

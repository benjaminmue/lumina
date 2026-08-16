# Lumina

Native macOS-Slideshow-App für Apple Silicon. SwiftUI, kein Framework-Ballast, kein Netzwerkzugriff.

Kurzfassung auf Deutsch. Die ausführliche Beschreibung samt Messwerten steht im
[englischen README](README.md), damit nicht zwei Fassungen auseinanderlaufen.

## Wozu

macOS hat keine brauchbare eigenständige Slideshow-App. Vorschau kann keine Übergänge,
Fotos will alles erst in seine Mediathek importieren, und Bildschirmschoner lesen nur aus
festen Ordnern. Lumina liest jeden Ordner, spielt ihn im Vollbild ab und vergisst ihn wieder.

## Was sie kann

- Einzelne Bilder, ganze Ordner (wahlweise mit Unterordnern) oder Dateien per Drag and Drop
- Acht Übergänge, Anzeige- und Übergangsdauer einstellbar
- Einpassen, Ausfüllen oder Einpassen mit unscharfem Rand
- Ken-Burns-Fahrt in vier Stufen, pro Bild reproduzierbar
- Animierte WebP, GIF und APNG werden abgespielt statt als Standbild gezeigt
- Drei Vorlagen: Bildschirmschoner, Diaschau, Präsentation

## Zusammenstellen

Markieren und Zusammenstellen sind getrennt, wie im Finder: ein Klick markiert, Cmd und
Umschalt erweitern die Markierung, die Pfeiltasten bewegen sie. Entfernt wird mit der
Löschtaste oder dem Kreuz auf der Kachel; entfernte Bilder verschwinden aus dem Raster,
die Dateien bleiben unangetastet. Der Rückweg steht in der Statuszeile. Ein Doppelklick
startet die Slideshow ab diesem Bild.

## Steuerung im Player

| Taste | Funktion |
|---|---|
| Leertaste | Pause und weiter |
| Links, oben | Vorheriges Bild |
| Rechts, unten, Return | Nächstes Bild |
| Pos1, Ende | Erstes, letztes Bild |
| Esc | Slideshow beenden |
| Mausbewegung | Steuerung einblenden |

## Installieren

DMG aus den [Releases](https://github.com/benjaminmue/lumina/releases) laden, Lumina in den
Programme-Ordner ziehen.

Die App ist ad-hoc signiert, aber **nicht notarisiert**. Beim ersten Start darum Rechtsklick
auf die App, dann *Öffnen* wählen und bestätigen. Ein Doppelklick zeigt nur eine Warnung ohne
Ausweg. Das ist einmalig nötig.

## Bauen

Voraussetzung: Xcode oder Command Line Tools mit Swift 6, dazu libwebp.

```bash
brew install webp

./scripts/build-app.sh              # baut dist/Lumina.app
./scripts/make-dmg.sh               # baut dist/Lumina-<version>.dmg
swift test                          # 57 Unit-Tests (XCTest braucht Xcode)
```

Ohne libwebp scheitert der Build. Die Bibliothek wird ins Bundle kopiert, die fertige App
braucht Homebrew also nicht.

## Bekannte Eigenheiten

- Die Ken-Burns-Fahrt läuft bei Pause bis zu ihrem Endpunkt weiter und bleibt dann stehen.
  Der Bildwechsel selbst pausiert korrekt.
- Entfernen lässt sich nicht mit ⌘Z rückgängig machen; der Rückweg führt über die Statuszeile.
- Beim ersten Zugriff auf Schreibtisch, Dokumente oder Downloads fragt macOS einmal nach Erlaubnis.

Protokoll mitlesen: `log stream --predicate 'subsystem == "ch.bebamu.lumina"'`

## Lizenz

MIT, siehe [LICENSE](LICENSE).

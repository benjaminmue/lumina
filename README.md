# Lumina

Native macOS-Slideshow-App für Apple Silicon. SwiftUI, kein Framework-Ballast, kein Netzwerkzugriff.

## Funktionen

**Quellen**

- Einzelne Bilder auswählen (Mehrfachauswahl im Dateidialog)
- Ganze Ordner auswählen, wahlweise mit Unterordnern
- Dateien und Ordner per Drag and Drop ins Fenster ziehen
- Aus einem importierten Ordner einzelne Bilder abwählen (Klick auf die Kachel)
- Zuletzt genutzte Quellen werden beim Start automatisch neu eingelesen

**Übergänge**

| Effekt | Verhalten |
|---|---|
| Harter Schnitt | Kein Übergang |
| Überblenden | Klassisches Crossfade |
| Schieben | Neues Bild schiebt sich über das alte |
| Verdrängen | Beide Bilder bewegen sich wie ein Filmstreifen |
| Zoom | Neues Bild kommt vergrössert herein, altes verkleinert sich |
| Wischen | Maske läuft über die Fläche |
| Umschlagen | 3D-Flip um die vertikale Achse |
| Zufällig | Pro Bild ein anderer Effekt |

**Bildbehandlung**

- Einpassen (ganzes Bild sichtbar), Ausfüllen (Crop) oder Einpassen mit unscharfem Rand
- Ken-Burns-Fahrt in vier Stufen (aus, dezent, mittel, stark): langsamer Zoom plus Schwenk
- Hintergrundhelligkeit stufenlos von Schwarz bis Weiss

**Ablauf**

- Anzeigedauer 1 bis 60 s, Übergangsdauer 0 bis 3 s
- Sortierung nach Name (natürliche Zahlenreihenfolge), Erstell- oder Änderungsdatum, Dateigrösse oder Zufall
- Endlosschleife, Vollbildstart, Dateiname-Einblendung, Fortschrittsbalken
- Drei Vorlagen: Bildschirmschoner, Diaschau, Präsentation

## Steuerung im Player

| Taste | Funktion |
|---|---|
| Leertaste | Pause / Weiter |
| Pfeil rechts, Pfeil runter, Return | Nächstes Bild |
| Pfeil links, Pfeil hoch | Vorheriges Bild |
| Pos1 / Ende | Erstes / letztes Bild |
| Esc | Slideshow beenden |
| Mausbewegung | Steuerleiste einblenden |
| Klick | Pause / Weiter |

Menü: `⌘O` Bilder wählen, `⇧⌘O` Ordner wählen, `⌘R` Slideshow starten.

## Bauen

Voraussetzung: Xcode oder Command Line Tools mit Swift 6.

```bash
./scripts/build-app.sh              # baut dist/Lumina.app
./scripts/build-app.sh --install    # baut und kopiert nach /Applications
swift test                          # 27 Unit-Tests (braucht XCTest aus Xcode)
swift scripts/make-icon.swift       # erzeugt Resources/AppIcon.icns neu
```

Das Bundle wird ad-hoc signiert. Es ist nicht notarisiert - lokal gebaut startet es ohne Gatekeeper-Warnung, per AirDrop oder Download weitergegeben nicht.

## Aufbau

```
Sources/LuminaCore/     Logik ohne UI-Abhängigkeit, vollständig testbar
  SlideshowConfig       Einstellungen inklusive Wertebereichs-Prüfung
  MediaItem             Datei-Scan, Sortierung, unterstützte Formate
  SlideshowSequence     Ablaufsteuerung: weiter, zurück, Loop, Vorausladen
  ImageLoader           Actor mit Downsampling beim Dekodieren und zwei Caches
  KenBurnsPlan          Reproduzierbare Kamerafahrt pro Bild
  SeededGenerator       Deterministischer PRNG für stabile Animationen

Sources/Lumina/         SwiftUI-Oberfläche
  AppState              Import, Auswahl, Persistenz der Einstellungen
  SlideshowEngine       Timing, Pause, Bildwechsel, Nachladen
  Views/                Bibliothek, Player, Übergänge, Einstellungen
```

Bilder werden beim Dekodieren direkt auf Bildschirmgrösse heruntergerechnet
(`CGImageSourceCreateThumbnailAtIndex`), sonst würde ein 60-Megapixel-RAW als
240-MB-Bitmap im Speicher landen. Vorschaukacheln und Vollbilder haben getrennte
Caches, damit viele kleine Thumbnails die grossen Bilder nicht verdrängen.

## Bekannte Eigenheiten

- Die Ken-Burns-Fahrt läuft bei Pause noch bis zu ihrem Endpunkt weiter und bleibt dann stehen. Der Bildwechsel selbst pausiert korrekt.
- Beim ersten Zugriff auf Schreibtisch, Dokumente oder Downloads fragt macOS einmal nach Erlaubnis.
- Defekte oder gelöschte Dateien werden im Player übersprungen.

## Formate

JPEG, PNG, HEIC/HEIF, GIF, TIFF, BMP, WebP, AVIF, JPEG 2000, PSD sowie die
gängigen RAW-Formate (DNG, CR2, CR3, NEF, ARW, ORF, RAF, RW2).

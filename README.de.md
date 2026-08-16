# Lumina

Native macOS-Slideshow-App für Apple Silicon. SwiftUI, kein Framework-Ballast, kein Netzwerkzugriff.

## Funktionen

**Quellen**

- Einzelne Bilder auswählen (Mehrfachauswahl im Dateidialog)
- Ganze Ordner auswählen, wahlweise mit Unterordnern
- Dateien und Ordner per Drag and Drop ins Fenster ziehen
- Zuletzt genutzte Quellen werden beim Start automatisch neu eingelesen

**Zusammenstellen**

Markieren und Zusammenstellen sind getrennt, wie im Finder: ein Klick markiert,
Cmd und Umschalt erweitern die Markierung, die Pfeiltasten bewegen sie. Entfernt
wird mit der Löschtaste oder dem Kreuz auf der Kachel - entfernte Bilder
verschwinden aus dem Raster, die Dateien bleiben unangetastet. Der Rückweg steht
in der Statuszeile ("Anzeigen" und "Zurückholen"). Ein Doppelklick startet die
Slideshow ab diesem Bild.

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

**Animierte Bilder**

Animierte WebP werden über libwebp dekodiert (ImageIO ist dort um Grössenordnungen zu langsam), GIF und APNG über ImageIO. Sie werden abgespielt, nicht als Standbild gezeigt - Cinemagraphs
laufen also so, wie sie gedacht sind. Auf Wunsch bleibt ein animiertes Bild so lange stehen,
bis die Animation mindestens einmal komplett durchgelaufen ist ("Animationen ganz abspielen").
Kacheln in der Bibliothek zeigen die Zahl der Einzelbilder als Badge.

Die Frames werden vollständig in den Speicher dekodiert. Ein Speicherbudget von 384 MB
begrenzt das: passt ein langer Clip in Vollauflösung nicht hinein, wird die Auflösung
halbiert; reicht auch das nicht, läuft die Datei als Standbild. Über die native Auflösung
hinaus wird nie dekodiert.

**Ablauf**

- Anzeigedauer 1 bis 60 s, Übergangsdauer 0 bis 3 s
- Sortierung nach Name (natürliche Zahlenreihenfolge), Erstell- oder Änderungsdatum, Dateigrösse oder Zufall
- Endlosschleife, Vollbildstart, Dateiname-Einblendung, Fortschrittsbalken
- Drei Vorlagen: Bildschirmschoner, Diaschau, Präsentation

## Steuerung

### Bibliothek

| Taste | Funktion |
|---|---|
| Pfeiltasten | Markierung bewegen |
| Umschalt + Klick | Bereich markieren |
| Cmd + Klick | einzeln zur Markierung |
| ⌘A | alles markieren |
| Löschtaste | Markierte aus der Slideshow entfernen |
| Return, Doppelklick | Slideshow ab hier starten |

### Player

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
swift test                          # 41 Unit-Tests (braucht XCTest aus Xcode)
swift scripts/make-icon.swift       # erzeugt Resources/AppIcon.icns neu
```

Das Bundle wird ad-hoc signiert. Es ist nicht notarisiert - lokal gebaut startet es ohne Gatekeeper-Warnung, per AirDrop oder Download weitergegeben nicht.

## Aufbau

```
Sources/LuminaCore/     Logik ohne UI-Abhängigkeit, vollständig testbar
  SlideshowConfig       Einstellungen inklusive Wertebereichs-Prüfung
  MediaItem             Datei-Scan, Sortierung, unterstützte Formate
  SlideshowSequence     Ablaufsteuerung: weiter, zurück, Loop, Vorausladen
  ImageLoader           Actor mit Downsampling beim Dekodieren und drei Caches
  AnimatedImage         Frames und Zeitachse animierter Bilder
  KenBurnsPlan          Reproduzierbare Kamerafahrt pro Bild
  SeededGenerator       Deterministischer PRNG für stabile Animationen

Sources/Lumina/         SwiftUI-Oberfläche
  AppState              Import, Auswahl, Persistenz der Einstellungen
  SlideshowEngine       Timing, Pause, Bildwechsel, Nachladen
  AnimationPlayback     Streamt Animations-Frames mit begrenztem Puffer
  Views/                Bibliothek, Kachel, Player, Steuerleiste, Übergänge
```

Bilder werden beim Dekodieren direkt auf Bildschirmgrösse heruntergerechnet
(`CGImageSourceCreateThumbnailAtIndex`), sonst würde ein 60-Megapixel-RAW als
240-MB-Bitmap im Speicher landen. Vorschaukacheln und Vollbilder haben getrennte
Caches, damit viele kleine Thumbnails die grossen Bilder nicht verdrängen.

## Bekannte Eigenheiten

- Die Ken-Burns-Fahrt läuft bei Pause noch bis zu ihrem Endpunkt weiter und bleibt dann stehen. Der Bildwechsel selbst pausiert korrekt. Die saubere Lösung würde eine GPU-getriebene Animation gegen 60 Zustandsänderungen pro Sekunde tauschen - das ist der Randfall nicht wert.
- Entfernen lässt sich nicht mit ⌘Z rückgängig machen; der Rückweg führt über die Statuszeile.
- Beim ersten Zugriff auf Schreibtisch, Dokumente oder Downloads fragt macOS einmal nach Erlaubnis.
- Defekte oder gelöschte Dateien werden im Player übersprungen.

## Formate

JPEG, PNG, HEIC/HEIF, GIF, TIFF, BMP, WebP, AVIF, JPEG 2000, PSD sowie die
gängigen RAW-Formate (DNG, CR2, CR3, NEF, ARW, ORF, RAF, RW2).

Animiert abgespielt werden WebP, GIF, APNG und HEICS.

# Changelog

## 1.2.0 - 2026-08-16

Überarbeitete Oberfläche, aus zwei Reviews entstanden: einem gestalterischen
(Leitidee Leuchtkasten - die Oberfläche tritt zurück, die Bilder tragen) und
einem zur macOS-Idiomatik.

### Bibliothek

- Markieren und Zusammenstellen sind getrennt: Klick markiert, Cmd und Umschalt
  erweitern, Pfeiltasten bewegen die Markierung, ⌘A markiert alles
- Entfernte Bilder verschwinden aus dem Raster, statt grau liegen zu bleiben.
  Löschtaste entfernt die Markierung, die Statuszeile führt zurück
- Dateinamen sind aus dem Raster verschwunden und erscheinen beim Überfahren
  zusammen mit einem Play-Knopf
- Ein Import-Menü statt zweier fast gleicher Knöpfe, ein prominenter
  Abspielen-Knopf, "Unterordner einbeziehen" beim Import statt in den
  Wiedergabe-Einstellungen

### Einstellungen

- Vorlagen als Karten mit aktivem Zustand, darunter die vier häufig genutzten
  Regler, alles Übrige eingeklappt: sichtbar 9 statt 17 Bedienelemente
- Die Übergangsdauer wird ausgeblendet statt ausgegraut, wenn es keinen Übergang gibt

### Player

- Ladezustand zeigt das Bild unscharf vorab statt eines Spinners auf Schwarz
- Steuerleiste entschlackt, mit Verlauf über die volle Breite; das Ende der Show
  ist ein Zustand dieser Leiste statt eines Dialogs mitten im Bild
- Fortschrittsbalken ist im Ruhezustand ein Haarstrich

### Behoben

- Klicks auf die Kachel-Knöpfe wurden von der Auswahl-Geste geschluckt
- Verlauf und Schatten der Steuerleiste waren auf Kapselbreite abgeschnitten

### Aus dem Code-Review

- Animierte WebP wurden immer in voller Auflösung dekodiert und der Puffer nur nach
  Frame-Anzahl begrenzt: eine 4000x4000-Animation hätte 1.5 GB belegt. Frames werden
  jetzt auf Anzeigegrösse verkleinert, der Puffer ist auf 64 MB begrenzt
- Der WebP-Decoder reichte einen Zeiger aus `Data.withUnsafeBytes` an libwebp weiter,
  das ihn behält und später daraus liest. Er besitzt seinen Puffer jetzt selbst;
  geprüft mit 3000 dekodierten Frames unter dem Address Sanitizer
- Konnte keine Datei gelesen werden, rief sich der Bildwechsel unbegrenzt selbst auf.
  Jetzt eine Schleife mit Rundendeckel und sichtbarer Fehlermeldung
- Ken-Burns konnte bei Skalierung 1.0 einen leeren Rand zeigen und hielt bei ganz
  abgespielten Animationen zu früh an
- Vorauslade-Aufgaben wurden nie abgebrochen und füllten den geleerten Cache neu
- Der Frame-Producer lief bei unlesbaren Dateien mit 100 Hz leer
- Zwei unzutreffende `@unchecked Sendable`-Zusagen entfernt
- Meldungen gehen an `os.Logger` statt still verloren

## 1.1.0 - 2026-08-16

- Animierte WebP, GIF und APNG werden abgespielt statt als Standbild gezeigt
- Neue Einstellung "Animationen ganz abspielen": ein Cinemagraph wird nicht mitten in der Bewegung abgeschnitten
- Badge mit Frame-Anzahl auf animierten Kacheln
- Speicherbudget für Animationen mit adaptivem Downsampling
- Gespeicherte Einstellungen überstehen neue Felder, statt auf Standardwerte zurückzufallen

### Behoben

- Hochformat-Bilder sprengten die Raster-Kachel und überlappten Nachbarn
- Vollbild-Slideshow lief mit der Dekodier-Auflösung des kleinen Fensters, Bilder waren unscharf
- Tastatur-Monitor verschluckte Tasten in anderen Fenstern der App
- Vollbildstart schlug fehl, wenn direkt nach dem Programmstart gestartet wurde
- Statuszeile verdeckte die unterste Kachelreihe
- Kacheln waren nur mit der Maus bedienbar

## 1.0.0 - 2026-08-16

Erste Version.

- Import einzelner Bilder, ganzer Ordner (optional rekursiv) und per Drag and Drop
- Abwählen einzelner Bilder aus der importierten Liste
- Sieben Übergänge plus Zufallsmodus, Dauer einstellbar
- Skalierung: Einpassen, Ausfüllen, Einpassen mit unscharfem Rand
- Ken-Burns-Fahrt in vier Stufen, reproduzierbar pro Bild
- Anzeigedauer 1 bis 60 s, Sortierung nach Name, Datum, Grösse oder Zufall
- Vollbild-Player mit Tastatursteuerung und einblendbarer Steuerleiste
- Drei Vorlagen: Bildschirmschoner, Diaschau, Präsentation
- 27 Unit-Tests für die Kernlogik

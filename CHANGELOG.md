# Changelog

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

# -*- coding: utf-8 -*-
"""Layout des Disk-Images für dmgbuild.

dmgbuild schreibt das .DS_Store direkt, ohne den Finder zu bemühen. Der Weg über
AppleScript funktioniert hier nicht: der Finder führt die Befehle zwar aus, legt
die Ansichtseinstellungen aber nie im Image ab (nachgeprüft, das .DS_Store bleibt
ohne BKGD- und Iloc-Einträge). Ohne Finder läuft es ausserdem auf einem CI-Runner.
"""

import os

app = os.environ.get("LUMINA_APP", "dist/Lumina.app")
readme = os.environ.get("LUMINA_README", "build/Read me first.txt")
background = os.environ.get("LUMINA_BACKGROUND", "Resources/dmg-background.png")

files = [app, readme]
symlinks = {"Applications": "/Applications"}

# Fenstermass und Positionen entsprechen dem Pfeil im Hintergrundbild.
window_rect = ((200, 140), (660, 552))
icon_size = 128
background = background

icon_locations = {
    os.path.basename(app): (180, 190),
    "Applications": (480, 190),
    # Unten links, der erklärende Text steht rechts daneben.
    # Tiefer und weiter links: bei 128 Punkten Icon-Grösse stiess die Oberkante
    # sonst an das Label von Lumina.app darüber.
    os.path.basename(readme): (92, 362),
    # Die versteckten Dateien liegen ausserhalb des Fensters. Wer im Finder
    # versteckte Dateien einblendet, sieht sie sonst mitten im Bild stehen.
    ".background.png": (900, 800),
    ".DS_Store": (900, 800),
    ".fseventsd": (900, 800),
    ".Trashes": (900, 800),
    ".VolumeIcon.icns": (900, 800),
}

# Ansicht: keine Seitenleiste, keine Symbolleiste, keine automatische Anordnung.
default_view = "icon-view"
show_icon_preview = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
grid_offset = (0, 0)
label_pos = "bottom"
text_size = 13

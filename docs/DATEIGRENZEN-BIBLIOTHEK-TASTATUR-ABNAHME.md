# Dateigrenzen, Bibliotheksaktualisierung und Tastaturbearbeitung

Stand: 19. Oktober 2026. Synthetische Daten, keine privaten Aufnahmen oder OCR-Inhalte.

## Datei-Reads

`ProjectArchive.readRegularFile` öffnet die Datei mit `O_NOFOLLOW` und `O_NONBLOCK`, prüft Typ und Größe am geöffneten Deskriptor und liest begrenzte Blöcke. Symbolische Verweise, Verzeichnisse und Pipes werden abgelehnt. Selbst eine während des Lesens wachsende Datei wird höchstens bis zur Grenze plus einem Prüfbyte gelesen; sie wird bei Überschreitung nicht zurückgegeben. Diese Regeln gelten auch für bestehende Projektdateien und bei Sicherungen.

| Datei | Grenze |
| --- | --- |
| Originalbild / Bildimport | 512.000.000 Bytes |
| Projektrevision | 32.000.000 Bytes |
| Projektmanifest | 65.536 Bytes |
| Bild-/Videovorschaubild | 8.000.000 Bytes |
| Videometadaten | 1.048.576 Bytes |
| Video-Backupmanifest | 16.777.216 Bytes |

Bestehende Grenzen für portable Projekte, Anleitungspakete, Bildassets und Sicherungsindizes bleiben erhalten. Fehlende, übergroße oder verlinkte Vorschaubilder werden als verwerfbare Caches ignoriert; das Projekt bleibt erreichbar. Unlesbare aktuelle Revisionen dürfen nach den vorhandenen Regeln auf die vorherige zurückfallen. Originale und Pflichtmetadaten werden bei Fehlern nicht als erfolgreich geladen oder gesichert gemeldet. Bestehende Pixelgrenzen bleiben zusätzlich aktiv.

## Bibliothek nach Autosave

Der Editor meldet erst nach erfolgreicher Speicherung den tatsächlichen Dokument-/Thumbnail-Snapshot. Die Bibliothek ersetzt nur diesen Eintrag oder ergänzt eine neu erzeugte Konfliktkopie. Andere Projektpakete, Papierkorb und Videos werden dafür nicht eingelesen. Die Sortierung bleibt konsistent; die Bildvorschauleiste behält ihre Erstellungsreihenfolge und Sieben-Tage-Grenze. Die OCR-Indexsynchronisierung erhält den gespeicherten Dokumentstand.

Vollständige Scans bleiben für Start, Import, Wiederherstellung und explizite Bibliotheksoperationen. Parallel eintreffende erfolgreiche Saves werden mit einem laufenden Scan zusammengeführt; jüngere Revisionen gewinnen, im Papierkorb gefundene IDs werden nicht wiederbelebt. Ein Callback aus einer abgelösten Bibliothek wird verworfen. Ein fehlgeschlagener Save veröffentlicht keinen ungespeicherten Stand.

Messung: `./scripts/benchmark-library-refresh.sh`, optimierter Swift-Build, 500 aktive und 100 gelöschte synthetische Projekte mit je 16 KiB Thumbnail, zwölf Speicherungen pro Lauf. Gemessen wird die Aktualisierung nach dem Save, einschließlich Einlesen beziehungsweise Eintragsersetzung/Sortierung, nicht Thumbnail-Erzeugung, Schreiben oder OCR.

| Variante | Median Lauf 1 | Median Lauf 2 |
| --- | --- | --- |
| Vollständiges Lesen aktiver Projekte und Papierkorb | 146,643 ms | 134,249 ms |
| Gespeicherten Eintrag direkt aktualisieren | 0,141 ms | 0,129 ms |

Vor der Änderung lag der Vollrefresh bei 138,594 ms. Der Vergleich prüft Dokumente und Thumbnail-Daten auf Gleichheit. Dies ist ein lokaler synthetischer Vergleich, keine Zusage zur gesamten App-Laufzeit oder zu beliebigen Bibliotheksgrößen.

## Tastatur

Bei Canvas-Fokus bewegen Pfeiltasten ausgewählte Objekte um einen Ausgabepixel; mit Umschalt um zehn. Die Richtung folgt der sichtbaren Bildfläche. Zoom und Retina ändern die Schrittgröße nicht; freie X-/Y-Bildskalierung wird pro Achse zurückgerechnet. Mehrfachauswahl und Gruppen bewegen sich gemeinsam, einschließlich Callout-Spitzen und Freihandpunkten. Jeder zugestellte Tastenschritt ist ein Undo-Schritt; Gedrückthalten wiederholt die Bewegung. Die vorhandene Zeichenflächenerweiterung und deren Grenzen gelten auch hier.

Aus der Objektliste führt **Im Bild bearbeiten** zum Canvas. In der Liste dienen Pfeiltasten weiterhin der Listenauswahl, in Textfeldern dem Cursor. Befehl-/Wahl-/Control-Pfeiltasten werden nicht als Objektbewegung behandelt. Unbestätigte Gesten, Texteingabe, Zuschnitt, Bildgrößendialog, OCR und Bildwechsel verhindern die Bewegung.

## Prüfnachweise und Grenzen

- `./scripts/test.sh --disable-sandbox`: 139 Domain-Tests bestanden. Neue Tests nutzen Sparse-Dateien für übergroße Originale, Revisionen, Manifeste und Caches; prüfen exakte Grenze, Symlink, Verzeichnis, Pipe, vorherige Revision und atomare Backup-Ablehnung. Der Schalter umgeht ausschließlich den verschachtelten SwiftPM-Compiler-Sandboxstart in der eingeschränkten Entwicklungsumgebung; die App-Sandbox bleibt aktiv.
- `./scripts/test-canvas.sh`: bestehende Canvas-/Zoom-/Crop-/Zeichenflächenprüfungen und neue native Tastaturprüfungen bestanden. Richtungen, 1/10 Schritte, Wiederholung, freie Bildskalierung, Gruppen, Text-/Gesten-/Modifikator-Sperren, Undo/Redo, Speicherung und Zeichenflächenerweiterung geprüft.
- `./scripts/test-library.sh --sandbox`: vollständige Bibliotheks-/Vision-/Bildwechselprüfung bestanden, einschließlich unmittelbarem gespeichertem Snapshot/Thumbnail, unberührten Nachbarprojekten/Papierkorb/Videos, expliziter Fehlererkennung, parallelem Vollrefresh, gescheitertem Save und Konfliktkopie. Echte Vision-OCR, persistenter Suchindex, ungesicherte/gesicherte Abdeckungen, Abbruch und Cache-Löschung ebenfalls erfolgreich. `--incremental-only` und `--search-only` erlauben gezielte Nachprüfungen.
- `./scripts/test-video-library.sh --sandbox`: übergroßer Thumbnail verworfen, übergroße Metadaten und Backup-Manifeste vor Übernahme abgelehnt; bestehende Video-/Sicherungs-/Prozessneustartprüfungen bestanden.
- `./scripts/build.sh -derivedDataPath "$PWD/build/QualityImprovements"`: signierter Debug-Build erfolgreich; Signatur verifiziert, App-Sandbox im Bundle bestätigt. Keine neue echte Capture-, Ton- oder Voll-VoiceOver-Abnahme.
- `python3 scripts/check-localization.py build/QualityImprovements` und `./scripts/test-localization.sh "$PWD/build/QualityImprovements/Build/Products/Debug/Snaprivo.app"`: deutsche/englische Kataloge, Compilerabdeckung und native Sprachneustarts bestanden.

Bei den ersten vollständigen OCR-Läufen verschwanden die temporären synthetischen Projektordner während längerer Vision-Aufrufe; die Diagnose zeigte fehlende Projektmanifeste nach erfolgreichem Vorab-Lesen. Die Testbibliothek liegt jetzt isoliert unter Application Support im eigenen Testcontainer und wird am Testende entfernt. Der vollständige Sandbox-Lauf besteht damit. Die produktive Bibliotheksablage wurde dafür nicht verändert. Reale Last-/Stromausfalltests und vollständige VoiceOver-Bedienung bleiben Q02/Q03.

## TestFlight-Kauf

Der Nutzer bestätigt am 19.10.2026: StoreKit-Kauf im eigenen TestFlight-Client erfolgreich. Das ist ein praktischer Nutzerbeleg für diesen Kaufweg. Buildnummer, Storefront und gelieferter Preis wurden nicht genannt; Restore, Offline-Neustart, Erstattung, frische Installation und Update mit gekauftem Pro bleiben unter K02/K03 offen. Kein erneuter Kauf und keine Store-Veröffentlichung durch diesen Auftrag.

## Scroll-Aufnahme bedienen

Die in diesem Auftrag beschriebene manuelle Abschnittsbedienung wurde am 19.10.2026 auf weiteren Nutzerwunsch ersetzt: Auswahlpfeil neben Neue Aufnahme/Foto → Scroll-Aufnahme → selbst scrollen → Fertig. Bildstände werden automatisch zusammengefügt; einzelne Abschnitte müssen nicht hinzugefügt werden. Aktuelle Bedienung, neue Tests und verbleibende Website-Abnahme: [Scroll-Aufnahme](SCROLL-ABNAHME.md).

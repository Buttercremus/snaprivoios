# Aufnahme-, Text- und Bildwerkzeuge

Stand: 25. Oktober 2026. Lokale Funktionen, macOS 26+, öffentliche AppKit-/Vision-/VisionKit-APIs, keine neue Abhängigkeit.

## Bedienung

- Die Werkzeuggruppe enthält Gestaltung, Drehen/Spiegeln, Bildgröße, Text erkennen und QR lesen. Kopieren, Speichern, Teilen, Öffnen mit und Anheften gehören zu den Bildaktionen. Beide Gruppen bleiben anpassbar; bei wenig Platz stehen weitere Einträge im jeweiligen Mehr-Menü.
- Links: Neue Aufnahme, Nur Text kopieren, QR-Code scannen und Aufnahmevorlagen. Der Vorlagenzugriff bietet den letzten Bereich und vorhandene benannte Bereiche. Die bisherigen Aufnahmeoptionen bieten zusätzlich Text und QR als direkte Aktionen.
- **⌃⇧7** erfasst Text auf dem Bildschirm und kopiert ihn ohne Bildprojekt. **⌃⇧8** liest QR-/Barcodes ohne Bildprojekt. Frei belegbare Kürzel, Übernahme alter Einstellungen einschließlich absichtlich entfernter Belegungen und Konfliktvermeidung. QR-Inhalte öffnen keine URL automatisch.
- In der schwebenden Schnellvorschau stehen Text kopieren und QR lesen direkt bereit. QR-Ergebnisse stehen direkt in der Vorschau; Kopieren und URL öffnen bleiben bewusste Aktionen.
- **Text erkennen** im Editor aktiviert die native Live-Text-Auswahl auf der Bildfläche. Text auswählen und ⌘C verwenden oder die Auswahl bzw. den gesamten erkannten Text rechts kopieren. **Erweiterte Texterkennung** öffnet den vorhandenen Dialog mit Bereich, Sprache und Korrekturmöglichkeit. Die Erkennung erhält eine flache Komposition einschließlich Abdeckungen, Drehung und Gestaltung, niemals das verdeckte Original.
- Ein eingefügtes Bild auswählen: Drehwinkel −180° bis 180° über Zahlenfeld/Regler. Rahmen, Griffe und Trefferfläche folgen der Drehung; Skalieren hält den gegenüberliegenden Anker fest. Live bleibt der Bildmaßstab erhalten. Nach Abschluss wächst die Leinwand passend; Winkel und Leinwanderweiterung bilden einen Undo-Schritt.
- Gestaltung bleibt beim Wechsel zu Auswahl, Pfeil, Text, Formen oder Unschärfe sichtbar. Hintergrund und Schatten liegen hinter der nativen bearbeitbaren Bildfläche; Rand, Ecken und freier Gesamtwinkel bleiben erhalten. Bildmaßstab, Maus-/Griffkoordinaten und native Texteingabe stimmen auch bei Spiegelung und gedrehter Ansicht. Beim Zuschneiden wird die Quellansicht verwendet; danach erscheint die Gestaltung wieder.
- **Nur Text kopieren** startet eine Bereichsauswahl auf dem Bildschirm. Den gewünschten Textbereich aufziehen und die Aufnahme bestätigen; anschließend lokal erkennen und mit ⌘V in einer anderen App einfügen. Escape bricht die Auswahl ab. Während der Erkennung zeigt die Seitenleiste Fortschritt und Abbrechen, danach eine Kopierbestätigung. Die Aktionen werden nach Erfolg, Fehler oder beendetem Abbruch wieder freigegeben. Text aus dem bereits geöffneten Bild bleibt über **Text erkennen** erreichbar.
- Beim Bildwechsel bleibt das bisherige Bild stehen, bis die neue Bildfläche einschließlich Filtern und eigenem Hintergrund vorbereitet ist. Der native Container bleibt erhalten; Filter zeigen beim ersten Bildaufbau keine vorläufigen schwarzen Felder. Der Abstand nach dem Werkzeug-Mehr-Menü enthält keinen ungenutzten flexiblen Leerraum mehr.

## Daten und Grenzen

Dokumentformat 19 speichert den optionalen individuellen Bildwinkel. Bestehende Formate 1–18 bleiben lesbar, ohne neue Felder in alten Formatversionen zu akzeptieren. Undo/Redo, Projektkopien, Speicherung und Export erhalten den Winkel. OCR-Texte und Codes werden nicht ins Projekt geschrieben. Abgebrochene/überholte Erkennungsanfragen dürfen keine Ergebnisse kopieren oder anzeigen. Bestehende Pro-Grenzen gelten für OCR und eingefügte Bilder.

Live Text hängt von Apples Unterstützung und lokalen Erkennungsressourcen ab. Der bisherige Dialog bleibt erreichbar. OCR ist nicht fehlerfrei; optische Unschärfe ersetzt keine deckende Abdeckung. Reale Bildschirmaufnahme, TCC-Erstfreigabe, mehrere Monitore und Space-Wechsel benötigen weiterhin Geräteabnahme. Ein Build ersetzt diese Prüfungen nicht.

## Prüfläufe

- `scripts/test.sh`: Domain-Geometrie, Winkelgrenzen, Formatmigration und kombinierte History.
- `scripts/test-image-frames.sh`: nativer Canvas, Live-Winkel, unveränderter Maßstab, rotierte Trefferfläche/Griffe, gegenüberliegender Resize-Anker, Export und Wiederöffnung; vorhandene Rahmen-/Paddingprüfungen bleiben enthalten.
- `scripts/test-persistent-presentation.sh`: Rahmen/Hintergrund nach wiederholtem Werkzeugwechsel, Pixelvergleich mit gemeinsamer Ausgabetransformation, freier Gesamtwinkel plus 90°-Drehung/Spiegelung, Zuschnitt und ungleiche X-/Y-Skalierung, Pfeil-/Textposition und native Wortauswahl, Zoom/Pan, Undo/Redo und Wiederöffnung.
- `scripts/test-settings.sh`: Werkzeug-/Ausgabegruppen, Sortierung/Neustart sowie Version-1-/Version-2-Hotkeymigration mit bestehenden Konflikten.
- `scripts/test-capture-tools.sh`: synthetische QR-Bilder, Abdeckungen, zusammengesetzte Gestaltung, explizite Clipboard-Schreibgrenze, Abbruch/Berechtigungsentzug und Live Text.
- `scripts/test-workflow-polish.sh`: beobachtete OCR-Belegung bei Start/Abschluss, Kopierbestätigung, Fehler/Abbruch ohne Clipboard-Schreiben; wiederholte Bildwechsel mit vorbereiteten Filtern und Hintergrund, stabilem Container und Prüfung der ersten sichtbaren Bildpixel. Enthält außerdem die vorhandenen Filmstreifenprüfungen für Sichern, Export, Fokus, Fehler und Papierkorb.
- `scripts/build-capture-tools-ui.sh`: isolierte App mit synthetischen Bildern und temporärer Bibliothek für visuelle Abnahme. Keine persönlichen Screenshotdaten.
- `scripts/build-persistent-frame-ui.sh`: isolierte Oberfläche mit Verlauf, Außenabstand, Ecken, Schatten und Bildrand für die Prüfung des Werkzeugwechsels.

Zurückgestellt: Stapelexport, Bildvergleich, automatische Videozooms/Cursor-Nachbearbeitung und automatische Anleitungserfassung.

## Ergebnis der lokalen Prüfung

Vollständiger App-Build erfolgreich; 164 Domain-Tests, native Rahmen-/Drehungsprüfungen, Einstellungen/Hotkeymigration, QR-/Live-Text-Prüfungen und die vollständige Canvas-Suite bestanden. 1175 App-, 7 InfoPlist- und 18 Domain-Texte in Deutsch/Englisch mit Compilerabdeckung geprüft. Auswahl direkt im Bild visuell bestätigt (`build/capture-tools-live-text.png`); der rechte Button wechselt auf „Ausgewählten Text kopieren“. Native Live-Text-Analyse dauerte auf dem verwendeten macOS-27-Prüfsystem in einem Durchlauf rund 67 Sekunden (VisionKit-Laufzeitmeldung); deshalb bleibt das Bild während der Analyse sichtbar und Schließen/erweiterter Dialog bleiben erreichbar. Dies ist keine garantierte Erkennungszeit für macOS 26.

Die Anbindung folgt [Apples öffentlicher Live-Text-Dokumentation](https://developer.apple.com/documentation/visionkit/enabling-live-text-interactions-with-images). Eine gemeinsame Analyzer-Instanz vermeidet wiederholte Einrichtung. Der QR-Einstieg nutzt separat Vision, weil die macOS-Live-Text-Oberfläche auf Text ausgerichtet ist.

Die Korrektur für verschwindende Rahmen wurde zusätzlich mit synthetischer Oberfläche bedient: Gestaltung → Pfeil → Zeichnen → Text. Verlauf und grüner Bildrand bleiben sichtbar, der neue Pfeil erscheint am angeklickten Ort (`build/persistent-presentation-tool-switch.png`). Der Fehler betraf die normale Editoranzeige nach Verlassen der Gestaltung; das Dokument und die Ausgabe hatten die Gestaltung bereits erhalten. Die Korrektur benötigt keine Formatmigration.

Die anschließende Korrektur für Textaufnahme und Bildwechsel besteht App-Build, 164 Domain-Tests, vollständige Canvas-Suite, native Filmstreifen-/Workflow-Prüfungen und die Symbolleistenprüfung in drei Größen auf Deutsch/Englisch. Der Workflow-Test prüft auch den Tastaturfokus nach dem Austausch der Bildfläche. Die OCR-Zustandsprüfung verwendet injizierte synthetische Ergebnisse und kontrollierte Fehler/Abbrüche; sie ersetzt keine reale Bereichsauswahl oder Prüfung der Erkennungsqualität. In der isolierten nativen Oberfläche wurden der geringere Werkzeugabstand und der Hinweis „Text kopiert. Mit ⌘V einfügen.“ bestätigt (`build/workflow-polish-native-ui.png`).


## Ergänzung: eindeutige Textaufnahme und mehrere Miniaturen

Am 25.10.2026 erweitert: Foto-Menüs bieten Textaufnahme und QR; der direkte Modus zeigt Text/QR in der Bereichsauswahl. Eine nicht aktivierende Ergebniskarte hält Fortschritt, Text, QR-Werte und Fehler sichtbar und bietet eine erneute Kopie. Erkennungsaufträge warten geordnet; sofortiger Abbruch, Clipboard-Konflikte, Kopierfehler und verspätete Ergebnisse sind geprüft. Die optionale Schnellvorschau hält bis zu fünf einzelne Bilder unten links. Schließen entfernt nur die Miniatur. [Bedienung, native Abnahme und Prüfnachweise](TEXTAUFNAHME-MINIATUREN-ABNAHME.md).

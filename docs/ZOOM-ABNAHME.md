# E01 – Zoom, Schwenken und Originalgröße

Stand: 12. Oktober 2026. Regulär signierter, sandboxed Xcode-Debug-Build auf macOS 27.0, Retina-Display. Keine Änderung an Bundle-ID, Signierteam oder Aufnahmeberechtigungen.

## Bedienung und Regeln

- Unter dem Bild: Minus/Plus, feste Stufen von 25 bis 1600 %, 100 % und Anpassen. Stufenloser Bereich über Gesten: 5 bis 1600 %. Anpassen hält 24 pt Rand und folgt der Fenstergröße, höchstens bis 100 % (ein Bildpixel pro Bildschirm-Pixel). Kleine Bilder bleiben zentriert und werden beim Vergrößern des Fensters nicht hochgerechnet. Bei 100 % und ganzzahligen Vergrößerungen liegt der Ursprung auf dem Bildschirm-Pixelraster; die Zentrierung bzw. der Zoomanker darf dafür um höchstens einen halben Bildschirm-Pixel abweichen.
- 100 % bedeutet ein Bildpixel pro Bildschirm-Pixel. Auf einem Display mit Skalierungsfaktor 2 ist ein 3840 × 2160-Bild daher 1920 × 1080 pt groß. Der Export bleibt 3840 × 2160 Pixel groß.
- Scrollen verschiebt große Bilder; Umschalt mit Mausrad horizontal. Leertaste halten und Ziehen schwenkt mit Handcursor. Escape verwirft die aktuelle Schwenkgeste. Jede Bildkante bleibt erreichbar, mit höchstens 24 pt Rand an der erreichten Kante.
- ⌘ mit Mausrad und Trackpad-Vergrößerung halten nach Möglichkeit denselben Bildpixel unter dem Mauszeiger. Kleine vollständig passende Bilder bleiben zentriert. Smart Magnify wechselt zwischen 100 % am Zeiger und Anpassen.
- ⌘+/⌘− vergrößert/verkleinert um Faktor 1,25; ⌘1 zeigt 100 %, ⌘0 passt an. Während einer Zeichen-, Griff- oder Canvas-Textauswahlgeste bleibt die Projektion fest.
- Native Texteingabe arbeitet weiter in Bildpixeln. Zoom ändert den View, nicht Schriftmetriken oder Umbruch. Scroll-/Vergrößerungsgesten über dem Textfeld gelten für die Bildansicht. Eine Leertaste während der Texteingabe bleibt ein normales Leerzeichen.
- Ansichtsänderungen erzeugen keine Dokumentrevision, keine Autosave-Schreibvorgänge und keinen Undo-Schritt. Konkrete Zoomstufe/Pan werden nicht persistiert. Seit 14. Oktober 2026 gilt beim Wiederöffnen die gespeicherte Vorgabe „Immer passend verkleinern“ (standardmäßig ein) oder 100 %. PNG/Clipboard bleiben vollständig und verwenden keine Auswahlgriffe.
- Die Bildfläche ist als zugängliche Gruppe beschriftet; Zoom und History-Buttons haben Labels/Tooltips. Bei knapper Breite sind History-Buttons als Symbole vorgesehen. Das ersetzt keine vollständige VoiceOver- und Mindestfenster-Abnahme.

## Automatisierte Nachweise

- `./scripts/build.sh`: signierter Xcode-Build erfolgreich.
- `./scripts/test.sh`: 40 Domain-Tests bestanden. Sechs neue Viewport-Tests prüfen Fit-Rand/Fensteränderung, tatsächliche Pixel bei Backing 1 und 2, Anker beim Zoomen, Hin-/Rückprojektion nach Pan, alle Kanten, Zentrierung kleiner Bilder, unmittelbare Pan-Reaktion nach Fensteränderung und ungültige Zoomwerte.
- `./scripts/test-canvas.sh`: bestehende Canvas-Prüfungen plus `Tests/ZoomCanvasChecks.swift` bestanden. Synthetisches 4K-Bild mit Fit/50/100/400 %; Pfeilzeichnung, Spitze, Formgriff, Klickposition des Texts, native Wortauswahl und Text-Undo nach Zoom/Pan. Zoom mitten im Zeichnen bleibt ohne Wirkung. Leertaste/Ziehen und Escape sowie Tastaturzoom geprüft. Dokumentrevision bleibt unverändert; tatsächliche PNG-Daten vor/nach Ansichtsänderungen sind identisch und behalten 3840 × 2160 Pixel. Ansichtsänderungen verbrauchen keinen Objekt-Undo-Schritt.
- `./scripts/test-renderer.sh` und `./scripts/test-autosave.sh`: erfolgreich. Bestehende Ausgabe-, Textlayout-, Form-/Rand-/Füllungs- und Filterprüfungen sowie Autosave, Wiederöffnen, Text-/Stiltransaktionen, konkurrierende Sicherung, Wiederholung und Konfliktkopie bleiben unverändert erfolgreich.

## Prüfung im laufenden App-Build

Ein neu erzeugtes synthetisches Rasterbild mit farbigen Ecken wurde über den nativen Dateidialog importiert. Das Projekt `SnagForge-Zoom-Abnahme-3840` bleibt mit fünf Testmarkierungen in der Bibliothek: ein Pfeil, drei Textobjekte und ein Rechteck. Keine Nutzeraufnahme wurde bearbeitet.

- 100 % per sichtbarem Button, 200 % per Zoommenü und Anpassen per Button/⌘0 geprüft. Vollständige Bildkanten sind in Anpassen sichtbar.
- Pfeil bei 100 % live gezeichnet. Nach Neustart im finalen Build Spitze von (1440,920) nach (1510,720) gezogen, Anfang bei (1080,820) erhalten; ein ⌘Z stellt den vorherigen Pfeil wieder her. Koordinaten hier beziehen sich auf den 2×-Fensterscreenshot.
- Nach Menüwechsel und Scrollen im Bild neue Textfelder gesetzt und direkt eingegeben. Bei 200 % „Nach“ per Doppelklick markiert, ersetzt und mit ⌘Z wiederhergestellt. Danach auf 100 % gewechselt: Wortauswahl und Text bleiben erhalten.
- Rechteck bei 100 % im verschobenen Bild gezeichnet, rechten unteren Griff vergrößert, ⌘Z/⇧⌘Z ausgeführt.
- Nativer PNG-Speicherdialog schrieb `/tmp/SnagForge-Zoom-Export.png`. Datei geöffnet und geprüft: 3840 × 2160 Pixel, Raster/Markierungen an den erwarteten Positionen, keine Griffe. Nach Beenden und erneutem Start sind alle fünf Objekte wieder sichtbar; Ansicht beginnt mit Anpassen. Letzte Pfeil-Teständerung zurückgenommen und gesichert. Ursprüngliches Nutzerprojekt wieder geöffnet.
- Beim ersten Bedienversuch blieben Canvas-Aktionen nach dem Zoommenü ohne sichtbare Wirkung. Nach expliziter Accessibility-Beschriftung der Bildfläche und Neustart liefen die Folgeprüfungen erfolgreich. Eine eindeutige Ursache dieses ersten Automationsversuchs ist nicht nachgewiesen; kein behaupteter Capture-/Berechtigungsfix.

## Verbleibende Releaseprüfungen

Physische Trackpad-Pinch-/Smart-Magnify-Geste, ⌘-Mausrad und gleichzeitige Leertaste/Mausbewegung bleiben auf echter Eingabehardware zu prüfen; die Leertasten-Ereignisfolge ist im nativen Canvas-Test abgedeckt. Displaywechsel zwischen Backing 1 und 2, macOS 26, vollständige VoiceOver-Bedienung, tatsächliche Mindestfenstergröße und Lasttest mit 50 Objekten gehören zu Q01–Q04. Der Versuch, das laufende Fenster über UI-Automation zu verkleinern, änderte seine Größe nicht und zählt daher nicht als erfolgreiche Mindestfenster-Abnahme.

Der anschließende Schritt E02 Zuschneiden ist inzwischen umgesetzt: [Zuschnitt-Abnahme](ZUSCHNITT-ABNAHME.md). Die aktuelle nächste Aufgabe steht im [Arbeitsplan](ARBEITSPLAN.md).


## Korrektur vom 13. Oktober 2026: kleine Bilder und gemeinsame Leiste

- Ursache der gemeldeten Unschärfe: Anpassen vergrößerte kleine Bilder ohne Obergrenze auf die freie Fläche. Die Ansicht ist jetzt bei 100 % begrenzt und berücksichtigt Backing 1/2; expliziter Zoom bleibt bis 1600 % möglich.
- Pixelgenaues Zeichnen bei 100 % und ganzzahligen Vergrößerungen, hochwertige Abtastung bei Verkleinerungen und gebrochenen Faktoren. Vorschau und Eingabekoordinaten verwenden denselben Ursprung. Exportauflösung und Dokument bleiben unverändert.
- Werkzeuge, Bildgröße, Kopieren und PNG teilen eine obere Leiste im selben Stil. Werkzeuge scrollen bei knapper Breite; die drei Dokumentaktionen bleiben rechts sichtbar. Die drei gespeicherten Leistengrößen gelten für alle Schaltflächen. Projekttitel/Pixelmaße stehen auf Nutzerwunsch im unteren Statusbereich unter Zoom/Undo; der Titel bleibt umbenennbar. Die gemeinsame Werkzeugleiste sitzt direkt unter der Fensterleiste.
- `./scripts/test.sh`: 76 Tests bestanden, einschließlich Fit ohne Vergrößerung, Seitenverhältnis, Backing 1/2 und Pixelraster nach gebrochenem Pan/Fensteränderung.
- `./scripts/test-canvas.sh`: bestanden, zusätzlich ein synthetisches 449 × 441-Bild mit Ein-Pixel-Streifen bei Anpassen/100/200 % in zwei ungeraden Fenstergrößen. Die sichtbaren Bildpixel entsprechen exakt den Quellstreifen, ohne interpolierte Grautöne. Bestehende Zoom-, Eingabe-, Zuschnitt- und Exportprüfungen bestehen weiter.
- `./scripts/test-resize.sh` und `./scripts/build.sh`: erfolgreich. Bestehende Bildgrößen-, Koordinaten-, Undo-, Persistenz- und Exportprüfungen bestehen; reguläre Development-Signierung und Sandbox bleiben aktiv.
- Diese Nachweise sind automatisierte Domain-/AppKit-Prüfungen. Die subjektive Beurteilung an Nutzeraufnahmen, physische Gesten, Displaywechsel und vollständige VoiceOver-Abnahme bleiben davon getrennt.

## Ergänzung vom 14. Oktober 2026: gespeicherte Vorgabe und Bildschärfe

Das Zoommenü bietet „Immer passend verkleinern“. Ein-/Ausschalten wirkt sofort und nach Neustart; deaktiviert beginnen neue/geöffnete Bilder bei 100 %. Die bestätigte Bildgrößen-/Zuschnittänderung einschließlich Undo/Redo folgt derselben Vorgabe. Explizite Zoomstufen gelten weiter für das aktuelle Bild; der Zuschnittentwurf startet für die Übersicht in Anpassen. Die Option beeinflusst weder Bildpixel noch Dokument-Undo oder Autosave.

Die Unschärfe-Vorschau verwendet keine 2048-Pixel-Zwischenkopie mehr. Neue synthetische Canvas-/PNG-Prüfungen bestätigen exakte Ein-Pixel-Streifen außerhalb des Filterbereichs bei einem 4097 × 513-Pixel-Bild. [Vollständige aktuelle Nachweise und verbleibende reale Vergleichsprüfung](BILDSCHAERFE-ABNAHME.md).

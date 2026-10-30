# Komfortfunktionen: Stand und Nachweise

Stand: 16. Oktober 2026. Auf Nutzerauftrag nacheinander implementiert. Keine Veröffentlichung und keine vollständige Release-/Hardwarefreigabe.

| Funktion | Bedienung | Nachweis |
| --- | --- | --- |
| Anheften | Editor → Anheften; schwebendes Fenster verschieben, skalieren, schließen | Native Fensterprüfung: sichtbar, floating, nonactivating, Bildinhalt, Schließen. Zusätzlich Bildstand und Schließen in isolierter App tatsächlich geprüft. |
| Mehrfachauswahl/Gruppen | Umschalt-Klick oder Eigenschaften → Objekte; ⌘A, ⌘G, ⇧⌘G | Auswahl, Gruppierung, unabhängige Duplikatgruppen, Auflösen, Löschen, Undo/Redo, Speichern/Laden; Checkboxen und Gruppierung tatsächlich bedient. |
| Pipette/Pixellupe | Editor → Pipette direkt auf der Bildfläche; Daten rechts. Bewegen zeigt live, Klick hält fest; X/Y oder Pfeiltasten wählen Pixel. | 232 native Koordinaten-/Farbproben mit allen acht Bildtransformationen, Zuschnitt, ungleichmäßiger Skalierung, Zoom/Schwenken und freier Drehung; Hintergrund, sRGB/Alpha, Festhalten, Leertaste-Ziehen, Fokus/Escape und unverändertes Dokument geprüft. Kompakte rechte Seitenleiste und Werkzeugwechsel sichtbar im synthetischen Editor geprüft. |
| Eingefügte Bilder | Editor → Bild einfügen; Griffe zum Skalieren, Umschalt für Proportionen | Getrennte Assets, kompakte Revisionen, Wiederöffnen, Archivimport, Backup/Wiederherstellung, gerenderte Pixel. Synthetisches PNG über echten Dateidialog als ausgewähltes Bildobjekt eingefügt. |
| PNG/JPEG/PDF | Editor → Bildausgabe | PNG-Alpha, deckendes JPEG, PDF-Seitengröße/eine Seite/kein verborgener Text; Dateiausgabe wird beim Abschluss ausstehender Arbeit abgewartet. |
| Ausgabe-Gestaltung | Bildausgabe → Hintergrund, Abstand & Schatten | Pixelmaße mit Abstand geprüft; Präsentationsvorlage, Schatten, runde Ecken und PDF-Vorschau visuell geprüft. Appweite Einstellungen, keine Änderung des gespeicherten Bildprojekts. |
| Scroll-Verbesserungen | Scroll-Aufnahme: automatische Abschnittsübernahme, Rücknahme, Kopf-/Fußausschluss, Originalgrößenvorschau | Injizierte synthetische Frames prüfen automatische Übernahme, Rücknahme, Freigabe der Randkontrollen und Abbruch. Exakte Übergänge, Stabilitätsprüfung, Abschnittslimit, Autosave/Neustart/Undo/Export bestehen. |

## Ausgeführte Prüfungen

- `./scripts/build.sh`: erfolgreicher macOS-Build mit aktivem Sandbox-Profil.
- `./scripts/test.sh`: 124 Domain-Tests bestanden, einschließlich Migration und Scroll-Randausschluss.
- `./scripts/test-convenience.sh`: Auswahl/Gruppen, Assets/Archive/Backup und Abschluss laufender Ausgabe bestanden. Dabei fehlende Assetdateien beim Backup-Restore gefunden und behoben.
- `./scripts/test-image-output.sh`: Formate, Transparenz, PDF, Ausgabegrößen und sRGB-Pipette bestanden. Die Farbfixture verwendet ausdrücklich sRGB statt geräteabhängiger Farbwerte.
- `./scripts/test-scroll.sh`: AppKit-Ereignisschleife mit injizierten Bildern; keine echte Bildschirmaufnahme für diese Prüfung.
- `./scripts/test-canvas.sh`: gemeinsames Ziehen zweier gruppierter Objekte mit einem Undo sowie bestehende Geometrie-, Zoom-, Zuschnitt-, Text-, Werkzeug- und Griffprüfungen bestanden.
- Einstellungen/Speicher sowie bestehende Teilen-/Öffnen-mit-/Export-Abschluss-/Transferprüfungen bestanden.
- Lokalisierungsprüfung: 805 App-Texte, 4 InfoPlist-Texte und 13 Domain-Texte, Deutsch/Englisch, Formatargumente und aktuelle Compilerabdeckung bestanden. Historische Archive im gleichen DerivedData-Verzeichnis werden nicht mit dem aktuellen Build vermischt.
- Isolierte deutsche Produktionsoberfläche mit synthetischen Projekten geprüft. Nutzerbibliothek und laufende Nutzer-App wurden nicht verändert oder neu gestartet. Test-App anschließend beendet.

## Bewusste Grenzen

Anheften ist kein Live-Abbild: Es zeigt den beim Aufruf gerenderten Stand. Spaces-/Vollbildkombinationen und Fokusverhalten mit verschiedenen fremden Apps sind noch nicht breit abgenommen; I01 bleibt dafür offen. Die Scroll-Automatik scrollt nicht selbst, sondern übernimmt geeignete neue Abschnitte. Dynamische Websites, wechselnde Fuß-/Kopfbereiche und verschiedene Browser benötigen weiterhin die P01-Abnahme. Nur der letzte angehängte Abschnitt ist rücknehmbar.

Gruppen unterstützen gemeinsames Bewegen, Duplizieren und Löschen; keine gemeinsame Gruppenskalierung. Ausgabe-Gestaltung wird appweit gemerkt, nicht pro Projekt gespeichert. Eingefügte Bilder sind auf 4096 Pixel je Kante, 8 MB je PNG und 16 MB pro Dokument begrenzt. Alte Originale und Assets bleiben in bearbeitbaren Projekten/Backups erhalten; flache Bildausgaben enthalten ausschließlich die sichtbare Komposition.

## Nachbesserung: ⌘S und Werkzeugtrennung

⌘S öffnet im Bildeditor jetzt denselben nativen PNG-Speicherdialog wie der PNG-Export, statt lediglich das bereits automatisch gesicherte Projekt zu flushen. Menüname: „Speichern als …“. Andere Arbeitsbereiche behalten ihre bisherige Sichern-/Übernehmen-Aktion. Nicht bestätigte Editorzustände und laufende Exporte sperren die Aktion. Trennlinien sind als 3-pt-Kapseln ausgeführt; im zweizeiligen Layout ist die Grenze zwischen Werkzeugen und Bildaktionen auch horizontal sichtbar.

Prüfung: Build, 124 Domain-Tests und 806 App-Lokalisierungen bestanden. In der isolierten deutschen Test-App ein synthetisches Projekt geöffnet, Canvas-Fokus bestätigt und ⌘S gedrückt: natives Save-Panel mit vorgeschlagenem PNG-Dateinamen und Zielordner erschien. Abbrechen führte zurück in den Editor. Die kräftigeren horizontalen und vertikalen Trenner wurden im Screenshot geprüft. Test-App anschließend beendet.

## Kompakte Werkzeugleiste

Vier direkte Aktionen bei normaler Breite, zwei bzw. eine bei schmalerer Detailspalte; übrige sichtbare Aktionen im nativen Mehr-Menü. Pipette/Bild einfügen erscheinen in der Werkzeuggruppe. Einstellungen trennen Bildaktionen und zusätzliche Werkzeuge. Unberührte alte Reihenfolge wird migriert; benutzerdefinierte Reihenfolge, Ein-/Ausblenden, Reset und Speicherung bleiben erhalten. Kürzere Speichern-Beschriftung, kleinere Mindestbreiten und verringerte Abstände. Einstellungen-/Migrationstests sowie 124 Domain-Tests bestehen.

Sichtprüfung in der isolierten deutschen Test-App mit synthetischem Projekt: Bei 1180 × 780 vier direkte Aktionen und Mehr; bei 800 × 540 Kopieren und Mehr mit allen übrigen Aktionen, Teilen genau einmal. Bildausgabe aus Mehr geöffnet und geschlossen. Pipette und Bild einfügen in der linken Werkzeuggruppe bei breitem Fenster sichtbar. Ein bei der Prüfung entdeckter Größenüberlauf wurde durch Begrenzung des Editors auf die verfügbare Fläche und eine flexibel schrumpfende Bildfläche behoben. Build und 828 App-Lokalisierungen geprüft. Das UI-Fixture verwendet ausdrücklich dasselbe macOS-26-Deployment-Target wie die App.

## Kompakter Editorfuß

Bedienhinweis in die Zoom-/Verlaufsleiste verschoben; bei Platzmangel Info-Button mit Tooltip und Popover. Bildname/Pixelmaße darunter mit je 4 pt vertikalem Abstand. Nur laufende Aktionen und Rückmeldungen benötigen noch eine zusätzliche Statuszeile. Build und Lokalisierungsprüfung bestanden. In der isolierten deutschen Test-App mit synthetischem Projekt bei schmalem Fenster Info-Button geöffnet und Erklärung per Escape geschlossen; im breiten Fenster vollständigen Hinweis zwischen Zoom und Verlauf sowie die kompakte Metadatenzeile visuell geprüft. Keine Domain-/Export-/Persistenzlogik geändert.

## Bild/Video und Onboarding mit Kürzelwahl

Build, Capture-Regression, Einstellungen-/Shortcut-Prüfungen, 124 Domain-Tests und 837 App-Lokalisierungen bestanden. Neue Capture-Prüfung betätigt den nativen Umschalter in beide Richtungen: kein vorzeitiges Bestätigen, unveränderter Rahmen/Fensterentwurf, gewählter Medientyp im Ergebnis und Fenster-ID nur bei Video.

Isolierte deutsche Test-App: alle vier Einführungsschritte geöffnet; Konflikt mit bestehendem Bildschirm-Kürzel angezeigt, alternatives Screenshot-Kürzel übernommen. Video-Button in der Hauptsymbolleiste vorhanden. Auf synthetischem Desktop 800 × 600 px gewählt, auf Video gewechselt, unveränderte Maße und Bestätigen-Aktion geprüft. Bestätigung öffnete Video-Vorbereitung mit Systemton/Mikrofon aus, getrenntem „Video starten“ und Abbrechen. Abgebrochen und Test-App beendet. Dieser Test prüft Auswahl/Vorbereitung, keine neue reale Bildschirm-/Audio-Aufnahme oder TCC-Erteilung.

## Direkte Foto-/Video-Aktionen

Die vorherige Auswahl per Umschalter wurde durch zwei direkte Buttons ersetzt. „Foto“ bestätigt sofort als Bild, „Video“ bestätigt sofort für die Videovorbereitung. Keine zusätzliche Aufnehmen-Schaltfläche. Leiste von 504 auf 416 pt verkürzt; Scroll-Aufnahmen bieten ausschließlich Foto. Einführungstext und Produktdokumentation angepasst.

Build, Capture-Regression und Lokalisierungsprüfung (838 App-Texte) bestanden. Native Button-Tests prüfen direkte Bestätigung mit dem jeweiligen Medientyp, unveränderten Ausschnitt, Fensterzuordnung bei Video, fehlenden Umschalter und fehlende Video-Aktion bei Scroll-Aufnahmen.

Isolierte deutsche UI-Test-App: synthetischen Bereich mit 800 × 600 px aufgezogen. Genau zwei Medienaktionen „Foto“ und „Video“ vorhanden. Video-Klick öffnet unmittelbar die Vorbereitung mit optionalem Ton und „Video starten“. Foto-Klick öffnet unmittelbar den Editor mit 800 × 600 Pixel. Test-App anschließend beendet. Keine reale Bildschirm-/Audioaufnahme oder neue TCC-Freigabe getestet.

## Video direkt starten und größere Aufnahmebuttons

„Video“ am Auswahlrahmen startet jetzt ohne zweite Startbestätigung. Gespeicherte Vorgaben für Systemton und Mikrofon unter Einstellungen → Aufnahme → Videoton (anfänglich aus); der gewählte Vorlauf bleibt wirksam. Eine erforderliche Mikrofonfreigabe wird weiterhin vor Countdown/Stream abgefragt. Beide Aufnahmebuttons sind blau, mit 15-pt-Schrift, 22-pt-Symbolen und 36-pt-Buttonrahmen in einer 52-pt-Leiste.

Build, Capture-Regression, Einstellungs-/Neustartprüfungen und 843 App-Lokalisierungen bestanden. Native Video-Tests prüfen Direktstart mit gespeicherten Audiooptionen für 0/3/5 Sekunden, genau einen Streamstart, keine Arbeitsdatei vor Countdownende, Stop/Finalisierung sowie Berechtigungs-, Fehler- und Abbruchpfade. Synthetische Tonspur und Transport; keine neue reale Bildschirm-/Tonaufnahme abgenommen.

Isolierte deutsche Test-App: größere Foto-/Video-Symbole und beide blauen Aktionsbuttons visuell geprüft. Video-Klick führte direkt in „Video startet in 3 …“, ohne weitere Bestätigung. Synthetischen Ablauf geschlossen und Test-App beendet.


## Aufnahmeleiste: Abstände und Hover

Foto/Video verwenden eine gemeinsame Symbolbox (26 pt) und einen festen Textabstand (6 pt). Neu auswählen/Abbrechen haben 20-pt-Symbole in 36 × 36 pt großen Buttons. Native NSButton-Aktionen, Tastatur und Accessibility bleiben erhalten. Hover blendet eine dezente Tönung in 140 ms ein/aus (Neu auswählen blau, Abbrechen rot, Foto/Video heller). Bei „Bewegung reduzieren“ erfolgt der Wechsel ohne Animation. Build und bestehende Capture-Regression bestanden.

Isolierte deutsche Test-App mit synthetischem Desktop: finale Symbolgrößen und gleichmäßige Foto-/Video-Abstände visuell geprüft; blaue Hover-Tönung bei Neu auswählen und rote bei Abbrechen sichtbar. Anschließend per Escape geschlossen und Test-App beendet.

## Ersetzter Scroll-Ablauf – 19. Oktober 2026

Die frühere optionale automatische Abschnittsübernahme mit Hinzufügen/Rücknahme wurde auf Nutzerwunsch durch den direkten Foto-/Aufnahmepfeil und den Ablauf „selbst scrollen → automatisch zusammensetzen → Fertig“ ersetzt. Feste Ränder und Originalgrößenvorschau liegen unter Optionen. Die historischen Nachweise oben beschreiben die damalige Oberfläche; aktueller Stand und verbleibende echte Website-Abnahme stehen in [SCROLL-ABNAHME.md](SCROLL-ABNAHME.md).


## Pipette im Editor – 27. Oktober 2026

Der bisherige Dialog mit zweiter Bildansicht entfällt. Eine native Eingabeebene auf der unveränderten Editorfläche zeigt den Pipettenzeiger und fängt Farbauswahl ab. Koordinaten werden über den tatsächlichen Darstellungsrahmen in die exakten Pixel der flachen Ausgabe abgebildet. Auswahlgriffe und Objekt-Kurzoptionen sind währenddessen ausgeblendet; das gewählte Werkzeug und die Objektauswahl bleiben für die Farbübernahme erhalten. Die rechte Seitenleiste zeigt eine 11×11-Pixellupe mit markiertem Pixel, X/Y, Farbmuster, HEX, RGB, Alpha und Aktionen. Nach Klick bleibt die Farbe beim Wegbewegen zum Kopierbutton erhalten; Live-Vorschau aktiviert die laufende Anzeige erneut. Escape, Schließen, erneutes Anklicken und Werkzeugwechsel beenden den Modus.

Prüfungen am 27. Oktober 2026:
- `./scripts/build.sh -derivedDataPath build/ColorPickerBuild`: erfolgreich.
- `./scripts/test-color-picker.sh`: 232 native Hover-/Klickproben ohne Koordinatentoleranz; alle acht Symmetrien, Zuschnitt, ungleichmäßige Skalierung, drei Zoomstufen, Schwenken, freie Drehung/Gestaltung, zusätzliche Hintergrundproben, festgehaltene Werte, Pipetten-Cursorzuordnung, Leertaste-Ziehen mit Fokus, Pfeiltasten, Escape/Fokusrückgabe, unverändertes Dokument, sRGB/Alpha und abgebrochene Vorbereitung bestanden.
- `./scripts/test.sh`: 173 Swift-Testing- und zwei XCTest-Tests bestanden.
- `./scripts/test-editor-toolbar.sh`: native Größen-/Überlaufprüfungen in Deutsch und Englisch bestanden.
- `python3 scripts/check-localization.py build/ColorPickerBuild`: 1253 App-Texte mit vollständiger Compilerabdeckung und passenden Formatargumenten. Native Sprach- und Neustartprüfungen über `scripts/test-localization.sh` bestanden.
- Sichtbare Bedienprüfung in der isolierten deutschen CleanShot-Test-App mit synthetischem Dashboard bei 1180×780: Öffnen über Mehr, unveränderte Bildfläche, kompakte rechte Seitenleiste mit sämtlichen Farbwerten und Aktionen ohne Scrollen, Klick zum Festhalten, Pfeiltaste, Rückkehr zur Live-Vorschau, Escape und direkter Wechsel zum Pfeilwerkzeug. Der erste zu hohe Inspektor wurde nach dieser Prüfung kompakter angeordnet. Keine Bildschirmaufnahme/Berechtigungsabnahme für diese Funktion nötig; vollständige VoiceOver-Abnahme bleibt manuell.

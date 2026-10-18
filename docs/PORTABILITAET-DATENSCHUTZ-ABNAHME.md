# Projekttransfer, Abdecken und Aufnahmeführung – L03 bis S03

Stand: 13. Oktober 2026. Native macOS-App, Mindestversion 26, Entwicklung und Bedienprüfung auf vorhandenem Mac mit macOS 27/Xcode 27. Sandbox und bestehende Apple-Development-Signierung bleiben aktiv. Keine TCC-Freigabe oder Bundle-ID wurde für diese Prüfung geändert.

## Umgesetzter Ablauf

- **L03:** Ablage → Bearbeitbares Projekt exportieren bzw. Projekt importieren. `.snaprivo` enthält Original und aktuelle Bearbeitung. Import übernimmt eine neue Kopie, einschließlich Crop, Zielauflösung, Textstil, Callout-Ziel, Favorit und Abdeckungen.
- **L04:** Ablage bzw. Dateien-Menü → Bibliothek sichern / Sicherung wiederherstellen. Aktive und gelöschte Projekte bleiben unterscheidbar. Wiederherstellung ergänzt; ID-Konflikte werden zu Kopien. Die gesamte Sicherung verwendet die Bibliothekssperre und wird erst vollständig veröffentlicht.
- **S01:** Direkt sichtbares Werkzeug Abdecken, immer deckend und über normalen Markierungen. Farbe, Position und Größe sind bearbeitbar; Undo/Redo und Autosave greifen. PNG und Clipboard verwenden denselben Renderer. Projekt und Backup behalten das Original; dies steht auch im Exportdialog und Inspektor.
- **S02:** Vorhandene frei belegbare globale Kürzel vom Nutzer physisch bestätigt. Die automatische Fenstervorschau blockiert freies Aufziehen nicht. Cursorreset an Menüleiste/Dock wird durch erneute Cursorzuweisung bei Bewegung/Eintritt behandelt.
- **S03:** Anleitung vor der ersten erfolgreichen Aufnahme; Abschluss erst nach Speicherung, danach Hinweis im Editor. Systemabfrage nur nach ausdrücklicher Aktion und einmal je App-Sitzung. Erneute Prüfung, Rückkehr aus Einstellungen und ein erforderlicher Neustart haben getrennte Zustände. Ablehnung löst keine Prompt-Schleife aus.

## Automatisierte Prüfung

Erfolgreich ausgeführt:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-transfer-privacy.sh
./scripts/test-capture.sh
./scripts/test-renderer.sh
./scripts/test-autosave.sh
./scripts/test-canvas.sh
./scripts/test-settings.sh
./scripts/test-layers.sh
```

Der signierte Build ist erfolgreich; 68 Domain-Tests bestehen. Die folgenden Tests verwenden temporäre Bibliotheken, eigene Defaults und ausschließlich synthetische Bilddaten:

| Bereich | Nachweis |
| --- | --- |
| Portabler Roundtrip | Originalbytes, editierbare Objekte, Crop, Zielauflösung und Favorit in neuer Bibliothek gleich; neue UUID; alte Datei unverändert. Ausstehende Texteingabe wird vor Export gesichert. |
| Backup/Restore | Aktive und Papierkorb-Projekte wiederhergestellt; bei Wiederholung neue Kopien; nach neuem Store/Workspace weiterhin lesbar. |
| Fehler vor Übernahme | Ungültige zweite Datei nach bereits vollständig vorbereitetem ersten Projekt führt zu keinem veröffentlichten Import. SHA-256-Abweichung, Symlink und unbekannte Version abgelehnt. |
| Dateiziele | Vorhandenes Sicherungsziel bleibt bytegleich; fehlender Zielordner ergibt Fehler und lässt die Quellbibliothek unverändert. Größenlimit vor Einlesen geprüft. |
| Abdeckung | Unterschiedliche verdeckte Originalpixel und synthetische Texte ALPHA/BETA ergeben bytegleiche PNGs nach Crop und freier Skalierung auf 41 × 29. Auch Bruchpixelkanten vollständig deckend. Manipulierte Formfüllung/Radius machen Abdecken nicht transparent. |
| Clipboard | Private Testzwischenablage enthält dasselbe flache PNG; zulässig sind nur PNG und von macOS abgeleitete TIFF-Typen. TIFF-Abdeckung auf Alpha 1 und Deckfarbe geprüft. Keine Text-/Projektformate. |
| Dokumentmodell | Format 4 nach 5 migriert, Abdeckungen bleiben oben, Undo/Redo stellt die Objektliste wieder her. |
| Berechtigungen | Injizierte Antworten prüfen fehlende Freigabe, explizite Nachfrage nur einmal, Ablehnung, Freigabe bei Rückkehr, Widerruf und ScreenCaptureKit-Ablehnung trotz positiver Vorprüfung samt Neustartpfad. Keine Systemrechte verändert. |
| Erstaufnahme | Erfolgreiches Anlegen setzt den gespeicherten Abschlussstatus, neuer Preferences-Zustand liest ihn wieder ein. |
| Aufnahmecursor | Erzwungener Pfeilcursor am oberen/unteren Rand wird bei Bewegung wieder zum Kreuz; Eintritt ebenso. Über Bestätigungstasten bleibt der Pfeil, danach wieder Kreuz. Fensterklick, freies Aufziehen innerhalb einer Fensterwahl, Rahmenänderung und Enter/Abbruch bestehen weiterhin. |

Zusätzlich bestehen Renderer-, Crop-, Canvas-, Zoom-, Ebenen-, Autosave- und Einstellungstests. Diese behandeln unter anderem Textauswahl/Undo, Auflösung/Pixelprojektion, Live-Griffe und die exklusive öffentliche Hotkey-Registrierung. Sie ersetzen keine Prüfung mit physischer Eingabe auf allen unterstützten Geräten.

## Bedienprüfung im signierten Build

1. Synthetisches vorhandenes Projekt `SnagForge-Crop-Abnahme` über den nativen Dialog als `/private/tmp/Snaprivo-S03-UI.snaprivo` exportiert. Originalhinweis sichtbar. Wiederimport erzeugt eine neue bearbeitbare Kopie, das Quellprojekt bleibt unverändert.
2. Kopie in `Snaprivo-S03-Abnahme` umbenannt, Abdeckung über Testtext gezeichnet. Deckfarbe/Griffe und Originalhinweis im Inspektor sichtbar. Rückgängig/Wiederholen über die nativen Editor-Schaltflächen geprüft.
3. App regulär beendet und korrigierten Xcode-Build gestartet. Kopie mit drei Markierungen wieder geöffnet; schwarze Abdeckung erhalten und erneut auswählbar. Undo-Historie beginnt erwartungsgemäß leer.
4. Rein synthetische `/private/tmp/Snaprivo-S03-Backup.snaprivobackup` über den nativen Öffnen-Dialog gewählt. Das Paket wird als Sicherung erkannt. Erfolgsmeldung und ein wiederhergestelltes Papierkorbprojekt sichtbar. Dieses wiederhergestellt und im Editor geöffnet: 41 × 29 Pixel, drei Objekte, Favorit erhalten.
5. Nutzer bestätigte auf die Aufforderung zur echten globalen Eingabe: Aufnahme erscheint. Anschließend stellte er klar, dass freies Aufziehen funktioniert; die Beanstandung betrifft den Cursorwechsel an der Taskleiste. Dafür wurde der oben beschriebene Cursorfix ergänzt. Eine erneute physische Randprüfung nach dem Fix ist nicht dokumentiert.
6. Neue Aufnahme über den laufenden Build gestartet: eingefrorene Auswahl mit Fenstervorschau, ohne eigenes Editorfenster beobachtet. Während der Bedienprüfung hat der Nutzer die Auswahl übernommen. Danach im Editor `Screenshot – 13. Okt. 2026, 9:40:45`, 378 × 268 Pixel und „Erste Aufnahme gesichert …“ beobachtet. Keine fremden Fenster oder Nutzerdokumente durch die Aufnahmeoberfläche verschoben.

Die realen Nutzeraufnahmen wurden für die Portabilitätsprüfung nicht verändert oder exportiert. Nur die synthetische Projektkopie und die synthetische Backup-Fixture wurden ergänzt. Keine sensiblen Bildschirmabbilder im Repository abgelegt. Physisches ⌘Z für die neue Abdeckung wurde in dieser Runde nicht separat abgenommen; die Editor-Schaltflächen und nativen Tastatur-/Historientests wurden geprüft.

## Verbleibende Releaseprüfungen

- **Q01:** Cursorwechsel an Menüleiste/Dock nochmals physisch prüfen; macOS 26, mehrere Displays/Spaces, andere Tastaturlayouts und Hotkeykonflikte. Vollständiger TCC-Neuinstallations-/Rechteentzugstest bleibt offen; injizierte Berechtigungsantworten sind keine echte Systemfreigabeprüfung.
- **Q02:** Große Bibliotheken, voller Datenträger und Prozessabbruch. Beim Abbruch während der finalen Mehrprojekt-Übernahme kann eine Teilmenge vollständiger neuer Projekte verbleiben; vorhandene Projekte werden nicht überschrieben. Eine erneute Wiederherstellung kann zusätzliche Kopien erzeugen.
- **Q03/Q04:** Vollständige VoiceOver-/Tastatur-/Kontrastabnahme sowie umfangreiche Farbraum-, Ausgabe- und Lastfälle. Bestehende Abdecktests begründen keine Aussage über automatisch erkannte sensible Inhalte oder bereinigte bearbeitbare Projekte.

Nächster geplanter Umsetzungsschritt: **T01 – manuelles Scroll-Stitching**. [Arbeitsplan](ARBEITSPLAN.md), [Formatbeschreibung](PROJEKTFORMAT.md).


## Nachtrag: Snaprivo und Kopierbestätigung

Am 13.10.2026 App-Produkt, Xcode-Projekt, Scheme und Target auf Snaprivo umgestellt; sämtliche sichtbaren App-Texte angepasst. Bundle-ID, Development-Zertifikat und designated requirement stimmen mit dem bisherigen Build überein. Bibliothekspfad bleibt stabil. Der gestartete Snaprivo-Build zeigte alle 29 vorhandenen Projekte; synthetisches Projekt erneut geöffnet, ohne Datenmigration.

Kopieren am synthetischen Projekt im laufenden Build angeklickt: Häkchen und „Kopiert“ direkt im Button sowie Accessibility-Label „Bild kopiert“ beobachtet. Feste Labelabmessungen verhindern Layoutsprünge. Native Tests prüfen sofortigen Arbeitszustand, Erfolg erst nach PNG-Schreiben, erneutes Kopieren, Rücksetzen nach 1,6 Sekunden und ausgeschaltete Animation bei Tastaturaufruf. Reduzierte Bewegung wird im View berücksichtigt; eine gesonderte Systemeinstellungs-/VoiceOver-Abnahme wurde nicht durchgeführt. Signierter Build und 68 Domain-Tests bestanden.

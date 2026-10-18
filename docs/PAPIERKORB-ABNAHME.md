# L02 – Papierkorb und Wiederherstellung

Stand: 13. Oktober 2026.

## Verhalten

- Projektkarte oder Kontextmenü: In den Papierkorb.
- Papierkorb-Schalter: Wiederherstellen oder Löschen mit separater, projektbezogener Bestätigung.
- Vor dem Verschieben des offenen Projekts werden laufende Text-/Stiländerungen abgeschlossen und gespeichert. Bei Speicherfehler bleibt das Projekt geöffnet.
- Original, Objektliste, Titel und Favoriten bleiben nach Neustart erhalten. Wiederherstellung überschreibt keine vorhandene Projekt-ID.
- Der App-Papierkorb wird nicht automatisch geleert. Eine bereits bestätigte, unterbrochene endgültige Löschung wird beim Laden fortgesetzt.

## Nachweise

`./scripts/build.sh` erfolgreich. `./scripts/test.sh`: 63 Tests bestanden. `./scripts/test-trash.sh` und `./scripts/test-library.sh` bestanden.

Domain-Tests prüfen Neustart mit neuem Store, Original/Metadaten-Roundtrip, blockiertes veraltetes Autosave, ID-Kollision ohne Überschreiben, Schutz aktiver Projekte vor endgültigem Löschen sowie Wiederaufnahme einer simulierten unterbrochenen Löschoperation.

Workspace-Test mit temporärem synthetischem Bild prüft ungesicherten Text vor dem Verschieben, Schließen des Editors, neue Workspace-Instanz, Wiederherstellung und endgültige Löschung mit anschließend leerer Bibliothek und leerem Papierkorb.

Native App: Nur das synthetische Projekt „SnagForge-Crop-Abnahme“ verschoben. Bibliothek 25 → 24, Papierkorb 1; Löschdialog mit Projektname geprüft und abgebrochen. App beendet und neu gestartet: Projekt mit 2 Markierungen weiterhin im Papierkorb. Wiederhergestellt: Bibliothek wieder 25, Papierkorb leer. Keine Nutzeraufnahme gelöscht. Endgültiges Löschen wurde über den automatisierten temporären Test geprüft, nicht an der Nutzerbibliothek.

## Grenzen

Kein Mehrfachlöschen oder Papierkorb-leeren-Befehl. Tatsächlicher Stromausfall, voller Datenträger und defekte Dateisysteme bleiben Teil Q02; der Unterbrechungstest simuliert den dauerhaften Zwischenzustand. Bibliotheksansicht und Suche werden beim Neustart zurückgesetzt, Projektstatus bleibt gespeichert.

# L01 – Namen, Favoriten und Sortierung

Stand: 13. Oktober 2026. Implementierter Stand.

- Umbenennen über Karte/Kontextmenü und Editor-Titel. Dialog mit Abbruch, gültigem Namen und sichtbarem Speicherfehler. Leerzeichen außen werden entfernt; leere und über 1.024 Zeichen lange Namen werden abgelehnt. Gleiche Namen sind zulässig; IDs bleiben unverändert.
- Stern pro Karte, gemeinsamer Favoritenfilter und Titelsuche. Filter und vier Sortiermodi bleiben nach Neustart erhalten. Der Suchtext selbst ist nicht persistent.
- Sortiert nach Änderungsdatum auf-/absteigend oder natürlicher Namensreihenfolge A–Z/Z–A. Gleichstände werden stabil anhand der Projekt-ID aufgelöst.
- Namen/Favoriten sind Dokumentmetadaten und aktualisieren das Änderungsdatum. Original, Objekte und Vorschaubild bleiben erhalten. Bild-Undo verändert diese Metadaten nicht; erneutes Umbenennen oder Sternklick ändern sie wieder.
- Aktive Editorprojekte werden über deren Zustand geändert und geflusht. Geschlossene Projekte erhalten unter der Dateisperre eine neue Metadatenrevision. Fehler bleiben sichtbar, beim Beenden wird auf laufende Metadatenänderungen gewartet.

## Nachweise

- Signierter Xcode-Build erfolgreich.
- 61 Domain-Tests erfolgreich: persistente Metadaten, alte Dokumente ohne Favorit, unverändertes Original/Objekte/Thumbnail, No-op, ungültige Namen und Schutz gegen veraltete Saves.
- `scripts/test-library.sh`: alle vier Sortierungen, natürliche Zahlenfolge, neue Workspace-/Store-Instanz, persistente Präferenzen, geöffnetes Projekt mit ausstehendem Autosave, spätere Bildänderung, Undo-Isolation und Favorit entfernen erfolgreich.
- Bestehende Autosave- und Einstellungstests erfolgreich.
- Im laufenden Build: synthetisches Projekt in der Bibliothek umbenannt, favorisiert, Favoritenfilter und Name A–Z eingestellt; nach App-Neustart alle vier Werte vorhanden. Über Editor-Titel zurückbenannt, Favorit entfernt, Filter und Sortierung zurückgesetzt. Originalname und zwei Markierungen wieder vorhanden.

Offen unter den allgemeinen Releaseprüfungen: vollständige VoiceOver-Abnahme, sehr große Bibliotheken und macOS 26. Papierkorb gehört zum nächsten Arbeitspaket L02.

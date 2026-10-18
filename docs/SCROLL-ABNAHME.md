# T01 – Manuelle Scroll-Aufnahme

Stand: 13. Oktober 2026. **T01 als manueller Prototyp abgenommen.** Der Menüpunkt ist wieder aktiv. Die vollständige Produktisierung und breite Website-Kompatibilität bleiben P01; dies ist keine allgemeine Website-Kompatibilitätszusage.

## Bedienung

1. Aufnahme → Scroll-Aufnahme (manuell) … wählen.
2. Ausschließlich den scrollbaren Inhalt aufziehen und Aufnahme bestätigen. Fixierte Kopf-/Fußzeilen ausschließen.
3. Manuell nach unten scrollen und mindestens ein Drittel Überlappung behalten. Fenster nicht verschieben, Animationen abwarten.
4. Abschnitt hinzufügen. Vorschau und Abmessungen werden aktualisiert; bei einer Ablehnung bleibt das bisherige Ergebnis erhalten. Zurückscrollen und einen kleineren Schritt versuchen.
5. Nach mindestens zwei Abschnitten Im Editor öffnen. Das zusammengesetzte Bild wird als Projekt gespeichert; Markierungswerkzeuge, Undo/Redo und Export stehen über den normalen Editorweg bereit.
6. Abbrechen verwirft nur die laufende Scroll-Sitzung, nicht vorhandene Projekte. Eine unfertige Scroll-Sitzung wird nicht für einen Neustart gespeichert.

## Umsetzung und Grenzen

ScreenCaptureKit friert zunächst den Desktop für die Bereichsauswahl ein. Nach der Auswahl wird die App des Zielinhalts aktiviert; die erste Live-Aufnahme erfolgt nach der Fokusumschaltung über denselben Aufnahmeweg wie spätere Abschnitte. Ein vollständiges Displaybild wird in der bestehenden Retina-/Koordinatenprojektion auf den gewählten Bereich zugeschnitten. Eigene App-Fenster und Cursor sind ausgeschlossen. TCC-Prüfung und Sandbox bleiben aktiv; keine Bedienungshilfenfreigabe oder automatische Scroll-Steuerung.

Das Vorschaufenster ist ein nicht aktivierendes AppKit-Panel mit eigenen Tastatur- und Accessibility-Bedienelementen. Der Zielinhalt bleibt bedienbar. Verarbeitung erfolgt außerhalb des MainActor. Zwei zeitversetzte Bilder prüfen auf Bewegung. Der Domain-Matcher sucht vertikale Überlappung, prüft Mehrdeutigkeit und feststehende Ränder. Der Vergleich am unteren Bildrand wurde korrigiert: wiederkehrende Textzeilen in tatsächlich scrollenden Abschnitten werden nicht mehr allein deshalb als feste Fußzeile abgelehnt. Konservative Heuristiken bleiben; Animationen und gleichförmige Muster können eine Wiederholung erfordern.

Nur abwärts, unveränderte Breite/Position/Skalierung, kein horizontaler Versatz. Maximal 4.096 px je Frame-Dimension, 20.000 px Gesamthöhe, 40 Megapixel und 50 Abschnitte. Die zusammengesetzten Abschnitte bilden einen flachen Hintergrund; neue Annotationen bleiben bearbeitbar. Noch keine nachträgliche Nahtkorrektur oder Entfernung einzelner Abschnitte. Breite Erprobung schwieriger Seiten, Vollbild, mehrerer Displays und Speicherverhalten gehört zu P01/Q01.

## Automatisierte Nachweise

- `./scripts/build.sh`: erfolgreich, Deployment Target macOS 26, Sandbox und bestehende Development-Signierung. Testhost: macOS 27; keine separate Hardware-Abnahme unter macOS 26 behauptet.
- `./scripts/test.sh`: 72 Tests erfolgreich. Scroll-Fälle: exakte Verschiebungen, zu große Sprünge, unveränderte/leere Bilder, wiederholte Muster, feste Kopf- und Fußzeilen, wiederkehrende scrollende Textzeilen, Bewegung, Größen-/Abschnittslimits.
- `./scripts/test-scroll.sh`: drei Ausschnitte pixelgenau rekonstruiert, Orientierung/Naht geprüft, Bewegung und Abschnittslimit abgelehnt. Zusammengesetztes Bild im Editor geöffnet, Pfeil/Text/Rechteck per echtem Autosave gespeichert, mit neuer Workspace-/Store-Instanz geladen, weiterbearbeitet, Undo/Redo und PNG-Auflösung geprüft. Keine echten Bildschirmdaten in Testfixtures.
- `./scripts/test-capture.sh`: Capture-/Berechtigungsregression erfolgreich. Ein Build ersetzt keine Systemfreigabe; der Desktop-Test nutzte die vorhandene Freigabe.

## Desktop-Abnahme am 13.10.2026

Durchgeführt mit dem aktuellen signierten Xcode-Debug-Build und ausschließlich synthetischem Aufnahmeinhalt:

1. Den scrollbaren Bereich der nativen Testfixture gewählt und bestätigt: 1 Abschnitt, 1.295 × 1.370 px.
2. Jeweils 120 pt nach unten gescrollt und Abschnitt hinzugefügt: 2 Abschnitte, 1.295 × 1.610 px; anschließend 3 Abschnitte, 1.295 × 1.850 px.
3. Im Editor geöffnet; fortlaufende Abschnitte 1–8 ohne sichtbare doppelte oder fehlende Textzeilen geprüft.
4. Projekt in `Snaprivo-T01-Abnahme` umbenannt; Pfeil, Text „T01: bearbeitbar“ und Rechteck eingefügt.
5. Snaprivo normal beendet und denselben Build neu gestartet. Bibliothek zeigte `Snaprivo-T01-Abnahme` mit 3 Markierungen.
6. Projekt geöffnet: Auflösung und alle Markierungen erhalten. Pfeil erneut ausgewählt und verschoben, Rückgängig/Wiederholen über die Editoraktionen geprüft. Globaler Tastaturtest wurde dabei nicht erneut abgenommen.

Vorherige Desktop-Tests zeigten auch die sichtbare Ablehnung eines uneindeutigen Übergangs sowie Abbruch ohne neues Projekt. Das fertige synthetische Abnahmeprojekt bleibt in der lokalen Bibliothek zum Nachprüfen erhalten.

### Reproduzierbare Testfixture

`./scripts/build-scroll-fixture.sh` baut `build/ScrollFixture.app` aus `Tests/Fixtures/ScrollFixtureApp.swift`. Die Fixture enthält ausschließlich lokale synthetische Texte und Farbbalken. „Zum Anfang“ setzt zurück; „120 pt nach unten“ führt einen reproduzierbaren Scroll-Schritt aus. Nur den Inhalt links aufnehmen, die Bedienelemente rechts ausschließen. Die tatsächlichen Pixelmaße hängen vom aufgezogenen Bereich und der Displayskalierung ab. Die Fixture gehört nicht zum ausgelieferten App-Target.

## Ordnerumbenennung

Projektwurzel: `/Users/simon/Woerk/Swift/Snaprivo`. Innerer Quellordner: `Snaprivo/`; Xcode-Projekt und Skripte angepasst. `Packages/SnagForgeDomain` ist weiterhin benötigter Quellcode. Bundle-ID und bestehende Speicherpfade bleiben aus Kompatibilitätsgründen erhalten. Keine Nutzerprojekte gelöscht.

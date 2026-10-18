# Markieren und Liste (P03)

Stand: 13. Oktober 2026. Implementiert und automatisiert mit synthetischen Bildern geprüft. Die persönliche Bedienprüfung im laufenden Editor übernimmt der Nutzer; sie wird durch Build und isoliertes Rendern nicht ersetzt.

## Bedienung

- **Markieren:** Rechts zwischen Rechteck und Freihand wählen. Rechteck aufziehen oder freihändig zeichnen; ein Klick setzt einen runden Punkt. Farbe und Deckkraft (5–80 %) sind einstellbar, Freihand zusätzlich mit 4–160 px Breite. Multiplizieren erhält schwarze Schrift unter der Markierung. Wechsel des Modus beginnt eine neue Markierung; bestehende Pfade werden nicht umgewandelt.
- **Liste:** Jeder Klick setzt eine Marke. Rechts Kreis, abgerundetes Rechteck, Raute oder Pfeilmarke wählen; Füllfarbe, Textfarbe, Größe (24–240 px) und Typ ändern. Zahlen zählen 1, 2, 3 …; Buchstaben A, B, C …, Z, AA … . Eine ausgewählte Marke hat einen veränderbaren Wert. Eigenschaftenänderungen gelten auch als Vorgabe für folgende Marken in dieser Sitzung.
- **Folge:** Nächster Wert = höchster vorhandener Wert desselben Typs + 1. Bestehende Werte bleiben beim Löschen und Anordnen stabil. Wird der höchste Wert gelöscht, ist er wieder der nächste. Zahlen und Buchstaben haben getrennte Folgen. Manuell gleiche Werte sind erlaubt. Duplizieren erhält eine neue ID und den nächsten Wert. Pro Typ sind Werte bis 10.000 möglich.
- **Bearbeiten:** Beide Werkzeuge bleiben nach jeder Zeichnung bzw. jedem Klick aktiv. Für Verschieben/Griffe Auswahl wählen. Rechteckmarker haben acht Griffe, Marken behalten beim Resize ihr Seitenverhältnis; Freihandstriche lassen sich als Ganzes verschieben. Escape verwirft eine laufende Zeichengeste. Eine Geste, ein Klick oder eine abgeschlossene Reglerbewegung ist ein Undo-Schritt.
- **Speichern/Ausgeben:** Pfade, Geometrie, Werte und Stile bleiben bearbeitbar. Wiederöffnen und Undo/Redo bestimmen den nächsten Wert aus dem tatsächlichen Dokument. Crop, Resize, PNG, Zwischenablage und Vorschaubilder verwenden denselben Renderer. Deckende Abdeckungen bleiben über beiden neuen Werkzeugen.

## Nachweise

- `./scripts/test.sh`: 82 Domain-Tests, einschließlich Zahlen-/Buchstabenfolgen, Grenzwerten, stabilen Werten, Undo/Redo, Pfadtranslation/Duplizierung, Format-6-Roundtrip, Migration 1–5, ungültigen Metadaten und Wiederöffnen über ProjectStore.
- `./scripts/test-canvas.sh`: Native Mausereignisse für fortlaufende Klickmarken, A/Z/AA/AB, Duplizieren, Verschieben, Griffe und gruppierte Größenänderung; Rechteckmarker, Freihand, geschlossene Striche, Klickpunkt, sofortige Punktvorschau und Escape; alle vier Formen und passende Zeichen; schwarze Quellschrift bleibt schwarz; deckende Abdeckung nach Resize; PNG-/Clipboard-Bytegleichheit nach Crop/Resize; Wiederöffnen und abgeleitete Zähler.
- `./scripts/test-renderer.sh`: Bestehende Renderer- und Zuschnittregressionen.
- `./scripts/test-transfer-privacy.sh`: Bestehende Export-/Zwischenablage-/Projekttransfer-/Backupregressionen einschließlich deckender Abdeckungen.
- `./scripts/build.sh`: Signierter macOS-Build.
- Die tatsächlichen SwiftUI-Inspektoren wurden isoliert mit NSHostingView in beiden Markermodi gerendert. Formen, Farben, Typauswahl, Abstände und Regler ohne Skalenstriche passen in den 224-pt-Eigenschaftenbereich. Synthetische Ausgabe wurde visuell geprüft; keine Nutzeraufnahme wurde als Fixture übernommen.

## Verbleibende Prüfung

Bediengefühl und Lesbarkeit auf den vom Nutzer verwendeten Bildern/Displays persönlich prüfen. Sehr lange Freihandstriche und Projekte nahe den bestehenden Objekt-/JSON-Grenzen gehören zur noch offenen Leistungs-/Releaseabnahme Q01–Q04. Eigene dauerhaft gespeicherte Werkzeugstile (P02) und mehrseitige Anleitungsausgabe (P06) sind weiterhin offen.

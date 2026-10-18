# Handgezeichnete Pfeile und Kreise

Stand: 16. Oktober 2026

## Bedienung

Pfeil oder Ellipse wählen, im Eigenschaftenbereich **Zeichenstil → Handgezeichnet** einstellen. Mit ausgewähltem Objekt ändert die Wahl dieses Objekt als einen Undo-Schritt und die Vorgabe für weitere Objekte desselben Werkzeugs. Ohne Auswahl wird nur die Vorgabe geändert. Pfeil und Ellipse behalten getrennte Vorgaben. **Präzise** stellt den bisherigen Stil wieder her. Umschalt beschränkt Ellipsen weiterhin auf Kreise und Pfeilendpunkte auf das vorhandene Winkelraster.

Der Pfeil hat eine feste geschwungene Kurve, runde Linienenden und eine offene, asymmetrische Spitze. Ellipsen besitzen eine leicht unregelmäßige Kontur mit einer kleinen Öffnung oben rechts. Farbe, Linienbreite und bei Ellipsen die bestehenden Kontur-/Fülleinstellungen bleiben verfügbar. Richtung und Stärke der Biegung sind noch keine separaten Bedienelemente. Andere Formen, Schrift und Freihandwerkzeug ändern sich nicht.

## Konsistenz

- Deterministische Vektorgeometrie aus Anfang/Ende beziehungsweise Rechteck: kein Zufallszittern beim Zeichnen, Duplizieren oder Neuladen.
- Vorschau, PNG, Bildkopieren, Vorschaubilder und OCR verwenden den gemeinsamen Renderer.
- Trefferprüfung eines handgezeichneten Pfeils berücksichtigt Kurve und offene Spitze, auch nach nicht proportionaler Bildskalierung. Die vorhandenen Endpunktgriffe bleiben erhalten.
- Undo/Redo, Autosave, Werkzeugvorgaben beim Editorwechsel sowie eigene Stilvorlagen erhalten den Zeichenstil.
- Projektformat 8 migriert Versionen 1–7; vorhandene Objekte bleiben präzise, Tags/Sammlungen aus Version 7 bleiben erhalten. Ältere Builds lehnen das neue Format ab.

## Nachweise und Grenzen

- `./scripts/test.sh`: 123 Domain-Tests bestanden, einschließlich Kurven-Trefferprüfung, Verschieben/Duplizieren, Stilvorlagen, Undo und Format-7-Migration mit Organisation.
- `./scripts/test-hand-drawn.sh`: native Stiländerung, Undo/Redo, Autosave und Wiederöffnen, bytegleicher PNG-Export nach Crop/Resize und Wiederöffnen, Pixelprüfung an Kurve statt gerader Verbindung sowie Vorgaben und Editorwechsel bestanden. Erzeugt ausschließlich synthetische Vergleichsdaten unter `build/HandDrawnTests/comparison.png`.
- `./scripts/test-renderer.sh`: bestehende Renderer-, Form-, Transparenz-, Text-, Unschärfe- und Zuschnittprüfungen bestanden.
- `./scripts/build.sh`: macOS-App erfolgreich gebaut.
- Vergleichsbild aus dem Produktionsrenderer visuell geprüft. Persönliche Bedienprüfung mit Maus/Tastatur und VoiceOver im laufenden Editor bleibt offen. Die laufende Nutzer-App wurde nicht beendet; zum Laden der Änderung neu starten.

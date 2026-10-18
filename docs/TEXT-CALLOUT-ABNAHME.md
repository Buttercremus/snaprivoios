# E05 – Schrift und Callout-Zeiger

Stand: 13. Oktober 2026. Implementiert im signierten Entwicklungsbuild.

## Bedienung

- Text oder Callout auswählen: Schriftfamilie, Fett/Kursiv und Links-/Mittel-/Rechtsausrichtung im Inspector. Die Formatierung betrifft das ganze Objekt; keine gemischten Schriftstile innerhalb eines Textes.
- Installierte Schriftfamilien werden angeboten; Systemschrift ist separat wählbar. Fehlende Familien behalten ihren gespeicherten Namen, werden als nicht verfügbar markiert und mit einer Ersatzschrift dargestellt. Nicht jede Schriftfamilie enthält alle Schnitte; es wird ein verfügbarer Schnitt verwendet.
- Bestehende Objekte ohne neue Attribute behalten Systemschrift Semibold und Linksausrichtung. Der alte Callout-Zeiger bleibt zunächst unten links. Neue Attribute werden mit Format 4 gespeichert; Versionen 1–3 bleiben lesbar.
- Runder Griff: Zeigerziel verschieben. Eckige Griffe: Rahmen ändern, Ziel bleibt fest. Verschieben/Duplizieren: Rahmen und Ziel bewegen sich gemeinsam. Bei einem Ziel im Rahmen verschwindet der herausstehende Zeiger, nicht sein Griff.
- Ziehen aktualisiert die Vorschau live und wird beim Loslassen ein Undo-Schritt. Escape verwirft die Vorschau. Textformatierung außerhalb der Eingabe ist ein Schritt; innerhalb einer Eingabe gehört sie zur Textsitzung. Native Textauswahl und Text-Undo bleiben erhalten.
- Autosave sichert nach 450 ms Ruhe. PNG, Zwischenablage und Vorschau verwenden dieselben Schriftmetriken und dieselbe Zeigergeometrie, auch mit Zuschnitt und geänderter Zielauflösung.

## Prüfung

- `./scripts/build.sh`: erfolgreich, bestehende Signierung und Bundle-ID erhalten.
- `./scripts/test.sh`: 59 Tests erfolgreich, darunter Format-3-Migration mit Zuschnitt/Zielauflösung, Legacy-Vorgaben, neue Eigenschaften, Duplizieren/Translation, History sowie ungültige Fontnamen und Zeigerkoordinaten.
- `./scripts/test-typography.sh`: native Font-/Absatzmetriken, fehlende Schrift, automatische Textbreite bei Zentrierung/Rechtsausrichtung, Live-Zeiger ohne vorzeitigen Commit, getrennte Rahmenänderung, vier Zeigerrichtungen, Duplikate, native Textauswahl, Undo/Redo, tatsächliches verzögertes Autosave/Wiederöffnen und identische PNG-/Clipboard-Ausgabe erfolgreich.
- Bestehende `test-canvas.sh`, `test-renderer.sh`, `test-autosave.sh`, `test-resize.sh` und `test-layers.sh` erfolgreich.
- Im laufenden Build: synthetischen Callout angelegt, Helvetica/Kursiv/Zentrierung gesetzt, Zeiger nach oben links gezogen, Undo/Redo ausgeführt. App beendet und neu geöffnet: Schrift, Stil und Zielposition erhalten. Fett ausgeschaltet und rechtsbündig gewählt. Anschließend den eigenen Test-Callout entfernt; die Bibliothek zeigt wieder die ursprünglichen zwei Markierungen.

## Grenzen und Releasefälle

Keine eingebetteten Fontdateien oder gemischte Zeichenformatierung. Ersatzschriften können auf anderen Macs abweichende Metriken besitzen. VoiceOver-Vollabnahme, weitere Schriftfamilien/Schriftsysteme und macOS 26 stehen weiterhin unter Q01–Q04; Build und automatisierte Tests ersetzen diese Abnahme nicht.

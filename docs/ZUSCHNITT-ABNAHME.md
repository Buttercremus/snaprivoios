# E02 – Zuschneiden

Stand: 12. Oktober 2026. Implementiert und im regulär signierten, sandboxed Xcode-Debug-Build auf diesem Mac mit macOS 27 geprüft. Ausschließlich synthetische Bilder verwendet. E02 ist abgeschlossen; die übergreifenden Releaseprüfungen Q01–Q04 bleiben offen.

## Ergänzung vom 14. Oktober 2026: gemeinsame Griffe

Zuschneiden verwendet jetzt dieselben runden Eckgriffe und länglichen Seitengriffe wie Aufnahme und Formen. Größe und Trefferflächen sind in Ansichtspunkten definiert, unabhängig vom Zoom. Bei überlappenden Flächen entscheidet der Abstand zum Griffmittelpunkt. ⌥ beginnt ausdrücklich eine neue Auswahl, auch über einem vorhandenen Griff. Native Pixel-/Mausprüfungen bei 50/100/400 %, Undo, Abbruch und Export bestehen; die persönliche Bedienprüfung übernimmt der Nutzer. [Gemeinsame Nachweise](AUSWAHLGRIFFE-ABNAHME.md).

## Bedienung

- **Zuschneiden** in der Werkzeugleiste oder **⌘K** zeigt das ganze Original und den bisherigen Ausschnitt. Ausgeblendete Bildteile sind abgedunkelt; Rahmen, Drittellinien und acht Griffe erscheinen sofort.
- Einen Rahmen in beliebiger Richtung aufziehen. Griffe korrigieren die Kanten, Ziehen innerhalb eines bereits verkleinerten Rahmens verschiebt ihn. **⌥ und Ziehen** beginnt auch darin einen neuen Rahmen. Bei noch vollständig ausgewähltem Original beginnt Ziehen im Inneren direkt einen neuen Rahmen.
- Im festen Inspektor lassen sich **X, Y, Breite und Höhe** in ganzzahligen Originalpixeln eingeben. Minimum ist 1 × 1 Pixel; Eingaben und Griffe bleiben innerhalb des Originals. Zahlenwerte und Rahmen aktualisieren sich während des Ziehens.
- **Übernehmen** oder die Eingabetaste bei Canvas-Fokus bestätigt alle Rahmenänderungen gemeinsam. **Abbrechen**, Escape bei Canvas-Fokus oder ein anderes Werkzeug verwirft nur die Vorschau und stellt die vorherige Ansicht wieder her. Während einer Ziehgeste sind Übernehmen und Zahlenfelder gesperrt; danach werden sie wieder aktiv. In Zahlenfeldern gelten die nativen Textfeldbefehle.
- **Ganzes Original** setzt den Entwurf auf die ursprünglichen Grenzen. Danach Übernehmen. Alternativ hebt **Bearbeiten → Zuschnitt aufheben** den bestätigten Zuschnitt direkt auf.
- Nach Bestätigung zeigt der Canvas ausschließlich den Ausschnitt und passt ihn ans Fenster an. Header, PNG, Zwischenablage und Bibliotheksvorschau verwenden dessen Abmessungen. Zeichnen, Text und Objektgriffe funktionieren weiterhin in derselben Projektion. PNG/Kopieren sind während einer unbestätigten Vorschau gesperrt.

## Dokument- und Koordinatenregeln

`pixelSize` bleibt die Größe des unveränderten Originals. `crop` ist optional und speichert ein ganzzahliges Rechteck im Original mit Ursprung oben links. `nil` bedeutet ganzes Original. Objektpositionen, Schriftgrößen, Linienbreiten und IDs ändern sich durch Zuschneiden nicht. Verdeckte Objekte werden weder gelöscht noch versetzt; ein späteres Erweitern des Ausschnitts bringt sie wieder zum Vorschein. Unsichtbare Griffe außerhalb des Ausschnitts reagieren nicht im grauen Rand.

Eine Zuschnittvorschau ist reiner UI-Zustand. Sie erzeugt keine Revision und wird nicht automatisch gesichert. Bestätigen erzeugt genau einen gemeinsamen Dokument-Undo-Schritt für den Zuschnitt; unverändertes Bestätigen erzeugt keinen. Objekt- und Zuschnittaktionen teilen dieselbe History. Undo/Redo sichert den resultierenden Stand per Autosave. Beim Wiederöffnen ist die History wie bisher leer, der gespeicherte Ausschnitt bleibt aber veränderbar und erweiterbar.

Projektformat **2** ergänzt `crop`. Version 1 wird beim Lesen im Speicher migriert; ID, Zeitstempel, Objekte und Revision bleiben erhalten. Erst die nächste tatsächliche Änderung schreibt Version 2. Ältere Builds lehnen diese Version ab, statt einen unbekannten Zuschnitt zu ignorieren und versehentlich das ganze Original auszugeben. Unbekannte zukünftige Versionen werden weiterhin nicht überschrieben. Das Paketmanifest bleibt bei Version 1. Details: [Projektformat](PROJEKTFORMAT.md).

PNG und Kopieren verwenden denselben Renderer mit demselben Zuschnitt. Dieser komponiert zunächst im Originalkoordinatensystem und schneidet anschließend die fertigen Pixel aus. So bleiben Antialiasing an Vektorkanten und die Unschärfeberechnung beim Zuschneiden unverändert. Der Canvas verwendet ebenfalls Originalkoordinaten und beschränkt die Darstellung auf das Ausgaberechteck. Native Inline-Texteingabe wird an der sichtbaren Bildkante beschnitten.

Das bearbeitbare Projekt behält Original und frühere Revision. Zuschneiden ist deshalb keine Bereinigung vertraulicher Daten im Projektpaket.

## Automatisierte Nachweise

| Prüfung | Ergebnis am 12. Oktober 2026 |
| --- | --- |
| `./scripts/build.sh` | Erfolgreich mit bestehender Apple-Development-Signierung und aktivierter Sandbox. Keine Änderung an Team, Bundle-ID oder Berechtigungen. |
| `./scripts/test.sh` | **47 Tests bestanden.** Neue Fälle für Pixelrundung, Grenzen, umgekehrtes Aufziehen, acht Griffe, Minimum, Verschieben, kombinierte Objekt-/Zuschnitt-History, Formatvalidierung, Migration und Dateiwiederherstellung. |
| `./scripts/test-canvas.sh` | Bestehende Zeichen-/Text-/Zoom-Prüfungen bestanden. Neuer Zuschnitt mit synthetischen NSEvents bei Anpassen, 100 % und 400 %: Live-Maske, acht Griffe, Verschieben, neuer Rahmen mit Option, Enter/Escape, ein Undo pro Bestätigung, Zeichnen/Resize/Text nach Zuschnitt, verdeckte Griffe, Original wiederherstellen und Wiederöffnen. |
| Zwischenablage innerhalb der Canvas-Prüfung | Tatsächlichen asynchronen `copyPNG`-Pfad auf einer privaten Test-Zwischenablage ausgeführt. PNG-Daten stimmen bytegenau mit dem PNG-Renderer desselben Ausschnitts überein; Maße geprüft. Unbestätigter Zuschnitt verändert die Zwischenablage nicht. Benutzer-Zwischenablage bleibt unberührt. |
| `./scripts/test-renderer.sh` | Bestehende Pixel-, Transparenz-, Formen-, Pfeil-, Text- und Unschärfefälle bestanden. Zuschnitt **pixelgenau** gegen denselben Bereich der vollständigen Komposition verglichen; oben-links-Orientierung, PNG/Thumbnail, 1-Pixel-Ausschnitt und ungültige Grenzen geprüft. |
| `./scripts/test-autosave.sh` | Bestehende Fälle bestanden. Zuschnittvorschau bleibt ungesichert; bestätigter Ausschnitt überlebt Debounce, neue Store-Instanz und Editor-Wiederöffnung. Originalbytes bleiben unverändert; Thumbnail, Undo/Redo und Sichern als Kopie bei konkurrierendem Stand erhalten den richtigen Zuschnitt. |

Die UI-Prüfung deckte einen Zustand auf, bei dem Zahlenfelder und Übernehmen nach dem Ziehen deaktiviert blieben. `isCanvasGestureActive` wird jetzt beobachtet; die erneute Bedienprüfung und der Canvas-Test bestätigen die Freigabe nach mouseUp.

## Bedienprüfung im laufenden Build

Synthetisches Projekt **SnagForge-Crop-Abnahme**, Original **3840 × 2160** mit Raster und vier farbigen Ecken:

1. Werkzeug gewählt und Rahmen aufgezogen; Maske, Werte und Griffe sichtbar. Rechten unteren Griff verändert, danach Rahmen innen verschoben. Zahlenfelder und Übernehmen danach aktiv.
2. Ausschnitt über Zahlenfelder auf **X 784, Y 474, Breite 2000, Höhe 1200** eingestellt und bestätigt. Header und Bildfläche zeigen 2000 × 1200. **⌘Z** stellt das Original wieder her, **⇧⌘Z** den Zuschnitt.
3. Im zugeschnittenen Bild einen Pfeil gezeichnet und direkt Text „Zuschnitt Test“ eingegeben. Beide bleiben in der erwarteten Position.
4. Zuschneiden erneut geöffnet: vollständiges Raster und ursprüngliche Ecken wieder sichtbar. Ganzes Original übernommen; alle Markierungen erhalten. Undo stellt den Ausschnitt wieder her. Eine weitere Vorschau auf ganzes Original mit Escape verworfen; bestätigter Ausschnitt bleibt erhalten.
5. Projekt gesichert, App beendet, aktuellen Xcode-Build gestartet und Projekt aus der Bibliothek geöffnet. **2000 × 1200** sowie beide bearbeitbaren Markierungen wieder vorhanden; neue Sitzung hat keine alte Undo-Historie.
6. Über den nativen Save-Dialog nach `/tmp/SnagForge-Crop-Export.png` exportiert. `sips` bestätigt **PNG, 2000 × 1200**. Sichtprüfung bestätigt Rasterausschnitt, Pfeil und Text ohne Werkzeug-/Auswahlrahmen oder die abgeschnittenen Originalecken.

## Offene übergreifende Prüfungen

- macOS 26, weitere Displays, reale Trackpad-Gesten und Mindestfenstergröße zusätzlich unter Q01/Q03 prüfen. E02 verändert die Capture-Pipeline nicht und ersetzt deren offene Hardwareabnahme nicht.
- VoiceOver und vollständige Tastaturbedienung von Canvas/Objekten/Griffen bleiben Q03. Die vier Zahlenfelder und Aktionen besitzen Accessibility-Labels; damit ist keine vollständige Accessibility-Abnahme erfolgt.
- Zuschnitt-Export und zugeschnittene Thumbnails komponieren derzeit das ganze Original im Hintergrund. Speicher-/Laufzeitgrenzen mit sehr großen Bildern und vielen Markierungen unter Q02 prüfen. Das 4K-Ergebnis ist kein Nachweis für die maximale Importgröße von 100 Millionen Pixeln.
- Auflösungsänderung folgt in **E03**. Zuschneiden resampelt das Bild nicht.

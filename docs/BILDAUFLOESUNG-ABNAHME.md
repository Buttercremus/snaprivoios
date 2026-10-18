# E03 – Bildauflösung ändern

Stand: 13. Oktober 2026. Implementiert und im regulär signierten Sandbox-Build auf macOS 27 geprüft. macOS 26 bleibt die Mindestversion; Bundle-ID und Signierung wurden nicht geändert.

## Bedienung

Oben im Editor **Bildgröße …** oder im Menü **Bearbeiten → Bildauflösung ändern …** öffnen. Breite und Höhe sind ganze Pixelmaße. Die Seitenverhältnissperre ist beim Öffnen aktiv; Änderung einer Achse berechnet die andere, auf ganze Pixel gerundet und mindestens eins. Nach Lösen der Sperre lassen sich beide Achsen unabhängig einstellen. Erneutes Sperren verwendet das aktuelle gültige Verhältnis.

**50 %** und **200 %** beziehen sich auf die beim Öffnen vorhandene Zielauflösung, nicht auf wiederholte Klicks derselben Taste. **Originalauflösung** verwendet die ursprünglichen Pixelmaße des bestätigten Ausschnitts; der Zuschnitt bleibt bestehen. Es handelt sich um Pixelmaße, nicht um Druck-DPI oder Ansichtszoom.

Übernehmen ist ein gemeinsamer Dokument-Undo-Schritt. Unveränderte Maße erzeugen keine Revision und keinen Undo-Schritt; der Button ist dafür deaktiviert. Escape/Abbrechen verwirft den Entwurf. Eingaben werden erst nach Übernehmen gespeichert. Ungültige Werte sperren Übernehmen und zeigen die zulässigen Grenzen: 1–32.768 Pixel je Achse, insgesamt höchstens 100 Millionen Pixel. Bei unbestätigtem Zuschnitt oder laufender Zeichengeste öffnet der Dialog nicht.

## Dokument, Koordinaten und Ausgabe

- `original.png`, `pixelSize`, Zuschnitt und Objektgeometrie bleiben in Originalpixeln erhalten. `resizedSize` speichert die gewählte Zielauflösung; `null` bedeutet die ursprünglichen Pixelmaße des Ausschnitts. `outputPixelSize` wird daraus abgeleitet.
- Bild, Pfeile, Formen, Callouts, Schrift, Linienmuster und Unschärfe werden gemeinsam skaliert. Ohne Seitenverhältnissperre werden auch Buchstaben und Formen entsprechend gestreckt. Das ist eine bewusste Bildskalierung, kein neues Textlayout.
- Die Stilwerte im Eigenschaftenbereich bleiben Originalpixelwerte. Beispielsweise wird eine Schrift mit 32 Originalpixeln bei 50 % mit 16 Ausgabepixeln dargestellt; sie bleibt separat bearbeitbar. Es gibt in E03 keine zweite Option „Schriftgröße beim Skalieren unverändert lassen“.
- Canvas und native TextView verwenden dieselbe zweiachsige Projektion. Klicks, Cursorpositionen, Verschieben und Griffe werden zurück in Originalkoordinaten gerechnet. Auswahlgriffe und ihre Trefferflächen behalten ihre Größe in Ansichtspunkten.
- „100 %“ im Zoom entspricht einem Ausgabepixel je Bildschirmpixel, einschließlich Retina. Die Größenänderung setzt die Ansicht auf die gespeicherte Zoomvorgabe: „Immer passend verkleinern“ (Vorgabe) oder 100 %. Zoom bleibt reiner Ansichtszustand.
- Seit 14. Oktober 2026 sampelt der PNG-/Clipboard-Renderer das Original mit Rastereffekten und nötigen Abdeckungen einmal mit hoher Interpolationsqualität auf die Zielmaße. Text, Callouts und Formen werden direkt in der Zielauflösung gerastert, damit ihre Kanten nicht durch eine zwischengespeicherte flache Komposition weicher werden. Abdeckungen werden abschließend erneut auf dem Zielpixelraster gezeichnet. Die 100-%-Ausgabe bleibt identisch zur unskalierten Komposition. Jede spätere Größenänderung verwendet erneut das Original, nie die vorherige verkleinerte PNG. Vergrößern erfindet keine zusätzlichen Bilddetails. [Aktuelle Nachweise](BILDSCHAERFE-ABNAHME.md).
- Die Bibliotheksvorschau berücksichtigt Zielmaße und Seitenverhältnis; ihre längere Kante bleibt auf 420 Pixel begrenzt. Bildverarbeitung für Export und Autosave-Vorschau läuft außerhalb des MainActor.
- Ein späterer Zuschnitt leitet aus den aktuellen Ausgangs-/Zielmaßen die X/Y-Faktoren ab, berechnet die neue Zielgröße und rundet auf ganze Pixel, mindestens eins. Zuschnitt und Zielgröße bilden einen Undo-Schritt. Bei sehr kleinen Ausschnitten ist diese Rundung unvermeidlich; es wird kein zusätzlicher Subpixel-Skalierungsfaktor gespeichert.
- Würde eine Erweiterung des Zuschnitts die Ausgabebegrenzung überschreiten, bleibt der Entwurf zur Korrektur offen. „Zuschnitt aufheben“ behält die gewählte Skalierung; „Originalauflösung“ setzt allein die Skalierung zurück.

## Speicherung und Migration

Dokumentformat **3** speichert Zuschnitt, Zielauflösung und Objekte. Format **1/2** wird im Speicher migriert; IDs, Original, Markierungen und vorhandener Zuschnitt bleiben erhalten. Erst eine echte Änderung schreibt Format 3. Ältere Builds lehnen dieses Format ab, statt eine verkehrte Bildgröße auszugeben. Unbekannte zukünftige Versionen werden weiterhin nicht überschrieben. Das Paketmanifest bleibt bei Version 1.

Autosave, vorherige Revision, Wiederherstellung und „Als Kopie sichern“ übernehmen die Zielauflösung. Originalbytes werden durch eine Größenänderung nicht ersetzt. Die Sitzungshistorie beginnt nach Neustart wie bisher leer; die gespeicherte Skalierung und alle Objekte bleiben weiter bearbeitbar.

## Automatisierte Nachweise

Erfolgreich ausgeführt:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-resize.sh
./scripts/test-canvas.sh
./scripts/test-renderer.sh
./scripts/test-autosave.sh
```

**53 Domain-Tests** erfolgreich. Neue Fälle prüfen Maße/Pixelgrenzen, gekoppelte Maße, sehr kleine Ziele, Format-1/2-Migration, Ablehnung ungültiger Daten, originale Objektkoordinaten, gemeinsame History, Crop-Skalierung, zweiachsige Projektion sowie Persistenz und Wiederherstellung aus einer vorherigen Revision.

`test-resize.sh` verwendet den tatsächlichen Produktionsrenderer, Canvas, EditorModel und ProjectStore mit synthetischen Bildern, nativen Offscreen-Ereignissen und temporärer Bibliothek:

- PNG-Abmessungen nach Zuschnitt und freier Skalierung, Orientierung, Transparenz und skalierte Pfeilpixel; 100-%-Ausgabe bleibt pixelidentisch zur bisherigen Komposition.
- Thumbnail mit Zielseitenverhältnis; übergroße Ausgaben werden abgelehnt.
- Live-Pfeil-Endpunkt bei Anpassen/100 %/400 %, unveränderter Gegenpunkt, Rücknahme ohne Verlust der Zielgröße.
- Formvorschau und Formgriff nach freier Skalierung.
- Native Wortauswahl und Text-Undo; TextView-Bounds skalieren mit denselben X/Y-Faktoren wie die Ausgabe.
- Gemeinsame Zuschnitt-/Größenhistorie, keine Dokument-Undo-Aktion hinter dem geöffneten Dialog, kein zusätzlicher Schritt bei unveränderter Größe.
- Autosave, Wiederöffnen, originale Bildbytes und Bibliotheksvorschau; PNG-Kopieren nach Wiederöffnen ist identisch zum Export. Dafür wird eine private Test-Zwischenablage verwendet; die Nutzerzwischenablage bleibt unverändert.
- Sichern als neues Projekt mit Zielauflösung und unverändertem Original. Normalisierung einer redundanten 100-%-Zielgröße hält Dokument und History synchron.

Vorhandene Canvas-/Zoom-/Zuschnitt-, Renderer- und Autosave-Prüfungen bestehen weiterhin.

## Bedienprüfung im laufenden Build

Synthetisches Projekt „SnagForge-Crop-Abnahme“ mit zwei Markierungen verwendet; keine Nutzeraufnahme bearbeitet:

1. Dialog geöffnet, Breite 2000 → 1000 eingegeben; Höhe wurde bei aktivierter Sperre 1200 → 600. Übernehmen zeigte 1000 × 600 Pixel im Editor.
2. ⌘Z stellte 2000 × 1200 wieder her; ⇧⌘Z wiederholte die Skalierung.
3. Über den nativen Speicherdialog nach `/private/tmp/SnagForge-E03-Abnahme-1000x600.png` exportiert. PNG-Header unabhängig gelesen: **1000 × 600 Pixel**, 29.828 Bytes.
4. Projekt gesichert, App beendet/erneut gestartet und aus Bibliothek geöffnet: Zielgröße 1000 × 600 und beide Markierungen erhalten.
5. Ungültige Breite 0 zeigte die Fehlermeldung und hielt Übernehmen gesperrt. Seitenverhältnis gelöst, Höhe 300 eingegeben und freie 1000 × 300 übernommen; Vorschau skalierte Bild und Markierungen gemeinsam. Mit ⌘Z zurückgenommen.
6. Originalauflösung bestätigte 2000 × 1200; Prüfprojekt damit wieder auf Ausgangsgröße gesichert. Anschließend 50-%-Entwurf mit Escape verworfen, Zielgröße blieb unverändert. Bibliothek blieb bei 24 Projekten; vorhandene Werkzeuggrößenvorgabe blieb erhalten.

## Verbleibende Releasefälle

macOS 26, weitere Retina-/Mehrdisplay-Konfigurationen, VoiceOver und vollständige Tastaturnavigation nach Q01/Q03. Große Originale nahe der 100-Millionen-Pixel-Grenze können beim Komponieren und Resampling viel RAM benötigen; Last-/Speicherfehlerprüfungen nach Q02 bleiben offen. HDR/Wide-Gamut-Ausgabe, DPI-Metadaten, wählbare Resampling-Verfahren und getrennte Skalierungsregeln für Markierungen gehören nicht zu E03.

E03 ist damit implementiert und mit den genannten Nachweisen abgeschlossen. Nächster Schritt im [Arbeitsplan](ARBEITSPLAN.md): **E04 Duplizieren und Ebenenreihenfolge**.

# Automatisch wachsende Zeichenfläche

Stand: 19. Oktober 2026.

## Verhalten

- Geometrische Canvas-Gesten zum Zeichnen, Verschieben oder Bearbeiten von Griffen können die sichtbare Bildfläche überschreiten. Der Überstand erscheint bereits während des Ziehens.
- Während der Geste bleiben Dokumentgröße, Zoom und Projektion unverändert. Erst beim Loslassen werden die Objektänderung und die benötigte Zeichenfläche als ein gemeinsamer Historienzustand übernommen.
- Die Erweiterung umfasst sichtbare Konturen einschließlich ihrer Stärke, Formpfade und Pfeilspitzen. Die Kanten werden nach außen auf ganze Quellpixel gerundet.
- Original und Objektkoordinaten bleiben unverändert. Links und oben sind negative Quellkoordinaten möglich. Neue Fläche außerhalb des Originals ist transparent; das Schachbrett im Editor gehört nur zur Ansicht.
- Löschen oder Verkleinern eines Objekts schrumpft die Zeichenfläche nicht. Undo stellt Objekt und Fläche gemeinsam wieder her; Redo übernimmt beide erneut. Escape verwirft die laufende Geste vollständig.
- Ein vorhandener Zuschnitt wird nur so weit geöffnet, wie die bearbeitete Geometrie es benötigt. Dadurch können bisher ausgeblendete Originalpixel und Markierungen wieder sichtbar werden. Erweiterungen über das Original hinaus bleiben transparent.
- Bereits eingestellte X-/Y-Ausgabeskalierungen bleiben erhalten. Die bisherige Zoomstufe bleibt bei der Geste erhalten; die vergrößerte Bildfläche wird danach mit der bestehenden Ansichtslogik dargestellt.
- Reine Stiländerungen und native Texteingabe lösen keine zusätzliche automatische Erweiterung aus. Die Erweiterung ist an abgeschlossene geometrische Canvas-Gesten gebunden.

## Speicherung und Ausgabe

Projektformat 11 ergänzt ein optionales `canvasRect`. Ohne dieses Feld verhält sich ein Dokument unverändert wie bisher. Formate 1–10 werden ohne Änderung der Originalpixel oder Markierungen migriert; ältere Builds lehnen Format 11 ab.

Die Zeichenfläche gehört zur gemeinsamen Historie mit Objekten, Zuschnitt und Ausgabeauflösung. Autosave, Wiederöffnen, Projektkopien, portable Archive und Bibliothekssicherung behalten sie. Zuschnitt und OCR-Auswahl unterstützen die negative Quelllage. „Ganzes Original“ im Zuschnitt stellt die vollständige Zeichenfläche einschließlich transparentem Rand wieder her.

PNG-Export, Zwischenablage, Teilen, externer PNG-Aufruf, Vorschaubild, Anheften, Bildausgabe, Pipette und Anleitungsübernahme berücksichtigen dieselbe Zeichenfläche. Bei Skalierung werden Original, Unschärfe und Abdeckungen vor dem Sampling zusammengesetzt; Vektor- und Textmarkierungen werden in der Zielauflösung gezeichnet. Die Schachbrettansicht wird nicht exportiert.

Weiterhin gelten höchstens 32.768 Pixel je Kante und 100 Millionen Pixel sowohl für Zeichenfläche als auch Ausgabe. Eine Überschreitung verwirft die gesamte Objektgeste und zeigt einen lokalisierten Hinweis; es entsteht kein teilweiser Undo-/Speicherzustand.

## Prüfnachweise

- `./scripts/test.sh`: 134 Domain-Tests, darunter sechs neue Prüfungen für Außenrundung, Grenzen, gemeinsame Historie, Formatvalidierung/Migration/Kopien, negative Crop-/OCR-Koordinaten und Speicherung mit unverändertem Original.
- `./scripts/test-canvas.sh`: bestehende Canvas-, Zoom-, Crop-, Griff- und Werkzeugprüfungen sowie neue native Gesten in alle vier Richtungen. Gemessen werden sichtbare Überstände vor Mouse-up, stabile Projektion, Verschieben, Griffbearbeitung mit vollständig sichtbaren Randgriffen, Escape, ein gemeinsamer Undo-Schritt, Redo, Wiederöffnen, Größenlimits und Erhalt freier Ausgabeskalierung.
- Pixelvergleich des unveränderten Originalbereichs einschließlich einzelner Pixelstreifen mit erweitertem PNG; Alpha 0 im neuen Rand, sichtbare Markierung außerhalb des Originals, Crop/Resize/Thumbnail, identische PNGs beim Teilen und Kopieren sowie portable Projektvalidierung.
- Regulärer App-Build und englische/deutsche Katalog-/Compiler-Abdeckung. Die persönliche Bedienung der Produktions-App ersetzt diese synthetischen Nachweise nicht.

Die native Sichtprüfung in einem isolierten Testfenster mit synthetischen Formen bestätigt rechts und links überstehende Rechtecke sowie die anschließend sichtbaren transparenten Randflächen. Die zusätzliche Randgriffdarstellung wird durch die Canvas-Pixelprüfung bestätigt.

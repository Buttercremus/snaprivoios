# Biegbare Pfeile, Lupe, Handstile und Live-Callouts

Stand: 20. Oktober 2026 · implementiert, persönliche Bedienabnahme offen.

## Bedienung

- Pfeil auswählen, mittleren runden Griff ziehen: Der Schaft biegt sich live, beide Enden bleiben fest. Endpunkte und Schaft behalten ihre bisherigen Aufgaben. Eigenschaften und Schnelloptionen bieten zusätzlich den tastaturbedienbaren Regler **Biegung** und **Pfeil begradigen**. Escape verwirft eine laufende Geste; Loslassen ergibt einen Undo-Schritt. Biegungen bewegen sich beim Verschieben, Duplizieren und Tastaturschieben mit.
- **Lupe** in der Werkzeugleiste wählen und einen Kreis aufziehen. Der Standardfaktor ist 200 %, einstellbar sind 150–500 %. Randfarbe und Linienbreite sind änderbar. Griffe skalieren den Kreis; Verschieben ändert den betrachteten Bildbereich. Die Quelle ist das ursprüngliche Bildrechteck samt flach gerenderten Markierungen, Filtern und deckenden Abdeckungen. Andere Lupen werden ausgelassen, damit keine rekursive Vergrößerung entsteht. Inhalte auf transparenter Zeichenflächenerweiterung außerhalb dieses Quellrechtecks werden nicht zusätzlich vergrößert.
- Unter **Zeichenstil** stehen Präzise, Handgezeichnet, Skizze und Marker für Pfeile und geometrische Formen bereit. Skizze zeichnet zwei dünne Stiftkonturen; Marker verwendet eine breitere Filzstiftkontur. Abgerundete Rechtecke behalten den Radius. Die Kurven verwenden keine Zufallswerte.
- **Callout** aufziehen: Der vollständige leere Rahmen samt Zeiger erscheint sofort und wächst während des Ziehens. Auch Ziehen nach links/oben funktioniert. Nach Loslassen erhält die Texteingabe den Fokus. Leer bestätigte Callouts bleiben sichtbar. Während des Aufziehens verwirft Escape den Entwurf. Der gezeichnete Rahmen ist eine Mindestgröße; längerer Text darf weiter wachsen. Ein Klick erzeugt einen sofort sichtbaren Rahmen mit Vorgabegröße.

Lupe und Handstile verwenden die bestehende Pro-Grenze für erweitertes Bearbeiten. Pfeilbiegung bleibt in der Basis nutzbar. Lesen und Ausgeben vorhandener Pro-Objekte bleiben unabhängig von der Freischaltung möglich.

## Speicherung und Ausgabe

Format 12 ergänzt den optionalen Schaftmittelpunkt `arrowBend`, den Typ `magnifier`, dessen optionalen Faktor `magnification` und die Stilwerte `sketch`/`marker`. Formate 1–11 bleiben lesbar; insbesondere bleibt `canvasRect` aus Format 11 bei der Migration erhalten. Ungültige Typ-/Feldkombinationen und nicht endliche Koordinaten werden abgelehnt. Die vorhandenen Callout-Felder `textWidth`/`textHeight` speichern die gezogene Größe. Eigene Stilvorlagen erhalten den Lupenfaktor und die Zeichenstile, keine Quellkoordinaten.

Vorschau und Bildausgaben teilen sich die Geometrie. Die Lupenquelle wird im Canvas außerhalb des MainActor vorbereitet und nur bei Änderungen an der Quellkomposition erneuert. Eine veraltete Quelle wird ausgeblendet, bis der aktuelle Stand bereitsteht. Reines Verschieben oder Skalieren einer Lupe braucht keine neue Quellrasterung. PNG, Zwischenablage und weitere Bildausgaben verwenden den gemeinsamen Renderer; Abdeckungen werden vor der Vergrößerung eingerechnet und weiterhin zuletzt auf die Ausgabe gezeichnet.

## Nachweise

- `./scripts/build.sh -derivedDataPath "$PWD/build/AnnotationBuild"`: macOS-App inklusive Sandbox und Swift 6 gebaut.
- `./scripts/test.sh`: 143 Domain-Tests erfolgreich, einschließlich Biegegeometrie, Translation, Duplikation, Historie, Speicherung, strenger Validierung, alten Stilen und Format-11-Zeichenfläche.
- `./scripts/test-canvas.sh --annotation-tools-only`: synthetische native Mausgesten in allen vier Pfeilstilen, Zoom und ungleichmäßiger Ausgabeskalierung; feste Endpunkte, Begradigen, Escape und Undo/Redo. Live-Callouts ohne Text, beide Ziehrichtungen, Fokus, leere Bestätigung und Abbruch. Lupenerstellung, runder Resize, Faktoränderung, Autosave und erneutes Laden. Pixelprüfungen für vergrößerte Bilddetails, Abdeckungen, Crop/Resize und unterscheidbare Stil-Ausgaben. Synthetische Übersicht: `build/CanvasTests/AnnotationStyles.png`.
- `./scripts/test-hand-drawn.sh`: bisheriger Handstil, gespeicherte Vorlagen, Undo, Autosave und identischer Export nach Wiederöffnen erfolgreich.
- `python3 scripts/check-localization.py "$PWD/build/AnnotationBuild"` sowie `./scripts/test-localization.sh "$PWD/build/AnnotationBuild/Build/Products/Debug/Snaprivo.app"`: vollständige Compiler-Abdeckung und native deutsche/englische Beschriftungen inklusive Lupe, Biegung, Vergrößerung und Skizze erfolgreich.
- `./scripts/test-canvas.sh`: vollständige Suite am 20.10.2026 erfolgreich, einschließlich `SelectionGripChecks`, Zeichenflächenerweiterung, Konturtreffern und Tastaturbearbeitung. Der reproduzierte Griff-Testfehler ist behoben: Die synthetische Form bleibt bei unveränderten Zoomstufen (50/100/400 %) und beiden Ausgabe-Seitenverhältnissen vollständig im Testfenster. Alle acht Form- und Crop-Griffe werden weiter auf Pixelgröße, Form, vergrößerte Trefferfläche und Undo geprüft. Pixelabfragen berücksichtigen die Bitmap-Grenzen; eine eigene Vorbedingung meldet einen außerhalb liegenden Griff verständlich. Keine Produktionsgeometrie wurde dafür geändert.

Die native Prüfung verwendet ausschließlich synthetische Daten und direkte Ereignisse an eigene Testfenster. Persönliche Bedienprüfung mit physischer Maus/Trackpad, VoiceOver und macOS 26 steht noch aus. Ein Build ersetzt diese Abnahme nicht.

### Callout-Spitze beim Aufziehen (20. Oktober 2026)

Neue Callouts speichern den Mausdruckpunkt als feste Spitze. Die Blase wächst mit 24 Bildpixeln Abstand entlang der Ziehrichtung; der Canvas behält während der Geste den Fokus. Erst beim Loslassen entsteht die native Texteingabe. Bestehende Objekte bleiben unverändert. Die erweiterte native Prüfung kontrolliert alle vier diagonalen Ziehrichtungen, eine Spitze außerhalb der Blase, die live sichtbare leere Blase, Fokuswechsel erst beim Loslassen, Undo/Redo und Abbruch. App-Build und vollständige Canvas-Suite einschließlich Lupe (Aufziehen, Größe, Zoom, Wiederöffnen und Export) bestanden. Das tatsächliche Bediengefühl im Hauptfenster bleibt manuell zu beurteilen.

### Versetzte Lupe mit Quellkreis (20. Oktober 2026)

Nach Nutzerreferenz: Mausdruck setzt die Quelle, Ziehen platziert die große runde Vergrößerung am Mauszeiger. Der Radius wächst mit dem Abstand (24–160 Bildpixel). Ein kleiner Kreis zeigt den abgebildeten Quellbereich, eine Linie verbindet beide Kreise bei ausreichendem Abstand. Ziehen des großen Kreises verschiebt nur die Anzeige, Ziehen des kleinen Kreises nur die Quelle. Die vorhandenen Griffe ändern die Größe, der Vergrößerungsregler den Zoom. Gruppenbewegungen und Duplikate verschieben beide Teile gemeinsam. Vorhandene Lupen ohne explizite Quelle bleiben unverändert. Export nutzt dieselbe Geometrie und berücksichtigt deckende Abdeckungen auch in der vergrößerten Quelle.

Projektformat 14 speichert den optionalen Quellmittelpunkt und liest Formate 1–13. Der Mittelpunkt wird auf endliche, begrenzte Koordinaten geprüft.

Nachweise für die versetzte Lupe: App-Build, gesamte native Canvas-Suite, 149 Swift-Testing-Domainprüfungen plus zwei XCTest-Prüfungen sowie Lokalisierungskatalog-/Compilerprüfung bestanden. Native Lupentests prüfen getrenntes Verschieben beider Kreise, Undo/Redo und Wiederöffnen. Pixeltests prüfen die versetzte Vergrößerung und die deckende Übernahme einer maskierten Quelle. Eine manuelle visuelle Abnahme der neuen Darstellung im Hauptfenster steht noch aus.

### Beide Lupenarten verfügbar

Der Inspector bietet „Lupenart“ als segmentierte Auswahl Normal/Versetzt. Normal ist der Anfangswert und zeichnet wieder einen Kreis direkt über dem Bilddetail. Die Auswahl gilt für folgende Gesten und stellt ausgewählte Lupen um. Bei Normal → Versetzt bleibt der Quellmittelpunkt erhalten und die Anzeige wandert einen Durchmesser nach rechts. Zurück zu Normal liegt die Anzeige wieder über ihrer Quelle. Zoom, Farbe und Rand bleiben erhalten. Native Regression prüft normales Aufziehen, beide Umschaltrichtungen, Undo/Redo und danach die versetzte Bedienung. App-Build, vollständige Canvas-Suite und deutsche/englische Katalog-/Compilerprüfung (1070 App-Texte) bestanden.

### Lupen-Umschaltung am Bildrand – 21. Oktober 2026

Die Umschaltung Normal/Versetzt erweitert jetzt bei Bedarf die Zeichenfläche über den bestehenden begrenzten Commit-Pfad. Rahmen, Quellkreis, Zuschnitt und vorhandene Ausgabeskalierung werden berücksichtigt. Undo/Redo stellt Geometrie und Ausgabeabmessungen gemeinsam wieder her. Die neue native Regression setzt eine Lupe nahe an den rechten Rand und prüft die vollständige sichtbare Kontur, Undo/Redo, Autosave/Wiederöffnen sowie tatsächliche PNG-Pixel am rechten Lupenrahmen – sowohl ohne Zuschnitt als auch mit Zuschnitt und freier Skalierung. Die vorhandene Kreisgrößenprüfung verwendet nun eine Toleranz von 0,000001 Bildpixeln statt exakter Gleitkommagleichheit. App-Build und vollständige Canvas-Suite bestanden. Der im Release-Bericht vom 20. Oktober aufgeführte Randfehler ist damit behoben.

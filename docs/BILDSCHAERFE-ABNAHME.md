# Bildschärfe und automatische Ansicht

Stand: 14. Oktober 2026. Automatisierte Prüfungen mit synthetischen Bildern auf macOS 27; macOS 26 bleibt das Deployment Target.

## Änderungen

- Das Zoommenü bietet **Immer passend verkleinern**, standardmäßig aktiv und über App-Neustarts gespeichert. Aktiv: ganze Bilder passend anzeigen, höchstens mit einem Bildpixel pro Bildschirm-Pixel. Inaktiv: neue/geöffnete Bilder bei pixelgenauen 100 %. Umschalten wirkt unmittelbar; manuelle Zoomstufen bleiben für das aktuelle Bild möglich. Bestätigter Zuschnitt, Bildgrößenänderung und deren Undo/Redo folgen der Vorgabe. Der Zuschnittentwurf startet für die Übersicht weiterhin mit Anpassen. Die Option verändert weder Dokumentrevision noch Undo, Autosave oder Exportpixel.
- Sobald ein Unschärfebereich vorhanden war, verwendete der Canvas bisher eine höchstens 2048 Pixel große Komposition als Hintergrund für das gesamte Bild. Diese Zwischenkopie konnte auch unberührte Screenshot-Schrift weichzeichnen. Die asynchrone Filterkomposition bleibt jetzt in Originalauflösung; weiterhin höchstens ein Filterauftrag gleichzeitig außerhalb des MainActor.
- Beim Größenexport wurde bisher die vollständige Komposition einschließlich Text und Formen zuerst in Originalauflösung gerastert und anschließend skaliert. Jetzt werden Rasterbild und Filter einmal auf die Zielmaße abgetastet; Text, Callouts, Formen und weitere Vektorobjekte entstehen direkt in den Ausgabepixeln. Originalkoordinaten, Schriftmetriken und Umbruch bleiben gleich. Abdeckungen wirken vor der Abtastung gegen Pixelreste und abschließend auf dem Zielpixelraster. Eine Ausgabe mit unveränderten Maßen verwendet weiterhin die bisherige pixelidentische Komposition.
- Der Capture-Adapter fordert bereits `.best` und `contentRect × pointPixelScale` an und schneidet den bestätigten Bereich aus den eingefrorenen Displaypixeln aus. Dieser Aufnahmeweg wurde für diese Änderung nicht verändert.

## Nachweise

Alle folgenden Befehle erfolgreich mit dem nötigen lokalen Xcode-/Bildfilterzugriff ausgeführt. Die eingeschränkte Agent-Ausführungs-Sandbox konnte Swift-Makros/SwiftPM und Core-Image-Filter nicht vollständig ausführen; dies war kein Fehler der App-Sandbox.

```sh
./scripts/test.sh
./scripts/test-renderer.sh
./scripts/test-resize.sh
./scripts/test-canvas.sh
./scripts/test-settings.sh
./scripts/test-transfer-privacy.sh
./scripts/build.sh -derivedDataPath "$PWD/build/SharpnessBuild"
```

- **88 Domain-Tests bestanden**, einschließlich initialer 100-%-Projektion vor dem ersten View-Layout und Backing 1/2.
- Native Offscreen-Canvas: 4097 × 513-Pixel-Bild mit Ein-Pixel-Streifen und tatsächlich abgeschlossener Hintergrund-Unschärfe. Außerhalb der Filterregion bleiben schwarze/weiße Pixel in Vorschau und PNG exakt erhalten. Bestehende kleine Bild-, Fit-/100-/200-%-, Zeichen-, Griff-, Text-, Zuschnitt- und Exportprüfungen bestehen weiter.
- Zoomvorgabe: Standard ein, gespeichertes Aus nach Neustart, Übergabe an neue Workspace-Editoren und erneutes Ein. Manuelles Zoomen bleibt möglich; Umschalten erzeugt keine Dokumentrevision oder Undo-Aktion und ist während einer Canvas-Geste gesperrt.
- Größenexport: synthetische Schriftstämme und scharfe Vektorkanten bei 200 % mit/ohne Zuschnitt, unveränderte Identitätsausgabe, Orientierung, Alpha, freies Seitenverhältnis, Textauswahl, Undo, Autosave, Wiederöffnen und PNG-/Clipboard-Gleichheit.
- Übergabe/Datenschutz: bestehende deckende Pixel nach Zuschnitt/Resize, PNG, Zwischenablage, Teilen und Öffnen-mit-Snapshots erfolgreich. Tests verwenden private Zwischenablagen; keine Ziel-App geöffnet und kein Versand ausgelöst.
- Regulär signierter Debug-Build erfolgreich; App Sandbox bleibt aktiv. Buildlog: `build/sharpness-build.log`.

## Grenzen und reale Abnahme

Eine verkleinerte oder gebrochen skalierte Vorschau muss Pixel zusammenfassen. Sie kann weicher wirken als die Datei bei 100 %. Eine tatsächliche Verkleinerung des Rasterbildes verliert Details; Vergrößern kann unscharfe Quellschrift nicht rekonstruieren. Zusätzliche Skalierung/Kompression in Ziel-Apps ist durch den PNG-Export nicht kontrollierbar. Automatisches Nachschärfen wird nicht angewandt.

Der visuelle Vergleich mit Snagit an identischem Bildschirmzustand, Ausschnitt, Pixelmaßen und 100-%-Darstellung steht aus. Ebenso bleiben macOS 26, reale Displaywechsel und subjektive Prüfung der Nutzeraufnahmen offen. Diese Änderungen sind keine pauschale Zusage, dass jede Quelle und jede Zielgröße gleich scharf aussieht.

Die nun volle Filterkomposition benötigt bei großen Originalen mehr Speicher als die bisherige 2048-Pixel-Vorschau. Verarbeitung bleibt asynchron und seriell; Last-/Speicherprüfungen nahe der Dokumentgrenze bleiben Teil von Q02.

API-Referenzen: [ScreenCaptureKit-Auflösungen](https://developer.apple.com/documentation/screencapturekit/sccaptureresolutiontype), [Core-Graphics-Interpolation](https://developer.apple.com/documentation/coregraphics/cgcontext/interpolationquality).

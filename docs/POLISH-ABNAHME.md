# Ansichtswechsel und Bibliotheks-Polish

Stand: 20. Oktober 2026. Umsetzung der vom Nutzer bestätigten Polish-Vorschläge.

## Verhalten

- **Seitenleiste und Bilder/Videos:** 120 ms Überblendung mit `timingCurve(0.23, 1, 0.32, 1)`, ausgelöst durch die Maus. Fenster, Seitenleiste und Hauptwerkzeugleiste bleiben stehen. Eigene Transaktionsmarker begrenzen die Animation auf den Übergang; darunterliegende Canvas-/Medienlayouts erhalten keine Navigationsanimation. Interne Animationen wie das Sortieren von Anleitungsschritten bleiben unabhängig davon verfügbar.
- **Bilder auswählen:** Die Aktionszeile hat einen dauerhaft reservierten Platz von 26 pt. Beim Aktivieren per Maus blendet sie über 160 ms mit derselben Kurve und 4 pt Bewegung ein. Beim Verlassen läuft der Weg rückwärts. Das Bilderraster wird dabei nicht verschoben. Unsichtbare Aktionen nehmen weder Maus- noch Accessibility-Eingaben an. Nachtrag 29.10.2026: Die Auswahlaktionen ersetzen jetzt die Bildanzahl in der Kopfzeile; der reservierte Streifen und seine Einblendung entfallen, das Raster bleibt weiterhin unverschoben.
- **Anleitungsschritte:** Die Auf-/Ab-Buttons ändern die Reihenfolge mit einer gedämpften Feder (`response: 0.24`, `dampingFraction: 1`). Stabile Schritt-IDs erhalten den Zusammenhang zwischen Inhalt und Position. Die bestehende Persistenz bleibt unverändert.
- **Vorschaubild-X:** Der Hover-Zustand blendet nur das Schließen-Symbol über 100 ms ein/aus. Tastaturfokus bleibt unmittelbar sichtbar; die Bildpixel werden nicht animiert.
- **Bewegung reduzieren:** Navigation und Auswahl verwenden 80 ms Deckkraftübergang ohne Positionsbewegung. Schritte wechseln ihre Position unmittelbar. Das Hover-X verwendet ebenfalls 80 ms. Die Einstellung wird über das öffentliche SwiftUI-Environment gelesen; Systempräferenzen werden nicht verändert.
- **Direkte Bedienung:** Tastaturaktionen bekommen keine neue Verzögerung. Zeichnen, Verschieben, Zoom, Bildwechsel per Kürzel und Videoscrubbing erhalten keine zusätzliche Animation. Native Sheets/Popovers behalten ihre Systemübergänge.

## Bibliothekssuche

Die Suche startet sofort. Während einer neuen Anfrage bleibt die letzte abgeschlossene Treffermenge sichtbar; die ScrollView wird nicht mehr bei jeder Änderung der Treffer-IDs neu erstellt. Erst nach 200 ms erscheint bei weiterhin laufender Suche eine kleine, nicht blockierende Fortschrittsanzeige über dem Raster. Schnelle Suchen zeigen keinen Spinner.

Alte OCR-Treffer werden nur bei unveränderten Projekt-IDs/Revisionen, OCR-Einstellung, Papierkorbkontext und Pro-Status weiter angezeigt. Bei einer Änderung dieser Grenzen wird unmittelbar anhand der aktuellen erlaubten Metadaten gefiltert. Abgebrochene Suchaufträge dürfen weiterhin keine neueren Ergebnisse ersetzen. Ein leerer Trefferzustand erscheint erst nach Abschluss der Suche. Die Beibehaltung der Scrollposition betrifft das vorhandene Raster; nach einer leeren oder deutlich verkleinerten Treffermenge kann macOS die Position an die neue Inhaltsgröße anpassen.

## Prüfung

- `./scripts/build.sh`: erfolgreicher signierter Debug-Build mit dem aktuellen SDK. Keine Swift-Compilerwarnungen; bekannter Hinweis zu übersprungenen AppIntents-Metadaten.
- `./scripts/test.sh`: alle 140 Domain-Tests erfolgreich.
- `./scripts/test-library.sh`: Bibliotheks-/Metadaten-/Autosave-/Bildwechselprüfungen sowie echte Vision-Erkennung synthetischer Bilder bestanden; einschließlich Cacheentfernung, veralteter Erkennung nach Abdeckungen und verspäteter Jobs.
- `./scripts/test-guides.sh`: Reihenfolge, Autosave, Prozessneustart, PDF/Markdown und Sicherungs-/Importfälle bestanden.
- Isolierte Produktionsoberfläche `SnaprivoWorkflowUI.app --pro --polish` mit 30 synthetischen Bildern tatsächlich bedient: Auswahl ein/aus ohne Bewegung des Rasters; Suche und leerer Trefferzustand; Bilder/Videos und Seitenleistenwechsel; drei Screenshots in eine Anleitung übernommen und ersten Schritt nach unten bewegt; Bildwechsel per Vorschauleiste und `⌥⌘→` erfolgreich.
- Die Bibliotheks-Scrollposition lag vor und nach der Suche nach „image“ unverändert bei etwa 0,227. Die Anleitung wechselte von „Synthetic image 30, 29, 28“ zu „29, 30, 28“ und wurde automatisch gesichert.
- `git diff --check`: ohne Befund.

Die Prüf-App verwendet eigene temporäre Daten und einen synthetischen Pro-Client. Ihr Buildskript erzeugt jetzt selbst das passende Domain-Modul, statt ein möglicherweise veraltetes Modul eines früheren Testlaufs zu verwenden. Die laufende Nutzer-App wurde nicht beendet. Keine Instruments-/Bildratenmessung und keine vollständige neue VoiceOver- oder System-Reduced-Motion-Bedienabnahme in diesem Auftrag.

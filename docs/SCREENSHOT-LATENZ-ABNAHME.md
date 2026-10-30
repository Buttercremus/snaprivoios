# Screenshot-Latenz – ergänzt am 28. Oktober 2026

## Ablauf und Änderung

Der relevante Weg ist: globales/lokales Kürzel → Berechtigungsprüfung/Vorlauf → eigene Fenster ausblenden → ScreenCaptureKit-Quellen ermitteln → Displays einfrieren → Auswahl/Foto oder Enter → Ausschnitt → PNG und Vorschau erzeugen → Projekt speichern und bisherigen Editor abschließen → neuen Editor bereitstellen.

- Die Quellenermittlung beginnt während der Fensterausblendung. Seit 28. Oktober entfällt die zusätzliche Schutzzeit bis 180 ms, wenn ScreenCaptureKit unsere Anwendung in der Quellenliste führt: Der bestehende Filter schließt dann ihre Fenster aus. Fehlt die Anwendung dort und wurden eigene Fenster ausgeblendet, bleibt die bisherige Schutzfrist ab dem Ausblenden erhalten. Ohne ausgeblendete Fenster gibt es diese Wartezeit nicht. Quellen und Pixel werden weiterhin für jede Aufnahme neu ermittelt.
- Ein bestätigtes Foto schließt die Auswahl sofort. Bisher begann die Verarbeitung erst nach der Ausblendanimation (normal 160 ms, bei reduzierter Bewegung 100 ms). Abbrechen behält die bisherige Animation; Scroll-/Video-Overlays behalten ihren bisherigen Übergabeweg.
- PNG/Vorschau und das Abschließen des bisherigen Editors laufen gleichzeitig. Das neue Projekt muss erfolgreich gespeichert sein und der bisherige Editor seine Arbeit abgeschlossen haben, bevor er ersetzt wird. Scheitert dessen Sicherung, bleibt die neue Aufnahme in der Bibliothek und der bisherige Editor sichtbar. Ein laufender Export behält seinen Eigentümer.
- Ein neues Bild wird mit seinem gespeicherten Dokument und Thumbnail in die vorhandene Bibliotheksliste übernommen. Es wartet nicht mehr auf eine erneute vollständige Suche durch Bilder, Papierkorb und Videos. Eine noch nicht geladene Bibliothek wird weiterhin im Hintergrund eingelesen. Gleichzeitige Scans übernehmen den neu gespeicherten Eintrag über denselben Abgleich wie Autosaves.

## Synthetischer Vergleich

Apple M1 Pro, 32 GB, macOS 27.0 (26A428), Swift-6-Prüfprogramm ohne Optimierungsflag. 3840 × 2160 synthetische Pixel und 500 vorhandene Projekte. Je Fall ein Aufwärmdurchlauf, danach zwölf Aufnahmen; eigener temporärer Ordner und eigene Einstellungen. Kein Zugriff auf Nutzerbibliothek oder Desktopbilder.

```sh
./scripts/test-library.sh --opening-benchmark
```

Gemessen wird vom Aufruf `WorkspaceModel.openScreenshot` bis zum Austausch des Editor-Modells sowie bis zum Freigeben des nächsten Aufnahmeauftrags (`isLoading == false`). Das ist keine Messung des ersten gezeichneten Frames.

| Zustand des bisherigen Editors | Modell vorher, Median / Maximum | Modell danach, Median / Maximum | Nächste Aufnahme vorher, Median / Maximum | Nächste Aufnahme danach, Median / Maximum |
| --- | --- | --- | --- | --- |
| unverändert | 63 / 70 ms | 66 / 88 ms | 166 / 175 ms | 67 / 88 ms |
| 30 ungesicherte Pfeile | 67 / 68 ms | 68 / 119 ms | 177 / 182 ms | 68 / 119 ms |

Das Bereitstellen des Editor-Modells bleibt in dieser kleinen Stichprobe ungefähr gleich schnell. Die Bibliotheksaktualisierung blockiert die nächste Aufnahme nicht mehr: ihr Median sinkt um rund 100–110 ms. Zusätzlich fällt die vorgeschaltete Ausblendpause weg, die dieser Modellbenchmark nicht enthält. Die seltenen höheren Einzelwerte werden nicht als belastbare Perzentile interpretiert.

Die Ausgangs- und Vergleichsausgaben liegen lokal in `build/screenshot-opening-before.log` und `build/screenshot-opening-after-quiet.log`; sie enthalten ausschließlich Zeitwerte und technische Compilerhinweise. Ein weiterer Vergleich während laufender Builds lag bei 65–68 ms bis zur erneuten Aufnahmebereitschaft.

## Prüfungen

- `./scripts/build.sh -derivedDataPath "$PWD/build/ScreenshotLatencyDerivedData" CODE_SIGNING_ALLOWED=NO`: erfolgreich, App-Sandbox-Konfiguration unverändert. Kein Store-/Signierungsnachweis.
- `./scripts/test.sh`: 140 Domain-Tests erfolgreich.
- `./scripts/test-capture.sh`: bestehende Auswahl-/Koordinatenprüfungen plus sofortiges Schließen aller synthetischen Desktop-Panels nach Bestätigung und Schutz vor doppelter Fortsetzung.
- `./scripts/test-library.sh`: initiale Erkennung vorhandener Projekte, ausstehende Texteingabe, gespeichertes Original/Thumbnail, keine erneute Prüfung absichtlich beschädigter fremder Projekte bei Aufnahme/Bildimport, Schnellvorschau, gleichzeitiger Scan und fehlgeschlagenes Anlegen ohne Veröffentlichung eines ungespeicherten Eintrags. Vorhandene OCR-/Bildwechselprüfungen bestehen ebenfalls.
- `./scripts/test-settings.sh`: Aufnahmeoptionen, automatisches Kopieren und gespeicherte neue Aufnahme trotz Speicherfehler im bisherigen Editor bestehen.
- `./scripts/test-transfer-privacy.sh`: Export-/Beenden-Lebenszyklus, Fehlererhalt und PNG-Datenschutz bestehen. Zusätzlicher Screenshot-Fall: neue Aufnahme wird während eines zurückgehaltenen Exports bereits gespeichert; Editorwechsel und Beenden warten auf dessen Abschluss und erhalten die ausstehenden Markierungen.

## Verbleibende Abnahme

Keine neue Messung von echtem Shortcut bis zu sichtbarer Auswahl bzw. erstem Editorframe. Warm-/Kaltstart, ScreenCaptureKit-Initialisierung, mehrere Displays, Spaces/Stage Manager und geänderte Bildschirmfreigaben sind auf echten Desktops zu vergleichen. Die Schutzzeit wird seit dem Nachtrag vom 28. Oktober nur bei vorhandenem Anwendungsausschluss übersprungen; bei fehlender Anwendung bleibt sie erhalten. Der synthetische Paneltest belegt den Abschlussweg, keine vollständige Capture-Abnahme. Zwölf Warmdurchläufe begründen keine p95/p99-Aussage.


## Erster Auswahlrahmen – 28. Oktober 2026

Die Startstrecke enthielt zusätzlich zur eigentlichen macOS-Abfrage eine Schutzfrist bis 180 ms nach dem Verbergen eigener Fenster, danach eine 160-ms-Einblendung des gesamten Chromes sowie eine beginnende Hover-Transition. Die zusätzliche Schutzfrist wird jetzt bei identifizierter eigener Anwendung übersprungen. Der ohnehin vorhandene `SCContentFilter(display:excludingApplications:exceptingWindows:)` in `ScreenshotService.freeze` schließt dieselbe Prozess-ID aus. Apples [Dokumentation des Anwendungsfilters](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init%28display%3Aexcludingapplications%3Aexceptingwindows%3A%29) bestätigt den Fensterausschluss. Daraus folgt hier die Entscheidung, für diesen abgesicherten Fall nicht zusätzlich das Ausblenden abzuwarten. Fehlt der eigene Eintrag, bleibt die Schutzfrist unverändert.

Vor dem ersten Anzeigen werden Chrome-Deckkraft und Hover-Geometrie unmittelbar auf den Endzustand gesetzt. Desktop und Rahmen werden im selben Display-Durchlauf sichtbar; es gibt keinen anschließenden Einblendaufruf. Die vorhandene Animation beim späteren Wechsel zwischen Fenstern und beim Abbrechen bleibt erhalten.

Prüfungen: App-Build, `scripts/test-capture.sh` und 173 Swift-Testing- plus zwei XCTest-Domainprüfungen bestanden. Die native Auswahlprüfung startet den echten Selektor mit synthetischem Desktop und synthetischen Fensterkandidaten. Sobald die Panels angezeigt sind, müssen Geometrie und Sichtbarkeit des Rahmens bereits endgültig sein; ein gerasterter Randpixel weist das gezeichnete Chrome nach. Die vorhandenen Prüfungen für unveränderte Desktoppixel, Retina-/Negativkoordinaten, Ausschluss fremder/offscreen Fenster, Cursor/Fokus, sofortige Bestätigung und Abbruch bleiben enthalten. Lokale Protokolle: `build/CaptureStartupWork/`.

Die Tests erfassen keine echte ScreenCaptureKit-Kaltstartdauer und keine Gesamtzeit vom Nutzerklick bis zum ersten komponierten Bildschirmframe. Aus den entfernten konfigurierten Pausen wird deshalb weder eine garantierte Einsparung von 340 ms noch ein p50/p95/p99-Wert abgeleitet. Aktuelle Quellen, pixelgenauer Desktop, Freigabeprüfung und ein bewusst eingestellter Vorlauf bleiben Voraussetzung.

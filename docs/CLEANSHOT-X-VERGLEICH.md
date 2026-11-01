# CleanShot X als Referenz für Snaprivo

Stand: 1. November 2026. Ergänzung zum [Screen-Studio-Vergleich](SCREEN-STUDIO-VERGLEICH.md). Analyse und Empfehlungen auf Nutzerwunsch, keine Umsetzung neuer App-Funktionen. Installierte Version: CleanShot X 5.0.2.

## Was ohne Aktivierung möglich war

REA hat das installierte App-Paket, Mach-O-Metadaten, eingebettete Oberflächenarchive, Asset-Metadaten, Signaturinformationen und Erweiterungsdeklarationen statisch gelesen. Das mitgelieferte `studiomode.mp4` zeigt in drei geprüften Einzelbildern eine gestaltete Bildschirmaufnahme mit Kamera, einen vergrößerten Bildausschnitt und die Rückkehr zur Gesamtansicht. Das sind Beispiele der produzierten Videoausgabe, keine Bedienprüfung des Editors.

Die Aktivierung wurde weder verändert noch umgangen. Die gesperrten Werkzeuge wurden nicht praktisch bedient. Exakte Icon-Übergänge, Aufnahmequalität, Reaktionszeiten und Exportleistung sind daher nicht vergleichend getestet. Die statischen Oberflächenarchive beweisen keine vollständige dynamische Oberfläche oder konkrete Animationskurve.

## Ergebnis

CleanShot 5 ergänzt einen Studio Mode mit Zooms, Cursorbearbeitung und Videohintergründen. Diese Richtung deckt sich mit dem größten noch offenen Unterschied zu Snaprivo: Unsere Videoansicht bietet momentan Vorschau, Trimmen und MP4-/GIF-Ausgabe. Die bestehenden Screenshot-Werkzeuge sind bereits deutlich näher an CleanShot.

Die Herstellerbeschreibung belegt Zooms, Cursorgröße/-glättung, Hintergrundgestaltung, Ausgabeformate und Motion Blur. Es handelt sich um angebotene Funktionen, nicht um hier gemessene Qualitäts- oder Geschwindigkeitsvorteile. [Screen Recording](https://cleanshot.com/screen-recording), [Versionshistorie 5.0](https://cleanshot.com/changelog).

| Vorher in Snaprivo | Sinnvolle Ergänzung | Nutzen und Einordnung |
| --- | --- | --- |
| Schnitt und Export eines Clips | Video-Gestaltung und manuelle Zoomabschnitte, danach erweiterte Timeline | Größter sichtbarer Nutzen; gemeinsam mit dem Screen-Studio-Ausbau planen |
| Mikrofon/Systemton wählbar, kein Live-Pegel | Getrennte Pegelanzeige für aktivierte Tonquellen | Vor einer längeren Erklärung erkennen, ob Signal ankommt; kleinerer eigener Ausbauschritt |
| Schnellvorschau für Bilder, separate Videoansicht | Nach Videoabschluss wahlweise kompakte Vorschau mit Abspielen, Exportieren und Bearbeiten | Kurze Supportclips schneller weitergeben |
| Eigene Projekte lassen sich mit Snaprivo öffnen | Quick-Look-Vorschau und Finder-Miniaturen für `.snaprivo`, später passende Anleitungsformate | Projekte erkennen, bevor die App geöffnet wird |
| Bilder über Import/Drag-and-drop übernehmen | Teilen-Erweiterung für „In Snaprivo bearbeiten“ und „Mit Snaprivo anheften“ | Direkter Einstieg aus Vorschau und anderen Apps |
| Vertikale Scroll-Aufnahme | Horizontale Scroll-Aufnahme als eigener Capture-Ausbau | Breite Tabellen und Boards; größerer Aufwand mit eigener Koordinaten-/Stitching-Abnahme |
| Neun manuelle Ausrichtungen und Randabstand | Optionales optisches Ausbalancieren der Gestaltung | Weniger Nachstellen bei asymmetrischen Screenshot-Inhalten; Erkennung und Grenzen separat festlegen |

Quick Access für Bilder und Videos, horizontales Scrollen und Auto Balance sind öffentlich beschrieben. Live-Tonanzeige und Mikrofonhinweise nennt die Versionshistorie. Ihre Qualität wurde hier nicht praktisch getestet. [Funktionsliste](https://cleanshot.com/features), [Audioanzeige und Aufnahmehinweise](https://cleanshot.com/changelog).

## Vorhandene Funktionen nicht erneut bauen

Snaprivo hat bereits lokale OCR und QR-Erkennung, vertikale Scroll-Aufnahmen, Anheften mit Deckkraft und Klickdurchlässigkeit, Bildgestaltung mit Vorlagen, Stift, Spotlight, Schrittmarken, Unschärfe/Abdeckung, bearbeitbare Projekte, Bild-Schnellvorschau und lokale Bibliothek. Mehrere dieser Ergänzungen wurden bereits im Oktober umgesetzt; siehe [bestehende CleanShot-Ergänzungen](CLEANSHOT-ERGAENZUNGEN-ABNAHME.md). Der ältere [Vergleich vom 20. Oktober](FEATURE-VERGLEICH-2026-10-20.md) beschreibt damalige Lücken und ist keine aktuelle Liste fehlender Werkzeuge.

Cloud, Teamverwaltung, Stapelexport und Bildvergleich sind für diese Empfehlung nicht priorisiert. Die bestehenden Nutzerentscheidungen dazu werden durch den Vergleich nicht geändert.

## Konkrete technische Ansatzpunkte

### Video-Gestaltung und Icon-Wechsel

Die Reihenfolge aus dem Screen-Studio-Vergleich bleibt sinnvoll: Bewegung an bestehenden Bedienelementen verfeinern, Video-Gestaltung einschließlich Export umsetzen, anschließend Timeline und manuelle Zooms erweitern. Cursorbearbeitung und Auto-Zoom benötigen zusätzlich zur Renderpipeline künftig zeitlich gespeicherte Cursor-/Klickdaten. Bereits eingebrannte Cursor können durch die Einführung dieser Metadaten nicht nachträglich unabhängig bearbeitet werden.

Für Icon-Wechsel liefert die gesperrte CleanShot-Installation keine belastbare Laufzeitreferenz. Unsere Empfehlung folgt dem eigenen Quellcode: Auswahlbewegung auf die Markierung begrenzen, Symbolposition und Schriftgewicht stabil halten; kurze native Symbolwechsel nur bei echten Zustandsänderungen wie Play/Pause. Tastatur und reduzierte Bewegung reagieren unmittelbar. Eine erneute Glass-Umgestaltung der verworfenen rechten Seitenleiste gehört nicht dazu.

### Tonanzeige

`ScreenCaptureVideoTransport` registriert Ausgaben für aktivierte Tonquellen. Die Methode `stream(_:didOutputSampleBuffer:of:)` gibt ihre gelieferten Samples bisher ohne weitere Verarbeitung frei; die eigentliche Datei schreibt `SCRecordingOutput`. Ein Pegel wäre eine neue, gedrosselte Auswertung außerhalb des MainActor mit kleinem UI-Zustand.

Mikrofon und Systemton sollten getrennt dargestellt werden. Stille ist nicht gleich Stummschaltung; fehlende Berechtigung, fehlendes Gerät, kein aktuelles Signal und ein tatsächlicher Aufnahmefehler müssen unterscheidbar bleiben. Die Anzeige darf keine zweite Aufnahme oder zusätzliche Berechtigung starten. Prüfung mit synthetischem Signal, Stille, wechselnden Quellen, Stop und Abbruch sowie Geräteabnahme.

### Einheitlicher schneller Abschluss

`QuickCaptureView.swift` und der Stapel verwenden Bild-EditorModelle und flache PNG-Dateien. `VideoLibraryModel.preview` führt separat zum Videoeditor. Für eine Video-Schnellvorschau braucht es deshalb ein gemeinsames Aufnahmeergebnis mit Bild-/Videofall sowie passende Aktionen und einen geregelten Lebenszyklus temporärer Ausgabedateien. Ein reiner MP4-Pfad als PNG-Drag-Ersatz wäre unzureichend. Der bestehende Fokus- und Wiederherstellungsablauf soll erhalten bleiben; die Wahl zwischen Schnellvorschau und direktem Editor ist eine Produkteinstellung.

### macOS-Erweiterungen

REA hat die vier `Info.plist`-Deklarationen gelesen und damit mehr als bloße Verzeichnisnamen bestätigt:

- `AnnotateShareExtension` und `PinShareExtension` deklarieren `com.apple.share-services` und Aktivierung für Bildtypen.
- `QuickLookExtension` deklariert `com.apple.quicklook.preview` für CleanShot-Bild- und Videoprojekte.
- `QuickLookThumbnailingExtension` deklariert `com.apple.quicklook.thumbnail` für CleanShot-Bildprojekte.

Das belegt die deklarierten Integrationspunkte; ihre Freischaltung, Funktion und Darstellung wurden nicht live geprüft. Snaprivo würde eigene Extension-Targets und eigene sichere Projektleser verwenden. Vorschauen sollten den gespeicherten flachen Bildstand zeigen; beim Empfang über Teilen entsteht eine eigene lokale Kopie. Team/Provisioning und reale Finder-/Fremd-App-Abnahme gehören zum späteren Integrationsschritt.

Die CleanShot-Hauptsignatur nennt Developer ID und Hardened Runtime, aber kein `com.apple.security.app-sandbox`-Entitlement. Das Paket enthält außerdem Sparkle. Diese Distribution ist keine technische Vorlage für Snaprivos vorgeschriebenen Sandbox-/Store-Build; dessen Regeln bleiben bestehen.

## Empfohlene nächste Auswahl

1. Die bereits ermittelten Icon-Wechsel und Video-Gestaltung als sichtbaren ersten Ausbau.
2. Audio-Pegel als eigenständige Verbesserung der Aufnahme.
3. Kompakte Video-Schnellvorschau und anschließend Quick Look.
4. Manuelle Zoomabschnitte und erweiterter Schnitt; Auto-Zoom/Cursorpipeline danach.
5. Teilen-Erweiterung, horizontales Scrollen und optische Balance nach Bedarf getrennt bewerten.

## Nachweise

- App: `/Applications/CleanShot X.app`, Bundle-ID `pl.maketheweb.cleanshotx`, Version/Build `5.0.2`.
- Hauptprogramm: universelles Mach-O für x86_64 und arm64; untersuchte Architektur arm64. SHA-256 `d11e2cbd5afe1ac56d89561d66161290208d1e37fd9e5003cee9152d6177df6c`.
- Paketinventur: 361 Vorkommen, 330 Inhaltsknoten, keine gemeldeten Integritätswidersprüche. Metadaten lesen ohne Programmausführung oder Aktivierung.
- Oberflächenarchive: 15 NIB-Dokumente mit 1315 erkannten Knoten und 706 Kanten; die Projektion ist partiell. Unbekannte Archivfelder und dynamische Oberflächen bleiben offen. Lizenzarchive waren Teil der allgemeinen Inventur; ihre Inhalte wurden nicht für einen Umgehungsweg untersucht.
- Asset-Metadaten: 4 Kataloge, 1352 Records; nur die erste Seite mit 64 Records gelesen. Keine Icon- oder Bildressourcen in Snaprivo übernommen.
- Gebündelte Demo: 6,583 s, 1000 × 500, 60 fps. Einzelbilder bei 0,6, 2,8 und 5,2 s außerhalb des Repositories angesehen. Dies ist keine gemessene Capture- oder Exportleistung.
- REA-Evidence: `/tmp/Snaprivo-CleanShot-Review/rea-evidence.json`, 14 Records, 3.240.851 Bytes. Sitzung anschließend geschlossen.
- Nur dieses Vergleichsdokument ergänzt; keine App-Codeänderung und daher kein neuer Build-/Testlauf.

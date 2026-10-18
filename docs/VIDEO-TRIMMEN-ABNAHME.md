# V03 – Videovorschau, Trimmen und MP4-Export

Stand: 16. Oktober 2026. Die restlichen **echten** Ton- und Synchronitätstests aus T02/V04 bleiben auf Nutzerwunsch für später vorgemerkt. Die folgenden Tonprüfungen verwenden ausschließlich synthetisch erzeugte Dateien ohne Aufnahmegerät oder Lautsprecherausgabe.

## Bedienung

Nach erfolgreichem **Stop** öffnet seit 17. Oktober 2026 die gerade finalisierte Aufnahme direkt hier. Vorhandene Videos lassen sich weiterhin in **Bibliothek → Videos** anklicken oder über **Video ansehen** öffnen. Snaprivo öffnet eine interne Vorschau mit nativen AVKit-Steuerelementen. Start und Ende lassen sich über Sekundenwerte, Schieberegler oder die aktuelle Abspielposition setzen. **Auswahl abspielen** startet am gewählten Beginn und stoppt am Ende. Die Vorschau hält das Seitenverhältnis des Originals.

**Übernehmen** beziehungsweise **⌘S** sichert die Grenzen. Bis dahin ist die Auswahl ein Entwurf; der MP4-Export ist gesperrt. Ungültige Grenzen werden erklärt und lassen sich nicht übernehmen. Mindestens ein Videobild mit Bezug auf das Aufnahmeziel 30 fps muss bleiben. **Rückgängig/Wiederholen** beziehungsweise **⌘Z/⇧⌘Z** schreibt den jeweils gewählten Arbeitsstand zurück. Die Historie gilt für die geöffnete Vorschau; nach Wiederöffnen beginnt sie neu. **Ganzes Original** setzt die Grenzen als Entwurf zurück und bleibt auch nach einem Neustart verfügbar.

Schließen/Escape mit offenen Änderungen verlangt Verwerfen oder Abbrechen. Beim normalen App-Beenden werden laufende Speicher-/Exportaufträge abgewartet; eine noch nicht übernommene Auswahl verhindert das Beenden mit einem Hinweis. Das normale Beenden einer gesicherten Vorschau pausiert die Wiedergabe. **Original extern öffnen** bleibt als ausdrücklich separate Bibliotheksaktion verfügbar.

## Speicher- und Exportregeln

- Das finalisierte Original bleibt unverändert. Übernehmen, Undo/Redo und Wiederöffnen ändern ausschließlich den kleinen JSON-Arbeitsstand. Originaldauer und Pixelgröße bleiben Fakten der Originaldatei.
- Videoformat **2** ergänzt optionale Start-/Endgrenzen und eine Revision. Version 1 wird mit dem ganzen Original und Revision 0 gelesen. Unbekannte neuere oder ungültige Daten werden abgelehnt. Revisionen verhindern, dass ein veralteter Editor neuere Änderungen überschreibt oder versehentlich einen veralteten Stand exportiert; ein Fehler bietet das Neuladen des gesicherten Stands an.
- Videosicherungen enthalten weiterhin **vollständige Originale** mit Prüfsummen, nun zusätzlich den gespeicherten Schnitt. Wiederherstellen erzeugt neue IDs samt Schnitt. Es ersetzt keine vorhandenen Videos.
- MP4-Ausgabe aus Vorschau **und** Bibliothek verwendet die gesicherten Grenzen. Ohne Schnitt wird das Original unverändert kopiert. Ein Schnitt wird über das öffentliche AVFoundation-Exportverfahren neu kodiert, sodass auch Grenzen zwischen H.264-Schlüsselbildern verwendbar sind. Ausgabe bleibt MP4/H.264 mit Originalmaßen; eine vorhandene AAC-Tonspur wird mit derselben Zeitspanne exportiert. Keine neue externe Abhängigkeit.
- Export zunächst in ein temporäres Verzeichnis auf dem Zielvolume, danach Prüfung von Dauer, Maßen, dekodierbarem Bild und vorhandenem/dekodierbarem Ton. Erst nach erfolgreicher Prüfung und letzter Abbruchprüfung wird das Ziel atomar ersetzt beziehungsweise verschoben. Fehler oder Abbruch erhalten das Original und ein bestehendes Exportziel. **Export abbrechen** bricht die asynchrone Kodierung ab; temporäre Daten werden bereinigt.
- Ziele innerhalb der Videobibliothek sind gesperrt, einschließlich aufgelöster Symlink-Pfade. Nativer Speicherdialog und zeitlich begrenzter Security-Scoped-Zugriff bleiben der Sandbox-Dateizugriff.

Verwendete öffentliche APIs wurden im macOS-SDK und in Apples Dokumentation geprüft: [AVAssetExportSession.export(to:as:isolation:)](https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession/export%28to%3Aas%3Aisolation%3A%29) und [timeRange](https://developer.apple.com/documentation/avfoundation/avassetexportsession/timerange). Die asynchrone Exportmethode übernimmt selbst die Task-Abbruchbehandlung.

## Nachweise

- `./scripts/test.sh`: 120 Domain-Tests, einschließlich Grenzen, Normalisierung des ganzen Originals, Format-1-Migration, Format-2-Roundtrip und unzulässiger Zustände.
- `./scripts/test-video-editing.sh --sandbox`: echte synthetische H.264-/AAC-Dateien im signierten App-Sandbox-Host. Ungültige Grenzen, Entwurfsschutz, Übernehmen, Undo/Redo, Original zurücksetzen, Wiederöffnen, AVPlayer-Grenzen und automatischer Stop. Konflikte bei Speichern/Export, Neuladen, Sicherung/Wiederherstellung mit vollem Original und gesichertem Schnitt. Beschädigte Metadaten-IDs dürfen keinen Schreibvorgang auf eine andere Video-ID umleiten. Auch die kleinste erlaubte Auswahl wird tatsächlich exportiert und enthält genau ein Videobild. Bytes, Dateinummer und Änderungsdatum des Originals bleiben identisch.
- Exportvergleich: 1-s-Original, Schnitt **0,23–0,77 s**, Ausgabe **0,54 s**, 320 × 180, H.264. Der erste überlappende Originalframe liegt bei 0,20 s, der letzte bei 0,766667 s; beide innerhalb eines Videobildes der gewählten Grenze, keine ungekürzte Schlüsselbild-Vorlaufsequenz. Vollständig dekodierter AAC-Impuls bei **0,103333 s**, zugehöriger exportierter Videoframe ebenfalls **0,103333 s**. Stille Videos erhalten keine Tonspur. Ausgabe ohne Schnitt bleibt byteidentisch.
- Bestehendes Ziel erfolgreich atomar ersetzt; fehlender Zielordner abgelehnt; Abbruch vor Beginn und gezielt **nach** erfolgreicher Kodierung/Prüfung, unmittelbar vor Veröffentlichung, erhält das bisherige Ziel. Export in die Originalbibliothek abgelehnt.
- Zwei getrennte Prozessstarts im Sandbox-Host: Schnitt persistieren, neu laden und mit diesen Grenzen erneut exportieren/dekodieren. Sicherung/Wiederherstellung erhält den gleichen Ablauf unter neuer ID.
- `./scripts/test-video-library.sh --sandbox`: bestehende Bibliotheks-/Sicherungs-/Migrations-/Neustartregression bestanden.
- `./scripts/test-video.sh`: synthetische Aufnahme-/Berechtigungs-/Countdown-/Lebenszyklusregression bestanden; keine echten Tonquellen geöffnet. Signierter Sandbox-Build, strikte Signaturprüfung, 755 deutsche/englische App-Texte mit vollständiger Compiler-Abdeckung und native Sprachprüfungen bestanden.
- Tatsächliche deutsche Produktionsoberfläche mit synthetischem 2-s-Video: interne Vorschau, Sekundenwerte 0,25–1,75, Übernehmen, Undo/Redo, Schließen und erneutes Öffnen mit gesicherter Auswahl. Nativen Speicherdialog abbrechen und erneut speichern; Erfolgsmeldung für MP4-Ausgabe. Verwerfen-Abfrage mit Abbrechen und Verwerfen bedient. Die Vorschau bleibt bei 800 Pixeln Hauptfensterbreite vollständig bedienbar.
- Die tatsächlich über den Speicherdialog erzeugte MP4 anschließend dekodiert: **1,5 s**, 320 × 180, keine eingeführte Tonspur und unterschiedliche Bildframes.
- ⌘S sowie native ⌘Z/⇧⌘Z im endgültigen Vorschau-Blatt tatsächlich bedient. Die Prüfsteuerung benötigt bei deutschem Tastaturlayout die vertauschte physische Y/Z-Position; die App verwendet normale macOS-Menübefehle ohne zusätzlichen Ereignismonitor.

## Grenzen

Dies belegt den Dateischnitt und die gemeinsame Medienzeitachse der synthetischen Fixtures. Es ist **keine** neue echte Aufnahme-/Mikrofon-/akustische Synchronitätsabnahme. Die verbleibenden Quellen-/Stop-, Mikrofonpegel-, macOS-26-, 15-Minuten- und Hardwarefälle aus V01/V04 sowie die breite VoiceOver-/Kontrastabnahme Q03 bleiben offen. Videoannotation, Mehrspur-Timeline, einzelne mittlere Ausschnitte entfernen, Video-Papierkorb, HDR/4K/60 fps und automatische Tonkorrektur sind nicht implementiert.

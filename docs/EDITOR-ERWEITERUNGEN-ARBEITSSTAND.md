# Editor-Erweiterungen – Arbeitsstand 20.10.2026

Auftrag: Freihandstift, Spotlight, Ausrichten/Einrasten/Gruppenskalierung, lokale Schwärzungsvorschläge sowie GIF-Ausgabe/Klickanzeige. Stapelexport und Bildvergleich ausgeschlossen.

| Teil | Zuständig | Zustand | Integrationsprüfung |
| --- | --- | --- | --- |
| Stift/Spotlight, Format, Canvas und gemeinsame UI | Hauptagent | Implementiert, geprüft | Domain, Canvas-Pixel/Interaktion, Persistenz/Export bestanden |
| Ausrichten/Einrasten/Gruppenskalierung | alignment_tools + Integration Hauptagent | Implementiert, geprüft | Geometrie/Undo/Gruppen und native Canvas-Gesten bestanden |
| Lokale Schwärzungsvorschläge | privacy_tools + Korrekturen Hauptagent | Implementiert, geprüft | Detektor, echte Vision auch in App Sandbox, Koordinaten, Abbruch/Neustart, Revision, Undo/PNG/Persistenz bestanden |
| GIF-Ausgabe und Klickanzeige | video_tools + Integration Hauptagent | Implementiert, geprüft | Synthetisches Video/GIF, Abbruch/Dateierhalt, Aufnahme-Konfiguration bestanden |
| Registrierung, Sprachen, Dokumentation und Gesamtprüfung | Hauptagent | Implementiert, geprüft | App-Build, 148 + 2 Domain-Tests, vollständige Canvas-Suite, Video/Einstellungen, vollständige OCR und Sprachabdeckung bestanden |

Alle Teilbereiche bearbeiten getrennte Dateien im bestehenden Checkout; die gemeinsame Integration erfolgt durch den Hauptagenten. Vorhandene lokale Änderungen bleiben erhalten. Es wird nichts veröffentlicht.

Bedienung und verbleibende reale Aufnahme-/Accessibility-Abnahme: [Editor-Workflow-Abnahme](EDITOR-WORKFLOW-ABNAHME.md). Die sichtbare Klickdarstellung in einer echten Aufnahme ist noch manuell zu prüfen.

# Prüfung der Projektgrundlage

Stand: 12. Oktober 2026

- Umgebung: Xcode 27.0, macOS 27.0, Apple Silicon.
- `scripts/build.sh`: erfolgreich, lokale ad-hoc-Signatur. Xcode meldet lediglich die ausgelassene App-Intents-Metadatenextraktion ohne AppIntents-Abhängigkeit. Der lokale ad-hoc-Build ersetzt keinen signierten Store-/Hardened-Runtime-Release.
- `scripts/test.sh`: drei Swift-Testing-Tests erfolgreich, darunter vier Parameterfälle für ungültige Bildgrößen. Roundtrip und Ablehnung beschädigter gespeicherter Dimensionen geprüft.
- Projektdatei und Entitlements: mit `plutil` geprüft.
- App-Signatur: `codesign --verify --strict` erfolgreich. App Sandbox und benutzergewählter lesender Dateizugriff im gebauten Bundle bestätigt.
- App gestartet: Bibliotheksfenster und native Symbolleiste vorhanden.
- Aufnahmefenster per App-Tastenkürzel geöffnet; Umschalten Bild/Video und Bereich/Fenster geprüft. Aufnehmen bleibt absichtlich deaktiviert.
- Abgeschnittener Erklärungstext im Aufnahmefenster korrigiert und erneut visuell geprüft.
- Nativen Öffnen-Dialog und PNG-Import mit bereitgestelltem Konzeptbild geprüft; Bildvorschau und deaktivierte, benannte Editorwerkzeuge im Accessibility-Baum vorhanden.
- Nach dieser Sichtprüfung Bildlayout auf verfügbare Fläche begrenzt und erneut erfolgreich gebaut; diese letzte Layoutänderung ist noch nicht erneut visuell abgenommen.

Noch nicht geprüft: Ausführung auf macOS 26, Intel, VoiceOver-Bedienung, Kontrast-/Transparenzeinstellungen und sämtliche echten Capture-/Export-/Persistenzabläufe. Diese Funktionen sind noch nicht implementiert. Der Import ist derzeit eine synchrone Vorschaufunktion; asynchroner Import und Ressourcenlimits gehören in den folgenden Import-Service.

Git auf `main` initialisiert; kein Remote, kein Commit, keine Veröffentlichung angelegt.

## Ergänzung zur echten Screenshotaufnahme

Die frühere Aussage „Aufnahme nicht implementiert“ beschreibt ausschließlich die Projektgrundlage. ScreenCaptureKit-Service, Fenster-/Bereichsauswahl und Berechtigungsablauf sind inzwischen implementiert. Aktueller Stand und verbleibende reale Tests: `SCREENSHOT-ABNAHME.md`. Der neue Build und acht Domain-Tests bestehen; die Berechtigungserklärung, fehlende Freigabe und erneute Prüfung ohne erneute Systemanfrage wurden in der laufenden App geprüft. Nach den Korrekturen benötigt der ad-hoc-signierte Build auf diesem Mac erneut die Freigabe.

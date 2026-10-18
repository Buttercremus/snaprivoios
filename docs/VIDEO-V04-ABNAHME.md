# V04 – Teilabnahme ohne Ton und Synchronitätsmessung

Stand: 16. Oktober 2026. **V04 bleibt offen.** Durchgeführt sind stumme Datei-/Lebenszyklusprüfungen, isolierte Systemmeldungen und erste echte Fensteraufnahmen. Die restlichen Ton- und Synchronitätstests bleiben auf Nutzerwunsch später. In diesem Schritt wurden weder Mikrofon noch Systemton eingeschaltet und keine AAC-/A/V-Tonprüfung ausgeführt.

## Umgebung

- Apple M1 Pro, MacBookPro18,3, 32 GiB RAM, 10 logische CPU-Kerne.
- macOS 27.0, Build 26A428; Xcode 27, Swift 6, Deployment Target weiterhin macOS 26.0.
- Normal signierter Debug-Build, App Sandbox aktiv. Echte Aufnahme über Snaprivos Fensterwahl, Start/Stop und nativen Speicherdialog. Der offene Bildarbeitsstand wurde vor dem Build gesichert.
- Eigenes synthetisches AppKit-Fenster: 960 × 544 pt einschließlich Fensterrahmen, Retina-Quelle 1920 × 1088 px, proportionale H.264-Ausgabe **1904 × 1080 px**. Farbige Eckmarken, bewegtes Quadrat, Bildzähler und wechselnder Hintergrund; keine Aufnahme-/Audio-APIs in der Testquelle. Der erste Versuch zeichnete mit einem 30-Hz-Timer; die wiederholbare Testquelle ist anschließend auf 60 Zeichenupdates/s für das Aufnahmeziel 30 fps umgestellt.
- Freier Datenträgerplatz schwankte im Verlauf ungefähr zwischen 1,8 und 3,4 GB. Keine Nutzerdateien wurden für die Prüfung gelöscht und keine Lautstärke-, Energie- oder Datenschutz-Einstellung verändert.

## Ergebnisse und Grenzen

| Fall | Nachweis | Stand |
| --- | --- | --- |
| Echte Fensterwahl ohne Ton | Synthetische Quelle ausdrücklich ausgewählt, beide Tonoptionen aus, 1904 × 1080 angezeigt | Geprüft |
| Fenstergröße ändern und verschieben | Echte Aufnahme, Hochformat und Rückkehr, kontrollierter Stop, Export über NSSavePanel. Dekodierte Frames zeigen das ganze Fenster mit allen vier Eckmarken; freie Fläche schwarz, Seitenverhältnis erhalten | Geprüft für diesen Mac und die Testquelle |
| Datei der Fensteränderung | **7,836667 s, 220 dekodierte H.264-Frames, keine Audiospur**, maximaler Zeitstempelabstand und längste identische Bildfolge jeweils rund **46,667 ms** | Lesbare Ausgabe ohne langen Bildstillstand |
| Ziel 30 fps | Derselbe kurze Versuch erreicht im Mittel **28,073 Bilder/s**. Das zuvor festgelegte Diagnoseziel mindestens 29 Bilder/s wird verfehlt | **Kein 30-fps-Abnahmepass**; konstante 60-Hz-Referenz und längerer Lauf erneut prüfen |
| Minimieren/Wiederherstellen | Nach Einschränkung des Displaybeobachters am entsperrten Mac erneut geprüft: Testfenster für 2 s minimiert und wiederhergestellt; Aufnahme läuft weiter, regulärer Stop und nativer MP4-Export gelingen. 9,535 s, 215 H.264-Frames, 1904 × 1080, keine Audiospur; erstes und letztes dekodiertes Bild zeigen die ganze Quelle mit fortgeschrittenem Zähler | Ablauf geprüft; während Minimierung 1,388 s Zeitstempellücke, kein Nachweis kontinuierlicher Bildfolge/30 fps |
| Quellfenster schließen | Während stummer Aufnahme geschlossen. Sichtbarer Quellenfehler „Keine Displays oder Fenster für die Aufnahme gefunden“, Stream-Stop protokolliert; Speichern/Vorschau gesperrt, Schließen erreichbar. Bibliothek zeigt den neuen Eintrag als fehlgeschlagen; ältere fertige Aufnahmen bleiben verfügbar | Fehlerablauf auf diesem Mac geprüft; kein fertiges Video veröffentlicht |
| Stummer 15-Minuten-Lauf | Tatsächlich gestartet. macOS beendete ihn innerhalb der ersten Minute wegen `insufficientStorage`, Code **−3822**. Fehlerstand bleibt in der Bibliothek erkennbar; keine fertige MP4 angeboten | **Nicht bestanden / ausreichend Speicherplatz erforderlich** |
| Sleep, Display-Sleep, Displaykonfiguration | 24 native Sitzungsfälle mit isolierten NotificationCenters und stummen echten Dateifixtures, einschließlich Abbruch vor Start und gültiger Finalisierung während Aufnahme | Kontrolllogik geprüft; echte physische Unterbrechungen offen |
| Rechteentzug, Geräte-/Displaywechsel, macOS 26 | Keine Änderungen an TCC oder angeschlossenen Geräten vorgenommen | Offen |

Nach bestätigtem manuellem Entsperren wurden die echten Minimier- und Quellschließfälle fortgesetzt. Der Minimierbeleg verwendet die 60-Hz-Testquelle, erreicht einschließlich der bewussten Minimierung nur 22,549 Bilder/s im Mittel und verfehlt die Grenzen des Auswerters für eine durchgehend bewegte Quelle. Das ist ein bestandener Start-/Weiterlauf-/Stop-/Exportablauf, kein bestandener Bildraten- oder Dauerlauf. Eine ununterbrochene Referenzaufnahme bleibt offen. Der sichtbare Zähler der schon zuvor laufenden Testquelle ist nicht die Aufnahmedauer. Die Testquelle ist anschließend geschlossen; Snaprivo steht wieder in der Videobibliothek, keine Aufnahme läuft.

## Gefundene Fehler und Korrekturen

**Ursächlicher Speicherfehler hinter früher Dateiende-Meldung:** Das macOS-Protokoll zeigt am 16.10.2026 um 15:52:34,640 zuerst `recordingOutputDidFinishRecording`, um 15:52:34,655 anschließend `didStopWithError` mit −3822. Der bisherige Controller hatte das frühe Dateiende sofort als allgemeinen Abbruch festgeschrieben. Ein unerwartetes Dateiende sperrt die Veröffentlichung jetzt weiter und gibt der konkreten Plattformursache höchstens 50 ms Zeit, bevor der allgemeine Abbruch als Rückfall verwendet wird. Der erste konkrete Fehler bleibt maßgeblich; Terminalzustände bleiben endgültig. Auch Start-Wartende und Stop-Zeitgrenzen werden abgeschlossen.

Speicherfehler von ScreenCaptureKit, POSIX `ENOSPC` und Cocoa `fileWriteOutOfSpace` erhalten einen verständlichen Hinweis: Platz schaffen und erneut aufnehmen. Der Originalfehler wird für die vorhandene Fehler-/Berechtigungsführung erhalten. Der öffentliche SDK-27-Code wird nur unter macOS 27 zugeordnet, als Rohwert, damit der Quellcode keinen SDK-27-Enum-Namen voraussetzt. Der 128-MB-Startcheck ist weiterhin nur eine App-Mindestprüfung; daraus folgt keine Garantie für die zusätzlichen Speicherbedingungen von macOS. Eine universelle freie macOS-Speicherschwelle wurde nicht ermittelt.

**Definierter Umgang mit Systemunterbrechungen:** Vor Start wird eine Auswahl/Countdown/Startvorbereitung bei einer Sleep- oder tatsächlich geänderten Bildschirmkonfiguration abgebrochen. Während Aufnahme wird ein normaler Stop samt Finalisierung versucht. Nur bei erfolgreichem Abschluss bleibt eine fertige MP4 mit verständlichem Hinweis verfügbar. Stop-Fehler/Timeouts bleiben Fehler und werden nicht durch einen Erfolgshinweis verdeckt. Mehrfache Meldungen und gleichzeitiges Schließen teilen den Abschluss; geschlossene Sitzungen entfernen die Beobachter. Ein allgemeines AppKit-Bildschirmereignis ohne geänderte IDs, Geometrie oder Pixelskalierung unterbricht nicht mehr.

Die öffentlichen Meldungen sind im SDK und in Apple-Dokumentation geprüft: [NSWorkspace.willSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification), [NSApplication.didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification). Workspace-Meldungen werden am Workspace-NotificationCenter registriert. Die App erzwingt oder verzögert keinen System-Ruhezustand; das physische Verhalten bleibt abzunehmen.

## Wiederholbare Prüfungen

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-video-validation.sh --sandbox
python3 Tests/VideoValidationAnalysisChecks.py
./scripts/build-video-validation-fixture.sh
# Testquelle öffnen, in Snaprivo nur ihr Fenster wählen; beide Tonoptionen aus.
# Für den Dauerlauf nach mindestens 15 Minuten stoppen und nach /tmp exportieren.
python3 scripts/check-silent-video.py /tmp/Stummer-Dauerlauf.mp4 --output build/video-v04-long.json
```

- 120 Domain-Tests bestanden. Native stumme Lebenszyklus-/Fehlersitzungen und die zusätzlichen Unterbrechungsfälle im signierten Sandbox-Host bestanden. Keine echte Sleep-/TCC-/Geräteänderung und kein Toneingang dabei.
- Abschließender normal signierter Debug-Build und Signaturprüfung bestanden. 758 App-Texte, vier InfoPlist-Texte und 13 Domain-Texte vollständig in Deutsch/Englisch; Compiler-Abdeckung im separaten Lokalisierungsbuild und native Bundle-/Sprachprüfungen des abschließenden App-Bundles einschließlich englischem Rückfall bei Französisch bestanden. Im älteren Standard-DerivedData-Verzeichnis liegen noch überholte Compiler-Extraktionen; deshalb stammt der Abdeckungsnachweis aus dem separaten Build.
- Geprüft: nur fertig bestätigte Ausgabe, gültige stumme MP4, Start-/Stop-Fehler, ursprüngliche Fehlermeldung, doppelte/späte Rückmeldungen, gemeinsame Stop-Aufrufe, Deadline, versteckte unbestätigte Arbeitsdatei, Erhalt älterer fertiger Fixtures, Countdown-/Startabbruch durch Systemmeldungen, Beobachterentfernung. Harmloses Displayereignis ohne Snapshotänderung erhält den jeweiligen Zustand.
- Neue Reihenfolge zusätzlich geprüft: unerwartetes Dateiende, **15 ms später konkreter Speicherfehler**, weiterer Folgefehler; genau ein Abschluss und die konkrete Ursache. Allgemeines Dateiende ohne Plattformursache bleibt ein Abbruch. Verständlicher Speicherhinweis an der echten Produktionssteuerung im isolierten Host geprüft.
- Der unabhängige stumme Auswerter dekodiert **jedes** Bild, prüft monotone Zeitstempel, Bildzahl, Maße, H.264, fehlende Audiospur, Anfang/Mitte/Ende und identische Bildfolgen mit begrenztem Pixelpuffer. Diagnosegrenzen vor Auswertung: mindestens 29 Bilder/s im Mittel, Median nahe 30 fps (±2 ms je Frame), maximal 250 ms Zeitstempelabstand und 500 ms Stillstand bei der bewegten Testquelle. Ein negativer Bericht ist kein Erfolg.
- Auswerter gegen bewegte synthetische H.264-Datei, zu kurze Dauer, absichtlich eingefrorenes Ende, fehlende Frames und ungültige Datei geprüft. Lokale `ffmpeg`/`ffprobe`-Entwicklerwerkzeuge wie bei den früheren Videoexperimenten; GPL-Binärdateien werden weder in der App ausgeliefert noch verlinkt, keine neue Produktabhängigkeit.

Lokale Belege, `build/` weiterhin ignoriert: `video-v04-build.log`, `video-v04-localized-build.log`, `video-v04-localization.log`, `video-v04-domain.log`, `video-v04-window.json`, `video-v04-window-first.png`, `video-v04-window-middle.png`, `video-v04-window-last.png`, `video-v04-storage-platform.log`, `video-v04-validation.log`, `video-v04-analysis-checks.log`, `video-v04-minimize-after.json`, `video-v04-minimize-after-01.png` bis `-03.png` und `video-v04-source-close-platform.log`. Echte synthetische Ausgabe außerhalb des Repositorys: `/private/tmp/Snaprivo-V04-Window-20261016.mp4`; Vergleich des ersten Minimierfalls: `/private/tmp/Snaprivo-V04-Minimize-BeforeFilter-20261016.mp4`; korrigierter Minimierfall: `/private/tmp/Snaprivo-V04-Minimize-AfterFilter-20261016.mp4`. Die zugehörigen lokalen Bibliothekseinträge heißen **V04 – Dauerlauf durch Speicherplatz abgebrochen**, **V04 – Minimieren und Wiederherstellen** und **V04 – Quellfenster geschlossen**. Keine Nutzeraufnahme oder OCR-Inhalte als Fixture eingecheckt, keine Medien hochgeladen.

## Verbleibende Abnahme

Ausreichenden Speicherplatz schaffen, stummen 15-Minuten-Lauf einschließlich Bildrate/Speicherverlauf vollständig wiederholen; Bildratenziel mit ununterbrochen bewegter Referenz sowie längere Minimierung und Verdeckung prüfen. Tatsächlicher Sleep/Display-Sleep, mehrere/wechselnde Displays, Rechteentzug und macOS 26 bleiben offen. Die restlichen Ton-, Mikrofonpegel-, Geräte- und A/V-Synchronitätstests sind ausdrücklich für später vorgemerkt. V01, T02 und V04 bleiben insgesamt offen.

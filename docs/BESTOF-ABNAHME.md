# Nachweise zum Ausbau aus beiden App-Vergleichen

Stand: 2. November 2026. Operative Aufgaben und Reihenfolge stehen ausschließlich im [Arbeitsplan](ARBEITSPLAN.md). Der Ausgangsstand wurde als `24a1bb2` lokal gesichert. Keine Veröffentlichung.

## A01 Icon-Wechsel

Die Auswahlfeder liegt jetzt nur auf der Markierung im Button-Hintergrund. Symbol und Beschriftung behalten ihr Schriftgewicht, die bereits reservierten Buttonbreiten bleiben bestehen. Der Videoeditor verwendet für Play/Pause einen nativen SF-Symbol-Replace-Übergang; die Aktion animiert nur im vorhandenen Mausereignis und ohne reduzierte Bewegung. Es gibt keine neue Animation auf der Bild-/Video-Geometrie und keinen neuen Glass-Seitenleistenstil.

- `./scripts/build.sh -derivedDataPath build/BestOfApps/Xcode`: bestanden.
- `./scripts/test-editor-toolbar.sh`: native Größen-/Überlauf-/Exaktbreitenprüfung in Deutsch und Englisch bestanden. Die erzeugte deutsche Testdarstellung wurde visuell gesichtet.
- `./scripts/test-video-editing.sh`: Wiedergabe, Schnitt, Undo/Redo, Ausgabe, Abbruch, Schutz der Originale und Prozessneustart bestanden.
- `git diff --check`: bestanden.

Logs: `/tmp/Snaprivo-bestof-{build,toolbar,video}.log`. Der Screenshot des nativen Testfensters prüft die Darstellung, keine zeitliche Animationskurve. Persönliches Bewegungsgefühl mit schneller Mausbedienung und vollständige VoiceOver-Abnahme bleiben manuell.

## A02 Video-Gestaltung

Der Videoeditor hat eine größere, in ihrer Geometrie stabile Vorschau mit eigenem Gestaltungsbereich. Ohne Gestaltung bleibt die Ausgabe neutral. Farbe und editierbarer Zweifarbverlauf, Randabstand, gerundete Ecken, Schatten und fünf Seitenverhältnisse sind verfügbar. Beim ersten Hintergrund werden 32 px Abstand, 12 px Ecken und 35 % Schatten vorbelegt, damit die Änderung direkt sichtbar ist. Regler haben keine zusätzlichen Skalenpunkte. Die Ausgabegröße ist im scrollenden Gestaltungsbereich ablesbar.

`VideoPresentation` liegt im Domain-Paket. Videoformat 4 speichert den Zustand und liest 1–3 neutral; ältere Apps dürfen das neue Format nicht still übernehmen. Die Originaldatei bleibt unverändert. Schnitt und Gestaltung bilden gemeinsam einen gesicherten Zustand mit Undo/Redo, Konfliktschutz und Backup. Das bisherige explizite Sichern bleibt erhalten. Videoschnitt/Gestaltung folgen der vorhandenen Pro-Grenze.

Eine unveränderliche AVFoundation-Instruktion und ein Core-Image-Compositor versorgen AVPlayer, MP4 und GIF. Keine neue Paketabhängigkeit und keine private API. Die Ausgabe behält das gesamte Quellbild und ergänzt Fläche entsprechend dem Format; dies ist kein automatischer Motivzuschnitt. Encoderabmessungen sind gerade, die gestaltete Fläche ist auf 8192 px je Kante und 16 MP begrenzt. Eigene Hintergrundbilder und Motion Blur gehören nicht zu diesem Schritt.

Zusätzliche Prüfungen deckten zwei Fehler vor Abschluss auf: gedrehte Quellen benötigen ihre dargestellte Größe und die Umrechnung zwischen Video- und Core-Image-Koordinaten; eine pausierte AVPlayerLayer behielt nach reinem Kompositionswechsel einen alten Frame. Die Korrektur veröffentlicht ein vollständig konfiguriertes PlayerItem am erhaltenen Player. Die Abspielposition reagiert schon beim Start des Seek, und dessen spätere Bestätigung bleibt gegen veraltete Wiedergabe geschützt.

- `./scripts/build.sh -derivedDataPath build/BestOfApps/Xcode`: bestanden.
- `./scripts/test.sh`: 184 Swift-Testing-Tests und 2 XCTest-Tests bestanden. Neue Prüfung für gerade Ausgabegrößen, Formate, Grenzen, Farb-/Zahlenvalidierung, Version-3-Migration und falsch deklarierte ältere Formate.
- `./scripts/test-video-editing.sh` und `--sandbox`: bestanden. Neue echte Pixelprüfungen für Vorschau/MP4/GIF, Hintergründe, Ecken, Verläufe, Formate und gedrehte Farbquadranten; Ton/Schnitt, unveränderte Originalbytes, Wiederöffnen, Backup, Undo/Redo, Pro-Sperre und Abbruch vor Veröffentlichung. Ein AVPlayerItemVideoOutput liefert den gestalteten Frame ohne Abspielen; die bestehenden Wiedergabe-/Schnitt-/Neustartprüfungen bestehen ebenfalls.
- Lokalisierung: 1373 App-, 7 InfoPlist- und 19 Domain-Texte mit vollständiger deutscher/englischer Compiler-Abdeckung und passenden Formatargumenten.
- Native deutsche Prüf-App mit ausschließlich synthetischen Bildern/Clips: Verlauf im pausierten Zustand und bei Wiedergabe sichtbar; Sichern, Undo und Redo bedient. Original und 9:16 zeigen passende Vorschau und Ausgabegröße (384 × 244 bzw. 384 × 684 im Test). Die Editor-Screenshots bleiben vor und nach beiden Wechseln 1520 × 1376 Pixel groß. Die Prüf-App ist von der Produktionsbibliothek getrennt.
- `git diff --check`: bestanden.

Logs: `/tmp/Snaprivo-bestof-presentation-{build,video,sandbox,localization}.log`, Domain-Log `/tmp/Snaprivo-bestof-domain.log`. Keine Bildraten-, lange Aufnahme-, HDR- oder vollständige VoiceOver-Abnahme. Diese Ergebnisse bestätigen technische Ausgabe und synthetische Bedienung, keine neue Capture-/Berechtigungsabnahme.

## A03 Audio-Pegel

Die vorhandenen Systemton-/Mikrofon-Samples werden auf ihrer Sample-Queue ausgewertet. Nur begrenzte RMS-/Spitzenwertaggregate gelangen mit höchstens 10 Hz je Quelle auf den MainActor. Es gibt keinen zweiten Audiostream, keine neue Berechtigung und keine Persistenz von Samples oder Messwerten. Die Pegel werden nur während bestätigter Aufnahme weitergegeben, nicht bei Start, Stop oder späten Delegate-Ereignissen.

Die bestehende 360 × 56 pt große Leiste zeigt aktivierte Quellen mit Lautsprecher/Mikrofon und nativer, nicht editierbarer Pegelanzeige. Ein eingehender Nullpegel bleibt Stille; ausbleibende Werte werden zurückgesetzt und erhalten „Wartet auf Audiodaten“ als Hilfe. Die vorhandenen Aufnahmefehler bleiben zuständig für tatsächliche Fehler. Beim Stop verschwinden die Anzeigen und verlieren ihre Werte. Ein Signaltest fand Rundung oberhalb des Spitzenwerts bei konstanten Samples; RMS wird deshalb auf den tatsächlich gemessenen Spitzenwert begrenzt.

- Build mit `./scripts/build.sh -derivedDataPath build/BestOfApps/Xcode`: bestanden.
- `./scripts/test.sh`: 186 Swift-Testing-Tests und 2 XCTest-Tests bestanden, einschließlich Stille, Pegel, NaN/Unendlich, Grenzen und konstantem Signal.
- `./scripts/test-video-editing.sh --sandbox --audio-levels`: PCM-Signal/Stille, unabhängige Messfenster, zurückgesetzte Uhr, veraltete Werte, aktivierte Quellen, native Geometrie und Aufnahmezustände einschließlich Stop/Abbruch/später Ereignisse bestanden. Auch die vollständige Video-Regression mit dem final gebauten Sandbox-Testhost bestand. Ein vorheriger Versuch im Sperrzustand fiel am AVPlayer-Test aus und wurde nicht als bestandene Prüfung gewertet.
- Lokalisierung: 1376 App-, 7 InfoPlist- und 19 Domain-Texte vollständig Deutsch/Englisch; native Sprach-/Neustartprüfungen bestanden.
- Native deutsche Prüf-App mit synthetischen Werten: getrennte grüne Anzeigen, Icons, Zeit, Abmessungen und Stop in unverändert großer Leiste gesichtet. Keine echte Aufnahme gestartet.

Logs: `/tmp/Snaprivo-bestof-audio-{build,domain,video,sandbox,localization}.log`. Reale Tonquellen, Signal-/Bildsynchronität einer neuen Hardwareaufnahme und vollständige VoiceOver-Abnahme bleiben offen.

## A04 Video-Schnellvorschau

Nur erfolgreich finalisierte Aufnahmen öffnen die neue kompakte Vorschau mit Abspielen, Scrubber, MP4-Export und „Bearbeiten“. Die Bibliothekskarte öffnet weiterhin direkt den Editor. Unter Allgemein lässt sich der direkte Editor auch nach der Aufnahme dauerhaft einschalten. Standard ist die Schnellvorschau.

Ein beständiger Sheet-Container besitzt Player-Lebenszyklus und Kompositionsaufgabe. Der Wechsel in den Editor pausiert und behält dasselbe Modell, denselben AVPlayer, dieselbe Datei und die Position. Erst das Schließen des gesamten Sheets entfernt den Zeitbeobachter und beendet die Vorschau. Export verwendet unverändert den gemeinsamen validierten Exportpfad; es entsteht keine zweite importierte Aufnahme. Fremde oder nicht finalisierte Dateipfade werden nicht übernommen.

- Build, Videobibliotheks-/Neustartprüfungen, gespeicherte Einstellungs-/Neustartprüfungen und vollständige Video-/Export-/Neustartprüfung im Sandbox-Host: bestanden.
- Modellprüfungen bestätigen Schnellvorschau nach Aufnahme, Spieler-/Positionsübergabe, direkten Editor und Ablehnung eines fremden gleichnamigen Dateipfads.
- Native deutsche Prüf-App: synthetische Aufnahme per Stop beendet, kompakte Vorschau gesichtet, Abspielen und Scrubber bedient. „Bearbeiten“ übernimmt die gesetzte Position 0,6 s. Nach Schließen steht weiterhin genau ein Video in der Bibliothek; dessen Karte öffnet direkt den Editor. Die bestehende Pro-Sperre bleibt erkennbar. Der abschließende Build zeigt kontrastreiche aktive Aktionen auch im inaktiven Fenster. MP4 öffnet den nativen Sichern-Dialog; Abbrechen und anschließendes Schließen erhalten das Bibliotheksvideo.
- Lokalisierung: 1382 App-, 7 InfoPlist- und 19 Domain-Texte einschließlich des angepassten Aufnahmeabschlusses vollständig Deutsch/Englisch.
- Vollständige VoiceOver- und reale Aufnahmeabnahme werden damit nicht ersetzt.

Logs: `/tmp/Snaprivo-bestof-preview-{build,library,settings,sandbox,localization}.log`.

## A05 Zeitansicht – erster Teil

Gesamt/2×/4×/8× vergrößern ausschließlich die gemeinsame Zeitskala in einer horizontal scrollenden Ansicht. Der Abspielkopf wird beim Wechsel in die Mitte der sichtbaren Zeitansicht gebracht. Zwischenzeiten bleiben auch in vergrößerten Ausschnitten ablesbar. Es werden weiterhin höchstens acht kleine Quellminiaturen geladen. Keine Änderung an Datei-, Schnitt-, Export- oder Undo-Daten durch diese Ansichtsoption.

Build und vollständige Video-Sandbox-/Neustartregression bestanden. Zusätzliche Prüfungen bestätigen die Zeitskala aller vier Ansichten, native Mausbewegungen bei 8× mit verschobenem Griff sowie die weiterhin 0,1 s große Tastaturbewegung. Compiler-Abdeckung: 1385 App-, 7 InfoPlist- und 19 Domain-Texte vollständig Deutsch/Englisch. Die native Sichtprüfung des vollständigen scrollenden Editors ist noch offen: Der Mac war beim Öffnen des finalen Prüf-Builds erneut gesperrt. Operativer Gesamtpunkt A05 bleibt für diese Bedienprüfung, Teilstücke, Tempo/Lautstärke und manuelle Zoomabschnitte offen.

Logs: `/tmp/Snaprivo-bestof-timeline-{build,sandbox}.log`.

## A05 Zeitmontage und manueller Fokus

`VideoPlayback` beschreibt bis zu 64 entfernte Quellbereiche, globales Tempo 0,25×–4×, Lautstärke 0–100 % und bis zu 32 getrennte Zoomabschnitte. Zeiten und Fokuspositionen bleiben am dargestellten Original ausgerichtet. Die Domain kennt keine Aufnahme-/UI-Frameworks. Validierung begrenzt Werte und Mengen, lehnt überlappende Zooms ab und erhält mindestens ein Quellbild in der Auswahl. Entfernte Bereiche werden beim Hinzufügen vereinigt und lassen sich einzeln wieder einsetzen.

Eine unveränderliche AVComposition wird auf einem parallelen Executor aus dem Original aufgebaut. Audio und Video verwenden dieselben behaltenen Quellbereiche und dieselbe Skalierung. AVAudioMix übernimmt Lautstärke/Stille, der öffentliche Spectral-Algorithmus erhält bei Tempoänderung die Tonhöhe. AVPlayer, MP4 und GIF verwenden dieselbe Montage und denselben Core-Image-Fokus. Zooms verwenden eine weiche Ein-/Ausfahrt von höchstens 0,25 s je Seite; ihre Position ist vom linken oberen Rand des angezeigten Originals definiert. Die Ausgabe behält die Fläche und Gestaltung. Dies sind manuelle Abschnitte, keine automatische Cursorverfolgung.

Videoformat 5 speichert alle Bearbeitungen in einem gemeinsamen Zustand und migriert 1–4. Älter deklarierte Dateien mit neuen Zeitdaten werden zurückgewiesen. Undo/Redo, Konfliktschutz, Sicherung und Wiederherstellung erfassen die neuen Daten. Die Originalbytes bleiben unverändert.

Die Oberfläche ergänzt Tempo/Ton, innere Schnitte und Zoomabschnitte im vorhandenen scrollenden Videobereich. Ein Bereichspopover verwendet Originalzeit, Zoompositionen in Prozent und die Vergrößerung als Faktor. Übernehmen eines Zooms zeigt dessen Mitte, damit die Änderung unmittelbar beurteilbar ist. Entfernte Bereiche erscheinen farblich in der Quellzeitleiste; Ausgabedauer und Quellposition werden getrennt behandelt. Die rechte Eigenschaftenleiste des Bildeditors bleibt unverändert.

Die Vorschau behält während eines Aufbaus den gewünschten Quellzeitpunkt und wendet ihn erst auf das passende neue PlayerItem an. Ein fehlgeschlagener Aufbau darf keinen älteren Arbeitsstand abspielen. Zeitbeobachter erhalten je PlayerItem eine Generation; verspätete Meldungen ersetzter oder geschlossener Items werden ignoriert.

- Domain: 190 Swift-Testing- und 2 XCTest-Prüfungen bestanden, einschließlich Quell-/Ausgabezuordnung, Grenzwerte, Mengen, Zusammenführen, Fokuskurven und Migration.
- `./scripts/test-video-editing.sh --sandbox --playback`: echte MP4-/GIF-Zeiten, entfernte Bilder, Ton-/Bildmarke, Viertellautstärke und Stille, Fokus im oberen linken Farbquadranten, Undo/Redo, Wiederöffnen, Pro-Sperre, Backup, Abbruch vor Veröffentlichung und unveränderte Originaldateien bestanden. Der Fokus-Pixeltest fordert den exakten Zeitpunkt an; eine freie Keyframe-Auswahl wäre für eine zeitabhängige Kamera ungeeignet.
- Vollständige Video-/Export-/Neustartregression im Sandbox-Host sowie Bibliotheks-/Backup-/Dateigrenzen-/Unterbrechungsprüfungen bestanden. Zusätzliche Fälle prüfen ausstehende Quellpositionen, fehlgeschlagene Vorschau und geschlossene Player.
- Native Sprach-/Neustartprüfung bestanden; Compiler-Abdeckung: 1403 App-, 7 InfoPlist- und 19 Domain-Texte vollständig Deutsch/Englisch.
- Sichtbare Bedienprüfung des erweiterten Editors ist noch offen. Die bisherigen realen Capture-/Hardware-/VoiceOver-Grenzen gelten weiterhin.

Logs: `/tmp/Snaprivo-bestof-playback-{domain,build,sandbox,full-sandbox,library,validation,localization}.log`. Öffentliche API-Grundlage: [AVMutableComposition](https://developer.apple.com/documentation/avfoundation/avmutablecomposition), [Time pitch algorithms](https://developer.apple.com/documentation/avfoundation/time-pitch-algorithm-settings).

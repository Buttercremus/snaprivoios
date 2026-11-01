# Screen Studio als Referenz für Snaprivo

Stand: 1. November 2026. Analyse und Vorschläge auf Nutzerwunsch; keine Umsetzung dieser Erweiterungen. Referenz ist die installierte Screen-Studio-Version 4.1.0-5005.

## Ergebnis und Reihenfolge

Den größten Nutzen haben eine gestaltete Videoausgabe und klarere, ruhigere Zustandswechsel. Empfohlene Reihenfolge: Icon-Wechsel gezielt verfeinern, Video-Gestaltung samt Export ergänzen, danach Timeline und manuelle Zoomabschnitte ausbauen. Automatische Cursorführung folgt als eigener Aufnahme- und Renderausbau.

| Vorher in Snaprivo | Vorschlag | Nutzen |
| --- | --- | --- |
| Videoansicht mit schwarzer Vorschau, Transport und einem Schnittbereich | Größere Vorschau, Timeline unten und passende Einstellungen daneben; Export bleibt erreichbar | Mehr Arbeitsfläche und klare Orientierung |
| Video behält die originale Bildgestaltung | Hintergrundfarbe/Verlauf, Randabstand, Ecken, Schatten sowie Original/16:9/9:16/1:1 | Vorzeigbare Demos und Anleitungen mit wenigen Einstellungen |
| Nur Beginn und Ende eines zusammenhängenden Clips kürzbar | Timeline-Zoom, anschließend Teilstücke entfernen, Tempo und Lautstärke | Pausen und Fehler lassen sich gezielt bearbeiten |
| Keine gespeicherten Zoomabschnitte | Zunächst manuelle Fokusbereiche mit Anfang, Ende und weicher Kamerafahrt | Kleine Bedienelemente werden in Tutorials erkennbar |
| Auswahlanimation auf dem gesamten Werkzeug-HStack; Symbol- und Schriftgewicht ändern sich dabei | Animation auf die Auswahlmarkierung begrenzen, Symbolposition und optisches Gewicht stabil halten | Weniger optisches Wackeln beim Werkzeugwechsel |
| Play/Pause wechselt das SF-Symbol ohne ausdrücklich definierten Symbolübergang | Kurzer nativer Replace-Übergang bei Mausklick, später ebenso bei anderen echten Zustandswechseln | Der neue Zustand ist klar erkennbar |

Diese Vorschläge verwenden die bestehende rechte Eigenschaftenleiste und vorhandene native Komponenten. Der verworfene Glass-Kopf und die Glass-Formauswahl gehören nicht dazu.

## Was bei Screen Studio belegt ist

Die visuelle Sichtprüfung zeigt eine große Vorschau mit Formatwahl, eine seitliche Einstellungsnavigation sowie getrennte Clip- und Zoomspuren. Im geöffneten Editor sind Schatteneinstellungen und ein Zoomabschnitt mit automatischer Position sichtbar. Es wurden keine Projektparameter verändert und keine privaten Aufnahmen gespeichert.

Screen Studio beschreibt Hintergründe, Abstände, Schatten, Formatwahl sowie Schnitt und Tempo auf seiner [Produktseite](https://screen.studio/). Seine [Auto-Zoom-Anleitung](https://screen.studio/guide/auto-zoom) erklärt den Zusammenhang zwischen Zoomziel und aufgezeichneten Klickpositionen; die [Format-Anleitung](https://screen.studio/guide/aspect-ratio) beschreibt Original, Querformat, Hochformat und Quadrat.

REA hat das lokale Electron-ASAR inventarisiert und drei ausgewählte JavaScript-Dateien plus Paketmetadaten statisch analysiert. Die untersuchten Dateien enthalten Federparameter mit Masse, Steifigkeit, Dämpfung und Begrenzung sowie Einstellungs-/Timeline-Logik. Das stützt eine Architektur mit gezielt konfigurierten Bewegungen. Eine bestimmte Federkonfiguration wurde keinem konkreten Icon-Wechsel zur Laufzeit zugeordnet. Die bloße Existenz einer eingebundenen Animationsbibliothek beweist keine Nutzung ihrer einzelnen Effekte.

## Technische Konsequenzen für Snaprivo

### Icon-Wechsel als kleiner erster Schritt

- In `EditorToolPalette.swift` läuft die vorhandene 0,24-s-Auswahlfeder auf dem Werkzeug-HStack. Gleichzeitig verwendet `EditorToolbarLabel` für aktive Symbole und Beschriftungen andere Schriftgewichte. Die Buttonbreite ist bereits für beide Beschriftungsgewichte reserviert; diese stabile Geometrie beibehalten und die Bewegung enger auf die Markierung begrenzen.
- Werkzeugwechsel und Zustandswechsel unterscheiden: Zwischen Pfeil, Text und Formen wandert die Markierung. Play/Pause oder Ton an/aus dürfen ihr Symbol kurz ersetzen. Ein Vorschlagswert für die Beurteilung ist 160–200 ms ohne Überschwingen; dies ist kein gemessener Screen-Studio-Wert.
- Keine nachlaufende Bewegung bei Tastaturbedienung oder „Bewegung reduzieren“. Schnelle aufeinanderfolgende Mausklicks sollen vom aktuellen sichtbaren Zustand aus reagieren, ohne Animationswarteschlange.
- Abnahme an den drei Werkzeuggrößen, Überlauf, Deutsch/Englisch und reduzierter Bewegung. Symbol und Beschriftung müssen während und nach dem Wechsel lesbar bleiben. Das Bewegungsgefühl braucht einen sichtbaren Versuch mit schnellem Wechseln.

### Video-Gestaltung vor einer großen Schnitt-Timeline

`VideoEditorView.swift` zeigt heute einen `AVPlayerView` mit proportionaler Darstellung auf Schwarz. `VideoDocument` speichert Metadaten und einen optionalen Schnittbereich. Der MP4-Export in `VideoRecordingFiles.swift` wendet den Schnitt an; eine Video-Gestaltung oder Zoom-Komposition existiert dort noch nicht.

Für den ersten Videoausbau lassen sich die eigenen Gestaltungskonzepte aus `EditorPresentation` verwenden: Farben, Verläufe, Abstände, Ecken, Schatten und Seitenverhältnis. Die Bild-Renderfunktion kann dadurch nicht unverändert als Video-Renderer verwendet werden. Vorschau und MP4-/GIF-Ausgabe brauchen dieselbe zeitabhängige Kompositionsdefinition, damit die Ausgabe tatsächlich wie die Vorschau aussieht. Die Gestaltung muss versioniert gespeichert, rückgängig machbar und für alte Projekte standardmäßig neutral sein.

Prüfungen: synthetische Clips mit sichtbaren Eckenmarkierungen, Hoch-/Querformat, variable Quellabmessungen, Schnitt und Ton, identische Geometrie in Vorschau und Export, Abbruch sowie Lesen alter Projekte. Hintergrundbilder sollten erst nach der Grundfunktion ergänzt werden, einschließlich ihrer sicheren Dateiverwaltung.

### Timeline und manuelle Zoomabschnitte

Die heutige Timeline verwendet acht asynchron geladene Vorschaubilder und eine gemeinsame Koordinatenskala. Darauf kann eine vergrößerbare Zeitansicht aufbauen. Teilstücke, Geschwindigkeitsänderungen und Lautstärke brauchen anschließend ein erweitertes Schnittmodell und eine eindeutige Abbildung von Quellzeit auf Ausgabezeit; sie sind keine reine Oberflächenänderung.

Manuelle Zoomabschnitte sind unabhängig von nachträglich bearbeitbaren Cursorn möglich: Der Nutzer wählt Fokusbereich, Zeit und Stärke. Eine gemeinsame Transformationsberechnung muss Ausschnitt, weiche Übergänge, Schnittgrenzen und Ausgabeformate in Vorschau und Export identisch behandeln. Auto-Zoom kann später dieselbe Grundlage nutzen.

### Auto-Zoom und Cursor als eigener Ausbau

`VideoRecording.swift` verwendet `SCStreamConfiguration.showsCursor` und `showMouseClicks`. Cursor und Klickmarkierungen landen damit in den Videopixeln. `VideoDocument` speichert keinen separaten zeitlichen Cursor-/Klickpfad.

Eine nachträgliche Größenänderung, Glättung oder unabhängige Animation des Cursors benötigt künftig separat aufgezeichnete Ereignisse und eine eigene Cursor-Komposition. Für bestehende Clips fehlt diese Grundlage. Die Zulässigkeit und Zuverlässigkeit einer Ereigniserfassung unter App Sandbox und mit öffentlichen APIs muss gesondert geprüft werden; aus der Screen-Studio-Implementierung folgt keine Zusage für unseren Store-Build. Für präzisen Auto-Zoom reichen die bereits ins Bild gezeichneten Klickmarkierungen nicht als verlässliche gespeicherte Koordinatenquelle.

## Nachweise und Grenzen

- Installierte App: `/Applications/Screen Studio.app`, Bundle-ID `com.timpler.screenstudio`, Version `4.1.0-5005`.
- ASAR-SHA-256: `3664b31486eb44652152f4ab408180b5a13f999dce9f104b90ad84dd44d15359`.
- Statisch ausgewählt: `package.json`, `dist/CpXpNcFh.js`, `dist/Brm6UpoL2.js`, `dist/oLirRMcf2.js`. REA bestätigt die Integritätswerte dieser vier Einträge. Drei JavaScript-Dateien wurden ohne Parserfehler als Text analysiert, ohne den Bundle-Code auszuführen.
- Die Gesamtinventur meldet neun abweichende Integritätswerte bei ausgelagerten nativen Komponenten. Die weitere Inventur verwendet ausdrücklich `record-and-continue`; diese Komponenten bleiben als nicht verifiziert markiert. Die Ursache wurde nicht bestimmt. Die Aussagen oben benötigen deren Ausführung nicht.
- Die JavaScript-Analyse ist durch Auswahl und Graphbudgets partiell. Sie liefert keine vollständige Rekonstruktion der App und keinen Nachweis einer konkreten Animationsdauer oder Bildrate.
- REA-Nachweise: `/tmp/Snaprivo-ScreenStudio-Review/rea-evidence.json`; 7 Records, 43.888.843 Bytes. Rohdaten und fremde Ressourcen liegen außerhalb des Repositories. Die REA-Sitzung wurde anschließend geschlossen.
- Kein neuer App-Build erforderlich: Für diese Analyse wurde ausschließlich dieses Vergleichsdokument ergänzt.

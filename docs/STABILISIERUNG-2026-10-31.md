# Stabilisierung vom 31. Oktober 2026

Umfang: bestehende Editorbedienung, Fokus, Bild-/Anleitungswechsel, Mehrfachauswahl von Anleitungen und Absicherung der Speicher-/Exportabläufe. Keine neuen Videoeffekte und keine Änderung des beschlossenen Releaseumfangs. Die operative Aufgabenliste bleibt [ARBEITSPLAN.md](ARBEITSPLAN.md).

## Korrigiertes Verhalten

- **Zuständiger Tastaturfokus:** Der Canvas verarbeitet Tastenkürzel nur bei Fokus auf seiner Bildfläche, Schnellleiste oder Pipette und nicht für ein anderes Fenster. Insbesondere erreicht „Alles auswählen“ weiterhin das aktive fremde Textfeld, wenn noch ein inaktiver Inline-Texteditor im Bild existiert. Unterstützte Kurzbefehle prüfen auch die Modifikatoren; beispielsweise dupliziert ⌥⌘D kein Objekt. Native Textkürzel und ⇧⌘Z bleiben erhalten.
- **Schnellleiste:** Unbehandelte Tasten gehen über die Bildfläche weiter, obwohl Leiste und Canvas im transformierten Container nebeneinander liegen. Entf und Rücktaste entfernen die Auswahl. Auch Fokus auf untergeordneten nativen Views wird beim Schließen der Leiste an den Canvas zurückgegeben.
- **Aktives Vorschaubild erneut wählen:** Offene Text-/Stilbearbeitung wird abgeschlossen, der vorhandene Editor erhält den Fokus zurück und wird nicht neu geladen. Ein anschließender Wechsel sichert die bestätigten Textänderungen.
- **Laufende Mausgeste:** Undo, Redo und Löschen verändern weder Dokument noch Vorschau einer gehaltenen Größenänderung. Nach dem Loslassen lässt sich die abgeschlossene Geste mit einem Undo rückgängig machen. Schutzbedingungen liegen auch im Modell und gelten damit für direkte Aktionsaufrufe.
- **Textabschluss:** Beim Entfernen des Inline-Editors werden auch noch ausstehende Text-Erstellungs-/Auswahlgesten bereinigt. Escape bestätigt den Text weiterhin; anschließend blockiert kein zurückgebliebener Gestenzustand Undo oder Löschen.
- **Optisch stabile Wechsel:** Schnellaktionen links behalten während des Bildwechsels ihre Helligkeit; Mausaktionen sind trotzdem gesperrt und Aufnahme-Einstiege prüfen den Ladezustand. Vorschauleiste, bisheriges Bild und Speicherfehlerverhalten bleiben erhalten.
- **Anleitungswechsel:** Nach erneutem Nutzerbefund ist die erste Wechselkorrektur nachgebessert. Die native Split-/Listenstruktur wird beim Laden nicht mehr insgesamt aus dem Hit-Testing genommen; eine eigene transparente Fläche fängt weitere Inhaltsklicks ab. Die rechte Spalte behält ihren Container und ein Dokumentwechsel unterdrückt geerbte Listenanimationen. Import, Papierkorb und die Fensterleistenaktionen behalten ihre Helligkeit. Der bisherige Inhalt bleibt bis zur Übernahme stehen, ohne Ladepopup darüber. Eine kleine Anzeige im Listenkopf erscheint erst nach 250 ms und gehört zur jeweiligen Öffnungsanfrage. Aktionsschutz und Speicherfehler verhindern weiterhin parallele Änderungen.
- **Gemeinsamer erster Frame:** Die erweiterte Prüfung reproduzierte neue Texte vor leeren Bildplatzhaltern (`[25872, 0]` gezählte rote Bildsamples vor/nach der ersten Übernahme). Die ohnehin erforderliche Bildvalidierung bereitet jetzt außerhalb des MainActor kleine Übersichtsbilder sowie die ersten drei Detailbilder und ein mögliches Suchziel vor. Erst der fertige Stand wird veröffentlicht. Die Detailauflösung und die Zahl vorbereiteter Bilder begrenzen den Zusatzspeicher; andere Bilder bleiben beim Scrollen bedarfsgesteuert. Originale, Ausgabe und Speicherdaten ändern sich nicht.
- **Mehrere Anleitungen löschen:** Die native Liste bindet eine Auswahlmenge. ⌘-/Umschalt-Klick, Entf/Rücktaste bei Listenfokus, Papierkorbsymbol und Kontextmenü verwenden dieselbe wiederherstellbare Löschung. Der Inhalt zeigt bei Mehrfachauswahl die Anzahl; Export/Preview bearbeiten keine versteckte einzelne Anleitung. Suchbeginn verwirft eine Mehrfachauswahl, und während der Suche ist die Löschaktion ohne markierte normale Listenzeile gesperrt. Alle Ziele werden unter einer Dateisperre anhand ihrer Metadaten vorgeprüft, ohne Bilddaten zu laden. Details: [Anleitungsabnahme](ANLEITUNG-AUSGABE-ABNAHME.md).
- **Video-Kopfaktionen:** Aktive Symbole/Beschriftungen verwenden die primäre Systemfarbe, nicht verfügbare Aktionen die deaktivierte System-Textfarbe.

## Regressionen

Die neuen Tests haben vor den jeweiligen Korrekturen reproduzierbar Folgendes gemeldet:

1. `An inactive inline editor stole Select All from another text field`.
2. `Clicking the active thumbnail did not return focus to the editor`.
3. `Undo changed history or discarded a preview during a held resize`.

Die zuvor ergänzten Container- und Pixelregressionen reproduzierten außerdem die ausbleibende Löschung bei Schnellleistenfokus und das Aufblinken der Sidebar. Tastaturtests verwenden echte native Container mit benachbarten Views und synthetischen Ereignissen; Bildwechseltests verwenden die Produktionsansichten, angehaltene Ausgaben und temporäre Projekte. Es werden keine privaten Nutzerbilder als Fixtures gespeichert.

Die erste Anleitungsprüfung war zu eng: Sie verglich Import/Papierkorb nach 70 ms eines programmgesteuerten Öffnens. Sie deckte weder die spätere Ladeeinblendung über dem Inhalt noch eine Folge echter Listenklicks ab. Die Nachprüfung hält den Wechsel über 250 ms an und vergleicht den gesamten bisherigen Inhaltsbereich; zusätzliche native Klickfolgen prüfen mehrere gerenderte Frames einschließlich der sichtbaren synthetischen Schrittbilder. Das ist keine Messung der tatsächlichen Bildschirm-Framerate oder der Liquid-Glass-Compositorausgabe.

## Prüfstand

Ausführung auf dem Entwicklungs-Mac: macOS 27.0, arm64, Xcode 27.0 (27A266a), Swift-6-Sprachmodus. Die Sandbox-Prüfungen verwenden eigene ad hoc signierte Testhosts.

| Prüfung | Ergebnis |
| --- | --- |
| `./scripts/test.sh` | 178 Domain-Tests bestanden; zusätzlich Mehrfach-Papierkorb, Wiederherstellung aller Bilder und vollständige Vorabprüfung fehlender/veralteter Ziele |
| `./scripts/test-canvas.sh` | Bestanden: vollständiger Container, Inline-Text, Fokusbereiche, genaue Modifikatoren, Entf/Rücktaste und gehaltene Gesten |
| `./scripts/test-workflow-polish.sh` | Bestanden: Fokus bei erneutem Auswählen, stabile Pixel während des Bildwechsels, ausstehende Ausgaben und Fehlererhalt |
| `./scripts/test-guide-navigation.sh` | Bestanden: kompletter bisheriger Inhalt auch bei langsamem Wechsel pixelgleich, erster neuer Frame mit Bildpixeln, wiederholte native Listenklicks über mehrere Frames, stabile Toolbar-Bedingungen, Listenmehrfachauswahl, beide Löschtasten, Textfeldschutz, Wiederherstellung und Abbruch bei Speicherfehlern/Suche |
| `./scripts/test-guides.sh --sandbox` | Bestanden: begrenzte Vorschaugrößen/-anzahl, Suchzielvorbereitung, Schutz vor veralteten Vorschauen und Validierung späterer Schritte; außerdem PDF/Markdown, Datenschutz, Autosave/Neustart, Undo, Papierkorb und große unveränderte Bildbestände |
| `./scripts/test-autosave.sh` | Bestanden: Autosave, Wiederöffnen, Retry und Konfliktkopien |
| `./scripts/test-capture.sh` | Bestanden: synthetische Auswahl-, Koordinaten-, Eingabe- und Overlay-Regressionsfälle |
| `./scripts/test-video-editing.sh --sandbox` | Bestanden: synthetischer Schnitt/AAC/Export, Timeline und Prozessneustart im Sandbox-Host |
| `./scripts/test-transfer-privacy.sh` | Bestanden: bestätigte Bildstände, deckende Exportpixel, ausstehende Ausgaben, Fehlerbestätigung und unveränderte Exportziele bei Fehlern |
| `./scripts/test-release-workflows.sh --sandbox` | Bestanden: Gesamtsicherung/Restore, Papierkorb, beschädigte Dateien, Finder-Routing, Free/Pro und simulierte Kaufzustände |
| `./scripts/build.sh` | Bestanden: regulärer Debug-App-Build am normalen Xcode-Ausgabeort, einschließlich Swift-Typprüfung und Signierung |

Swift-Typprüfung erfolgt mit dem App-Build. Ein separater Coverage-Prozentsatz wird nicht behauptet; die nativen Prüfrunner verwenden konkrete Zustands-, Datei- und Pixelassertionen.

Alle aufgeführten Prüfläufe haben erfolgreich abgeschlossen. Der Build meldet lediglich die übersprungene App-Intents-Metadatenextraktion, da die App keine `AppIntents.framework`-Abhängigkeit hat; keine Compilerfehler. Eine separate Swift-Lint-Prüfung wurde nicht ausgeführt; die Whitespace-Prüfung erfolgt mit `git diff --check`.

Diff- und Whitespace-Prüfung sowie Scan neu hinzugefügter Swift-Zeilen auf typische private Schlüssel/Token ohne Befund. Keine neuen Abhängigkeiten, Berechtigungen oder privaten APIs. Eine durch parallele Quelländerung abgebrochene Exportkompilierung wurde mit unverändertem Modell erfolgreich wiederholt.

## Verbleibende Abnahme

Dieser Durchlauf ersetzt keine physische Tastatur-/VoiceOver-Abnahme, macOS-26-/Mehrdisplayprüfung oder echte Daueraufnahme mit Audio. Offen bleiben insbesondere die bereits in Q01–Q05 und V04 geführten Hardware-/Releasefälle: reale Scroll-Seiten, Audio-/Gerätewechsel und 15-Minuten-Synchronität. Der neue Build muss für eine Bedienprüfung neu gestartet werden; ein bereits laufender Prozess erhält keine Codeänderungen durch das Bauen.

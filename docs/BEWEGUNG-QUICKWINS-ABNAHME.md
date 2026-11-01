# Bewegung und Bestätigungen – Quick Wins

Stand: 1. November 2026. Vom Nutzer nach der Design-Analyse (Vergleich mit CleanShot und Screen Studio) beauftragt: zuerst die kleinen Animations- und Liquid-Glass-Verbesserungen. Sicherung des vorherigen Arbeitsstands: Branch `backup/vor-quickwins-2026-11-01` (HEAD, Index und Arbeitsverzeichnis blieben dabei unverändert, weil parallel ein weiterer Agent arbeitete).

## Verhalten

- **Kopieren im Editor:** Das Symbol verwandelt sich per SF-Symbol-Replace von „Kopieren“ in das Häkchen statt zwei Beschriftungen überzublenden. Beide Zustände reservieren weiterhin ihre Breite; benachbarte Buttons verschieben sich nicht. Animiert nur bei Klick auf den Button, nicht bei automatischem Kopieren und nicht bei reduzierter Bewegung.
- **Kopiert-Häkchen in der Schnellvorschau:** Das Häkchen zeichnet sich mit dem SF-Symbol-Effekt „Draw On“ ein (macOS 26). Reduzierte Bewegung zeigt es sofort. Das Schließen der Miniaturen bleibt ohne Animation (Entscheidung vom 27. Oktober 2026).
- **Werkzeugauswahl im Editor:** Die blaue Markierung gleitet nach einem Mausklick mit einer gedämpften Feder (`response 0.24`, `dampingFraction 1`) zum neuen Werkzeug, wie die Auswahl der Schnelloptionen. Tastenkürzel, VoiceOver und programmatische Wechsel bleiben sofort. Die Bildfläche nimmt nicht teil.
- **Haptik beim Einrasten:** Rastet ein verschobenes Objekt an einer neuen Kante oder Mitte ein, gibt das Force-Touch-Trackpad einen kurzen Ausrichtungsimpuls (`NSHapticFeedbackManager`, `.alignment`). Gehaltenes Einrasten bleibt still; ⌥ und ausgeschaltetes Einrasten erzeugen keinen Impuls. Ohne Force-Touch-Trackpad passiert nichts.
- **Video-Countdown:** Während des Vorlaufs steht mittig in der Quelle eine große, klickdurchlässige Liquid-Glass-Kreisfläche mit der verbleibenden Sekunde. Die Ziffer zählt mit `numericText(countsDown: true)` herunter; die erste Sekunde erscheint ohne Übergang. Kleine Quellen erhalten eine kleinere Fläche (64–112 pt), teilweise außerhalb liegende Quellen behalten sie auf dem Display. Bei verschobenem Fenster folgt sie der Quelle. Vor dem Streamstart, bei Abbruch, Fehler und Schließen ist sie ausgeblendet; wie alle eigenen Fenster ist sie zusätzlich aus der Aufnahme ausgeschlossen. VoiceOver erhält weiterhin die vorhandene Ansage je Sekunde.
- `EditorMotion` liegt jetzt in `EditorToolPalette.swift` und bietet `panel` und `selection`; beide animieren nur bei Mausbedienung und nie bei reduzierter Bewegung.

## Bewusst zurückgestellt

- **Zentrale Bewegungswerte für die ganze App:** Berührt Dateien, die der parallele Agent gerade ändert (`WorkspaceView`, `EditorQuickOptions`, `GuideView`), sowie `project.pbxproj` und mehrere Testskripte. Nach Abschluss der parallelen Arbeit nachholen.
- **REC-Punkt als SF-Symbol:** Der vorhandene Puls respektiert reduzierte Bewegung bereits und ist durch `VideoCountdownChecks` abgedeckt; ein Austausch brächte kaum sichtbaren Gewinn.

## Prüfung

- `./scripts/build.sh -derivedDataPath build/QuickWinsBuild`: erfolgreicher Debug-Build; keine Fehler oder Warnungen in den geänderten Dateien. Eigener DerivedData-Ordner, weil parallel ein weiterer Build lief. Der Build enthält auch die noch nicht abgeschlossene Arbeit des parallelen Agenten.
- `./scripts/test.sh`: 183 Domain-Tests bestanden.
- `./scripts/test-video.sh`: alle Video- und Berechtigungsprüfungen bestanden. `VideoCountdownChecks` prüft jetzt zusätzlich die Badge-Geometrie (zentriert, 64–112 pt, auf dem Display gehalten), die sichtbare, klickdurchlässige Badge mit der richtigen Sekunde bei 3 und 5 Sekunden Vorlauf sowie ihr Verschwinden vor der Aufnahme, nach Abbruch in der ersten und letzten Sekunde und beim Schließen.
- `./scripts/test-editor-toolbar.sh`: Werkzeugleiste mit drei Größen, Überlauf und Anpassung bestanden (Deutsch und Englisch).
- `./scripts/test-canvas.sh`: alle Canvas-Prüfungen einschließlich Einrasten, ⌥-Umgehung, Mittenausrichtung und gleicher Abstände bestanden.
- `./scripts/test-quick-capture-integration.sh`: bestanden.

Keine Prüfung auf einem echten Mac mit Force-Touch-Trackpad, keine reale Videoaufnahme mit Countdown über fremden Apps und keine VoiceOver-Abnahme in diesem Auftrag.

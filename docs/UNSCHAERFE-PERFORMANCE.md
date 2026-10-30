# Flüssigere Unschärfe-Vorschau

Stand: 25. Oktober 2026. Anlass: ruckelndes Verschieben einer Unschärfefläche. Die vom Nutzer beschriebenen etwa 2 FPS sind eine Beobachtung, keine hier gemessene Display-Bildrate.

## Messaufbau und begrenzter Umfang

Optimierte Operation: Aktualisieren eines verschobenen Filterrechtecks. Metrik: Renderzeit pro Schritt, Median und p95. Synthetisches 3840 × 2160-Bild, 600 × 280-Filterfläche, Stärke 24, Weich/Pixel/Mosaik, 16 Positionen mit 14 Pixel Abstand; die ersten zwei Messungen werden verworfen. Jede Messung erzeugt weiterhin einen vollständigen 4K-Ausgabepuffer. Es werden keine echten Screenshots gelesen oder gespeichert.

Zwei Varianten: wiederverwendeter Core-Image-Kontext, danach vorberechnete Quellpixel mit beweglicher Maske. Keine zusätzlichen Abhängigkeiten, kein externer Dienst, keine Formatmigration. Korrektheitsgrenze: Vorschau und Export stimmen innerhalb der üblichen 8-Bit-Farbrundung überein; unverdeckte Quellpixel, deckende Masken, History und Persistenz bleiben korrekt. Vorschautexturen werden auf rund 65 MB begrenzt.

## Gemessene Varianten

| Variante | Weich, Median | Pixel, Median | Mosaik, Median | Ergebnis |
| --- | ---: | ---: | ---: | --- |
| Ausgangspfad, erste Messung | 22,86 ms | 18,60 ms | 19,03 ms | Vollbild + neuer Kontext pro Schritt |
| Wiederverwendeter Kontext | 6,10 ms | 5,30 ms | 5,48 ms | Kontextaufbau entfällt |
| Ausgangspfad, reproduzierte Messung | 20,32 ms | 17,86 ms | 20,12 ms | Eingefrorener alter Pfad im Benchmark |
| Vorberechnete Maske, Lauf 1 | 3,90 ms | 3,87 ms | 3,95 ms | p95 4,03 / 4,03 / 4,10 ms |
| Vorberechnete Maske, Lauf 2 | 3,90 ms | 4,04 ms | 4,00 ms | p95 4,18 / 4,12 / 4,32 ms |

Die vorberechnete Variante ist in dieser Messung etwa fünfmal schneller als der Ausgangspfad. Die Vorbereitung der Reserve benötigt nach Aufwärmen des Filterkontexts rund 2–4 ms. Die 16 folgenden Zeichenläufe verwenden ausschließlich diese Reserve, ohne erneuten Filteraufruf. Der Benchmark misst diesen Zeichenpfad direkt; er zählt nicht die vorsorglichen Nachladejobs der App. Das sind Renderzeiten auf dem Prüfmac, keine garantierte FPS-Zahl für komplette Fenster, beliebige Bildgrößen oder andere Macs.

## Umsetzung

- Der gemeinsame `CIContext` behält seinen aufwendigen internen Zustand. [Apple beschreibt Kontextwiederverwendung und Thread-Sicherheit](https://developer.apple.com/documentation/coreimage/cicontext).
- Ein Hintergrundjob berechnet einen Bereich mit 256 Quellpixeln Reserve um die Filterfläche. Native Mausbewegungen verschieben anschließend nur deren Schnittmaske. Innerhalb von 96 Pixeln vor dem Reserverand wird nachgeladen; neuere Positionen ersetzen überholte Anforderungen statt eine Jobwarteschlange aufzubauen.
- Pro Objekt bleiben höchstens zwei vorbereitete Bereiche bzw. Stile verfügbar. Der Cache ist auf rund 65 MB begrenzt. Das Pixelbudget wird auf die vorhandenen Unschärfeflächen verteilt. Sehr große Live-Filterflächen können dafür eine kleinere Vorschautextur verwenden; Bildinhalt außerhalb der Filterfläche bleibt in Originalauflösung. Der Export filtert weiterhin in voller Quellauflösung.
- Noch nicht vorbereitete Teile bleiben vorübergehend deckend. Bereits fertige Pixel bleiben bei Stärke-/Stilwechsel sichtbar; der freigegebene frühere Bildbereich wird beim Verschieben sofort aus dem Original gezeichnet. Deckende Abdeckungen bleiben über den Filtern.
- Vorschau und Export verwenden denselben Filter mit einer Sampling-Reserve, bevor das sichtbare Rechteck ausgeschnitten wird. Das verhindert abweichende Pixel-/Mosaikwerte direkt an bewegten Maskenrändern. GPU-Ergebnisse werden im Hintergrund fertig gerendert und nicht erst im nächsten AppKit-Zeichenschritt ausgewertet.
- Beim Bildwechsel werden die neuen Bereiche vorbereitet und mit dem neuen nativen Canvas übernommen. Es werden keine Vorschautexturen im Projekt gespeichert. Die Änderung lässt sich ohne Datenmigration zurücknehmen.

## Reproduzieren und prüfen

```sh
./scripts/benchmark-blur-drag.sh --legacy
./scripts/benchmark-blur-drag.sh
./scripts/test-blur-styles.sh
./scripts/test-workflow-polish.sh
./scripts/test-canvas.sh
./scripts/test.sh
./scripts/build.sh -derivedDataPath build/CleanShotBuild
```

Der Legacy-Schalter existiert ausschließlich im synthetischen Benchmark. Die Pixelprüfung erfasst alle drei Stile, mehrere Stellen einschließlich der Maskenränder und die Wiederherstellung vorher bedeckter Quellpixel. Zusätzlich wird ein großes Vorschaurechteck auf Einhaltung seines Pixelbudgets geprüft. Der native Filtertest liest die gezeichneten Pixel direkt nach aufeinanderfolgenden Mausereignissen ohne Wartezeit auf neue Filterjobs und prüft einen gemeinsamen Undo-Schritt. Filmstreifenprüfungen decken den ersten vorbereiteten Bildaufbau und Tastaturfokus ab.

Eine echte Drag-Aufzeichnung mit Display-/Frame-Timing ist hierdurch nicht ersetzt. Insbesondere sehr große Flächen, viele gleichzeitig sichtbare Filter und weit über die Reserve springende Mausbewegungen können weiterhin Nachladeaufwand verursachen.

Lokale Regression: vollständiger App-Build, 164 Domain-Tests, native Unschärfeprüfung mit unmittelbaren Pixelabfragen nach Mausereignissen, vollständige Canvas-Suite und Text-/Bildwechsel-/Filmstreifenprüfungen erfolgreich. Sprachkataloge: 1175 App-, 7 InfoPlist- und 18 Domain-Einträge in Deutsch/Englisch mit Compilerabdeckung geprüft.

Zusätzlich wurde die Pixelmaske in einer separat gestarteten nativen Prüfansicht mit synthetischen Inhalten per Maus verschoben. Die neue Position und die sofortige Wiederherstellung des zuvor überdeckten Originalbereichs sind bestätigt (`build/blur-drag-native-ui.png`). Das ist eine Bedienprüfung, keine FPS-Aufzeichnung.

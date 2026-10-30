# Bibliotheksbild öffnen – Messung und ruhiger Status

Stand: 26.10.2026.

## Ursache und Änderung

Der zentrale Hinweis „Projekt öffnen …“ wurde bei jedem `isLoading` unmittelbar eingeblendet. Die gesamten Kacheln wurden zusätzlich deaktiviert und dadurch abgedunkelt. Schon ein kurzer Vorgang erzeugte deshalb einen sichtbaren Ladeblitz. Das Öffnen liest und validiert das Projekt, dekodiert die PNG-Pixel und bereitet gegebenenfalls Filter, eingefügte Bilder und Hintergrund vor. Das bisherige Bild muss zudem Änderungen und begonnene Ausgaben abschließen.

Gezielte Projektöffnungen haben jetzt eine eigene Zielkennung. Die Bibliothek bleibt sichtbar, bis das vollständige neue Modell bereitsteht; ein kleiner Indikator erscheint erst nach 250 ms auf der angeklickten Kachel. Die Bilder behalten ihre normale Darstellung; weitere Öffnungs-/Änderungsaktionen sind währenddessen weiterhin gesperrt. Speicherortwechsel, Import und Sicherungsübertragungen behalten ihre eigenen Statusanzeigen. Fehler lassen den bisherigen Editor und die Bibliothek erhalten und geben den Ladezustand wieder frei.

Die unabhängige Vorbereitung des nächsten Bilds beginnt während des Abschließens/Sicherns des bisherigen Editors. Veröffentlicht wird das Zielmodell erst nach erfolgreichem Abschluss beider Arbeiten. Auch ein früher Lesefehler wartet auf den begonnenen Sicherungsauftrag. Die vollständige Vorbereitung der ersten sichtbaren Filterpixel bleibt erhalten; keine vorübergehend unverpixelten Bildbereiche. Keine neue Abhängigkeit, kein zusätzlicher Originalbild-Cache und keine Formatänderung.

## Vergleich

macOS 27.0, Swift 6, ohne Optimierungsflag, synthetisches PNG mit 3840 × 2160 Pixeln, zwei wechselnd geöffnete Projekte je Fall. Filterfall: drei Unschärfearten. Fall mit ungesicherten Änderungen: 30 Pfeile im bisherigen Bild. Ein eigener temporärer Speicherordner und eigene Einstellungen; lokale Bildtextindexierung deaktiviert. Kein Zugriff auf Nutzerbibliothek oder Desktopbilder.

Messgröße: `WorkspaceModel.openProject` bis Modell und Ladezustand fertig sind, Polling alle 1 ms. Je Fall zwei erste Öffnungen, danach zwölf Warmöffnungen. Ausgangsbinärdatei und Variante wurden zusätzlich abwechselnd zweimal ohne parallele Builds ausgeführt. Die Übersicht verwendet diese Wiederholungen.

| Fall | Ausgangsmedian, Wiederholung 1 / 2 | Parallel, Wiederholung 1 / 2 | Bewertung |
| --- | --- | --- | --- |
| Unverändertes 4K-Bild | 20,07 / 19,15 ms | 18,98 / 20,80 ms | gleich schnell innerhalb der Schwankung |
| Drei vorbereitete Filter | 55,29 / 55,45 ms | 55,32 / 55,20 ms | gleich schnell |
| Bisheriges Bild mit ungesicherten Änderungen | 53,41 / 52,54 ms | 33,57 / 33,16 ms | rund 37 % kürzere Vorbereitung |

Das unabhängige Aufschlüsseln eines normalen Bilds ergab rund 0,4–0,9 ms für Lesen/Validieren und 16–20 ms für PNG-Dekodierung. Die erstmalige Filtervorbereitung enthält zusätzlichen Core-Image-Aufwand. Das erklärt reale Arbeit, aber kein pauschal „langsames“ Öffnen: Ein sofortiger modaler Ladehinweis fiel selbst bei wenigen Zehnmillisekunden auf. Die Statusänderung selbst wird hier nicht als Zeitersparnis ausgegeben.

Keine Messung vom Mausklick bis zum ersten gezeichneten Editorframe. Die Dateien wurden zuvor erstellt/gelesen; die ersten Öffnungen sind kein echter kalter Datenträgertest. Zwölf Warmöffnungen erlauben keine belastbare p95/p99-Aussage. Größere Bilder, viele eingebettete Bilder/Filter, langsame externe Speicher und Systemauslastung können länger dauern.

## Reproduktion und Grenzen

```sh
./scripts/benchmark-project-opening.sh
./scripts/test-workflow-polish.sh
./scripts/build.sh -derivedDataPath build/LibraryOpeningBuild
./scripts/test.sh
```

Der Benchmark liegt in `Tests/ProjectOpeningBenchmark.swift`. Die vor der Änderung kompilierte Binärdatei bleibt lokal als `build/ProjectOpeningBenchmark/ProjectOpeningBaseline` erhalten. Logs: `build/project-opening-baseline.log`, `build/project-opening-parallel.log` sowie `build/project-opening-{baseline,parallel}-repeat-{1,2}.log`.

Der Vergleich wurde bewusst auf einen Ansatz begrenzt: unabhängige Vorbereitung überlappen. Ein zusätzlicher Speicher-Cache wurde für die bereits kurzen unveränderten Öffnungen nicht eingeführt. Zurücksetzen der Parallelisierung auf die vorherige serielle Reihenfolge und der zielbezogenen Fortschrittsanzeige ist lokal möglich; keine Datenmigration.

Die Workflow-/Filmstreifenprüfung kontrolliert weiterhin vorbereitete erste Bildpixel, Export-Eigentümerschaft, ungesicherte Änderungen, konkurrierende Schreibvorgänge und wiederherstellbaren Papierkorb. Zusätzlich prüft sie jetzt das genaue Ladeziel, erhaltene Bibliotheksansicht bis zur Freigabe, Rücksetzen nach Erfolg/Speicherfehler und den fehlgeschlagenen Zugriff auf ein nicht vorhandenes Projekt. Der abschließende App-Build in `build/LibraryOpeningBuild` besteht. Die vollständige native Workflow-/Filmstreifensuite einschließlich der neuen Ziel-/Fehlerprüfungen und 164 Domain-Tests bestehen ebenfalls. Logs: `build/project-opening-build.log`, `build/project-opening-workflow.log`, `build/project-opening-domain.log`. Die laufende Nutzer-App wurde nicht überschrieben oder neu gestartet. Kein neuer Nachweis einer vollständigen manuellen Bibliotheksbedienung oder des ersten dargestellten Frames auf einem realen Nutzerprojekt.

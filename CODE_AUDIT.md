# Code-Audit — Snaprivo

Stand: **01.11.2026**, Commit `58e5c2c` einschließlich des aktuellen, nicht eingecheckten Arbeitsbaums und der transparenten Scroll-Fenster. Geprüft wurden Capture-/Task-Lebenszyklen, Editor/Renderer, Anleitungen und Textassistent, Videoausgabe, Datei-/Persistenzpfade und native UI. Methode: frischer vollständiger Debug-Build, drei getrennte statische Prüfdurchgänge und gezielte synthetische Reproduktionen. Befundnummern bleiben stabil. Die vorherige Berichtsfassung liegt unter `build/Audit20261101/CODE_AUDIT-before.md`.

**Ergebnis nach der Korrekturrunde: Alle fünf bestätigten Fehler und die zusätzliche Low-Optimierung sind behoben.** Die Befundnummern bleiben erhalten. Der ursprüngliche Audit-Nachweis steht in §12.13, die anschließende Umsetzung und Abschlussprüfung in §12.14. Frühere geschlossene Befunde bleiben geschlossen; die Aussage bezieht sich auf diese bestätigten Fälle, nicht auf sämtliche möglichen Fehler.

Kein neuer Critical- oder High-Befund wurde bestätigt. Die Aussage gilt für die geprüften Pfade und ist keine vollständige Fehlerfreiheitserklärung. Tatsächliches Store-Archiv und reale macOS-26-/Capture-/Audio-/VoiceOver-Abnahme bleiben gesondert (§11). Es wurden ausschließlich synthetische Fixtures verwendet; keine Benutzerbibliothek verändert und nichts veröffentlicht.

## 1. Executive summary

1. **[Behoben] Kurze GIF-Schnitte verlieren Bewegung am Ende** — §5.4 — `Snaprivo/Capture/VideoRecordingFiles.swift:280`.
2. **[Behoben] Verworfener Textvorschlag kann trotzdem eine Generierung starten** — §3.4 — `Snaprivo/App/GuideAssistantModel.swift:98`.
3. **[Behoben] Gelöschte Anleitungsschritte behalten Vorschläge und Bildstände im Speicher** — §7.6 — `Snaprivo/App/GuideAssistantModel.swift:26`.
4. **[Behoben] Geschweifte Klammern schneiden gültigen Anleitungstext ab** — §5.5 — `Snaprivo/App/GuideAssistantService.swift:410`.
5. **[Behoben] Pin-Aktionen sind per Tastatur und VoiceOver nicht erreichbar** — §8.7 — `Snaprivo/Features/PinnedImage.swift:70`.

Auch die Kontextwiederverwendung für wiederholte Hintergrund-Unschärfe (§7.7) ist umgesetzt. Die bereits geschlossenen Export-/Beenden-, Formen-, Video-Menü-, Guide-Asset-, Datenschutzlink- und Skriptbefunde bleiben geschlossen.

### 1.1 Historische Beta-Befunde und Korrekturen

Die stabilen Nummern bleiben erhalten. Die vor den Korrekturen erneut reproduzierten Fehler stehen in der gesicherten Momentaufnahme. Geschlossene Befunde sind unten ausdrücklich als behoben markiert. Frühere Kauf-/Restore- und Store-Vorbereitungsabnahmen des Nutzers bleiben anerkannt; der lokale Release-Build ersetzt die Prüfung des tatsächlichen Store-Kandidaten nicht.

## 2. Quick wins

Die sechs Korrekturen sind umgesetzt. Die Regressionen prüfen insbesondere angehaltene Verfügbarkeitsantworten, Verwerfen/Ersetzen, Entfernen und Undo, echte GIF-Frames eines kurzen Schnitts sowie native Pin-Fokus- und Accessibility-Aktionen (§12.14).

### 2.1 Copyright vor dem ersten Upload ergänzen

_REMOVED: Im früheren Audit als korrigiert dokumentiert. Release-Metadaten und App Store Connect wurden in dieser Prüfung nicht erneut abgenommen; kein aktueller offener Codebefund._

## 3. Concurrency

Der frische App-Build enthält keine Swift-Concurrency-Warnungen. Die folgenden Befunde betreffen Laufzeitverhalten, das der Compiler nicht beanstandet.

### 3.1 Geschlossene Schnellvorschau fällt aus der Export-/Beenden-Verwaltung

_REMOVED: Behoben am 29.10.2026._ Geschlossene und verdrängte Vorschauen übergeben ihre Speicher-/Exportarbeit an eine vom Workspace verwaltete Sammlung. Beenden, Bibliothekswechsel und Transfer warten diese einschließlich nachträglicher Dismissals ab. Der UI-Callback erhält das sofortige Miniaturschließen. Hintergrundfehler öffnen den bestehenden Workspace-Dialog; erst `acknowledgeImportError()` bestätigt sie, bloßes Zurücksetzen von `importError` reicht nicht. Regressionen mit zwei unabhängig angehaltenen Writern, Fehler/Bestätigung und angehaltenem Bibliothekswechsel bestehen: `Tests/QuickCaptureIntegrationChecks.swift`, `build/ReleaseFixes/Capture/quick-capture-library-gated.log`.

### 3.2 Bibliothekssperre wartet ohne eigene Deadline

_REMOVED: Behoben am 29.10.2026._ `ProjectStore` erwirbt die OS-Sperre mit `LOCK_NB`, monotoner Drei-Sekunden-Deadline und kooperativem Abbruch vor jedem Versuch, auch bei `EINTR`, sowie vor der geschützten Operation. Ein belegter Store meldet den lokalisierten Fehler `ProjectError.libraryBusy`. Abbruch/Timeout veröffentlicht keine Projekt-Halbtransaktion; nach Freigabe bleibt der Store nutzbar.

- **Ort:** `Packages/SnagForgeDomain/Sources/SnagForgeDomain/ProjectStore.swift:58`; Fehler in `ProjectDocument.swift`, Domain-Übersetzungen de/en.
- **Nachweis:** Domain-Tests mit unabhängig gehaltenem OS-Lock, kurzer Testdeadline, Cancellation, unverändertem Projektbestand und anschließend erfolgreichem Create/Load. `build/AuditFinalFixes/domain.log`.

### 3.3 Bookmark- und Verzeichniszugriffe laufen synchron auf dem MainActor

_REMOVED: Behoben am 29.10.2026._ Der produktive Bookmark-Weg löst Freigaben, Verzeichnisattribute und stale-Erneuerung im Hintergrund auf. Security-Scoped Access beginnt vor dem Dateizugriff und bleibt bis zur Freigabe des übernommenen Grants aktiv. Während der Wiederherstellung verhindern Readiness und bestehende Fehlerguards Zugriffe auf eine unbeabsichtigte Defaultbibliothek. Leere Einstellungen sind sofort bereit; fehlende/beschädigte Bookmark- oder Pfadwerte bleiben gesperrt. Parallele Aufrufer warten dieselbe Wiederherstellung ab. Generation und Cancellation verhindern späte Übernahme nach `endAccess`; nicht übernommene Grants werden beendet. Die Ordnerauswahl verwendet `prepareAsync` mit ausgeglichenem initialem und aufgelöstem Scope.

- **Ort:** `Snaprivo/App/StorageLocations.swift:82`, `Snaprivo/App/StorageLocations.swift:213`; Integration in `WorkspaceModel.refreshLibrary` und Ordnerauswahl.
- **Nachweis:** Einstellungen, echte Bookmark-Restoration, kanonischer `/var`-/`/private/var`-Ordnervergleich, beschädigte/fehltypisierte Werte, parallele verzögerte Restoration bei verfügbarem MainActor und Abbruch vor Veröffentlichung; bestehende Tests für Scope-Balance, Bibliothekskopie/Undo/Neustart und Transfer bestehen. `settings.log`, `library.log`, `transfer-privacy.log` unter `build/AuditFinalFixes/`. Ununterbrechbare Betriebssystemaufrufe können im Hintergrund bis zur Rückkehr laufen; sie blockieren die UI nicht.

### 3.4 Verwerfen beendet die Vorbereitung eines Inline-Vorschlags nicht

_REMOVED: Behoben am 01.11.2026._ Das Modell besitzt die vorbereitende Task und beendet sie in `cancel()`. Zusätzlich prüft `prepare()` nach dem Await die Anfragegeneration, sodass auch eine verspätete, nicht kooperative Verfügbarkeitsantwort keine verworfene Anfrage mehr startet. Der Bereitschafts-Wartepfad ist kooperativ abbrechbar. Ein bewusster neuer Versuch bleibt möglich; geänderte Hinweise während der Prüfung lassen die Verfügbarkeit nicht im Prüfzustand hängen.

- **Ort:** [GuideAssistantModel.swift:98](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/GuideAssistantModel.swift:98), `prepare()`, `cancel()`.
- **Nachweis:** Angehaltene Verfügbarkeit mit Abbruch, Verwerfen und Ersetzen; keine unsichtbaren Serviceaufrufe, Freigabe alter Modelle und erfolgreicher expliziter Neustart. [GuideAssistantChecks.swift:319](/Users/simon/Woerk/Swift/Snaprivo/Tests/GuideAssistantChecks.swift:319); §12.14.

## 4. API modernity

_Keine neuen belastbaren Befunde._ Im frischen Debug-Build gab es keine Swift-Deprecation-Warnungen. Die einzelne Meldung des AppIntents-Metadatenwerkzeugs („Metadata extraction skipped“) betrifft die fehlende AppIntents-Abhängigkeit und ist für sich kein Funktionsfehler.

Keine Migration allein wegen eines älteren, weiterhin unterstützten API-Namens empfohlen. Die Prüfung ersetzt keine komplette API-Verfügbarkeitsprüfung auf macOS 26.

## 5. Bugs / logic errors

### 5.1 Byte-Grenzen greifen nicht vor allen lokalen Bild-/Paket-Reads

_REMOVED: Der aktuelle Stand prüft lokale Paket-/Dateilesungen über begrenzte Lesewege und validierte Dateigrößen. Die aktuellen Domain-Tests zu Dateigrenzen bestehen. Die alte pauschale Aussage ist damit überholt; die ergänzten Raster-Arbeitsgrenzen stehen separat in §7.3._

### 5.2 Versteckte Video-Arbeitsdateien nach Crash werden nicht wiederaufgenommen

_REMOVED: Neue Aufnahmen besitzen inzwischen einen persistierten Wiederherstellungszustand. Der frühere allgemeine Befund trifft auf den aktuellen Aufnahmeweg nicht mehr zu. Historische Arbeitsdateien ohne diesen Zustand sind kein neu reproduzierter Fehler des aktuellen Aufnahmewegs._

### 5.3 Anleitung-Speichern akzeptiert gleich große beschädigte Assets

_REMOVED: Behoben am 29.10.2026._ GuideStore prüft bestehende reguläre PNG-Assets per SHA-256 und repariert abweichende Inhalte atomar aus dem gültigen Arbeitsspeicherstand. Gesunde Dateien werden nicht neu geschrieben; Symlink-/Dateitypgrenzen bleiben erhalten. Der neue Domain-Test prüft gleich große Korruption, Reparatur und vorherige Generation. 174 Swift-Testing- und zwei XCTest-Prüfungen sowie die vollständige Anleitungs-Sandboxprüfung bestehen; auch zehn Textsicherungen einer großen Anleitung erhalten die unveränderten Bilddateien. Nachweise unter `build/ReleaseFixes/Guides/`, `domain.log` und `guides-sandbox.log`.

### 5.4 Kurze GIF-Schnitte werden fast nur am Anfang abgetastet

_REMOVED: Behoben am 01.11.2026._ Jeder GIF-Frame wird bei `trim.start + index / fps` abgetastet. Die bereits aufgerundete Framezahl hält die Zeitpunkte innerhalb der Auswahl; die falsche Begrenzung um ein ganzes GIF-Intervall entfällt. Die Zeitauflösung beträgt 60.000 Ticks pro Sekunde.

- **Ort:** [VideoRecordingFiles.swift:278](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Capture/VideoRecordingFiles.swift:278).
- **Nachweis:** Echter synthetischer 30-fps-MP4-Input, 0,13-Sekunden-Schnitt bei 8 fps: zwei unterschiedliche GIF-Frames, letzter Frame mit dem korrekt abgetasteten Quellbild verglichen. Die Referenz wird für den Vergleich ebenfalls in GIF-Palette/Farbraum gewandelt. Zusätzlich GIF-Ausgabe der minimalen Schnittdauer mit genau einem Frame. [VideoEditingChecks.swift:134](/Users/simon/Woerk/Swift/Snaprivo/Tests/VideoEditingChecks.swift:134); §12.14.

### 5.5 Gültige Klammern werden als fehlerhafter Modellausgang abgeschnitten

_REMOVED: Behoben am 01.11.2026._ Streaming-Abbruch und Bereinigung verwenden dieselbe konservative Erkennung eines Serialisierungsendes: vollständiger Satz, überzähliges Schlusszitat und ein ausschließlich aus Serialisierungszeichen bestehender Rest. Klammern oder Code-Fences allein lösen keinen Abbruch aus. Gültige Platzhalter, JSON, zitierte einzelne Klammern und Codeblöcke bleiben erhalten; die bekannten entgleisten Endstücke werden weiterhin entfernt.

- **Ort:** [GuideAssistantService.swift:410](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/GuideAssistantService.swift:410).
- **Nachweis:** Die ursprünglichen Bereinigungsfälle und sechs zusätzliche gültige Texte einschließlich „Gib {Vorname} ein und bestätige mit OK.“ bestehen. [GuideAssistantChecks.swift:99](/Users/simon/Woerk/Swift/Snaprivo/Tests/GuideAssistantChecks.swift:99); §12.14.

## 6. Security

_Keine neuen bestätigten Sicherheitsbefunde._ In den geprüften Aufnahme-, Datei- und Exportpfaden wurde keine neue private API, TCC-Umgehung oder konkrete Offenlegung sensibler Daten nachgewiesen. Dies ist kein vollständiger Penetrationstest.

### 6.1 Live-Abdeckung und exportierter Stand können während einer Geste auseinanderfallen

_REMOVED: Die frühere Ursache wurde behoben. Aktuelle Canvas-Prüfungen zu Abdeckung sowie Crop-/Resize-/PNG-Gleichheit bestehen. Die Datenschutz-/Transfer-Suite wurde nach der Skriptkorrektur und erneut nach den finalen Änderungen erfolgreich ausgeführt (§12.12)._

## 7. Performance

### 7.1 Core-Image-Kontext wird für jede Blur-Komposition neu erzeugt

_REMOVED: `Snaprivo/Editor/EditorRenderer.swift:48–50` hält inzwischen einen wiederverwendeten CIContext. Kein aktueller Befund derselben Ursache._

### 7.2 Jeder Autosave lädt Bibliotheks- und Papierkorbmetadaten erneut vollständig

_REMOVED: Der aktuelle Save-Pfad aktualisiert den betroffenen Bibliothekseintrag gezielt. Die frühere vollständige Aktualisierung bei jedem Autosave ist als allgemeiner Befund überholt._

### 7.3 Große Raster besitzen Grenzen, aber kein gemeinsames Arbeitsspeicherbudget

_REMOVED: Behoben am 29.10.2026._ Ein prozessweites, atomar verwaltetes Arbeitsbudget prüft große Render-/Encode-Jobs vor weiteren Allokationen. Die konservative Schätzung berücksichtigt Quelle, vollständige Crop-Komposition, Skalierung/Transformation, tatsächliche Präsentationsgeometrie, Rastereffekte, Bildassets und Encoderpuffer. Das Budget richtet sich nach einem Viertel des physischen Speichers, mindestens 512 MiB und höchstens 2 GiB. Gleichzeitige Überschreitung liefert einen verständlichen Speicherfehler mit Wiederholen-/Verkleinern-Hinweis; keine stille Reduktion der Exportauflösung. PNG-Encoding hält seine Reservierung bis nach dem Encoder, eigenständige Präsentations-/JPEG-/PDF-Schritte und Canvas-Blur nutzen dieselbe Zulassung. Lupenvorschauen sind auf 2048 Pixel begrenzt und behalten den Original-Koordinatenraum; die Pipette arbeitet innerhalb des Budgets weiterhin mit den präzisen Ausgabepixeln.

- **Ort:** `Snaprivo/Editor/EditorRenderer.swift:135`, `Snaprivo/Editor/EditorRenderer.swift:663`; `ImageOutput.encode`, `CanvasRenderClient.live`.
- **Nachweis:** Tatsächlich konkurrierende Reservierung und PNG-Zulassung, Release bei Fehler/Abbruch, ungültige Geometrie ohne Trap, Crop-/Präsentations-/Encoder-Abschätzung, volle Exportmaße und korrekte Lupen-Quellkoordinaten in `Tests/RenderingBudgetChecks.swift`; vollständige Canvas-/Pipetten-/Ausgabeprüfungen. `workflow.log`, `canvas.log`, `color-picker.log`, `image-output.log`.

Das Arbeitsbudget ist keine harte Grenze für den gesamten Prozess-RSS: bereits gehaltene Benutzerbilder, separate begrenzte Caches und interne System-/GPU-Allokationen bleiben davon zu unterscheiden. Es wurde kein Speichermangel erzwungen.

### 7.4 Einige Bildabbrüche erreichen die Detached-Arbeit nicht

_REMOVED: Behoben am 29.10.2026._ Canvas-Assetprüfung und Lupenkomposition besitzen Worker-Handles mit Cancellation-Handlern und prüfen Abbruch/Generation vor Veröffentlichung. Assetvalidierung prüft zusätzlich vor jedem weiteren Decoder. Lupen-Coalescing verwirft überholte Ergebnisse und beginnt nach Abbruch keine neue Runde; alte Task-Abschlüsse überschreiben keine neueren Handles. Auch temporäres PNG-Rendering und QuickCapture-Thumbnail-Decoding erhalten den Abbruch. Abgebrochene temporäre Transfers werden entfernt; ausdrücklich begonnene, vom Modell verwaltete Exporte bleiben wie bisher im Beenden-/Speicher-Workflow.

- **Ort:** `Snaprivo/Editor/EditorCanvas.swift:368`, `Snaprivo/Features/QuickCaptureView.swift:12`; `EditorPNGShare.writeTemporaryPNG`.
- **Nachweis:** Kontrolliert angehaltene echte Canvas-/Vorschaupfade beobachten Worker-Cancellation; verspätete Fehler/Pixel erscheinen nicht, Coalescing veröffentlicht keine veraltete Komposition und temporäre PNGs sind nach Abbruch entfernt. `Tests/RenderCancellationChecks.swift`, `workflow.log`, `quick-capture.log`.

Bereits laufende synchrone ImageIO-/Core-Image-Aufrufe lassen sich nicht vorzeitig unterbrechen; nach ihrer Rückkehr stoppen weitere Arbeit und Veröffentlichung zuverlässig.

### 7.5 Lange Texte werden bei Canvas-Arbeit synchron neu gelayoutet

_REMOVED: Behoben am 29.10.2026._ Textgeometrie wird anhand des vollständigen Texts, Font/Stils, Breite, Objektart und Callout-Mindesthöhe zwischengespeichert. Der unveränderliche Cache-Key besitzt vollständige Gleichheitsprüfung; Position, Farbe und UUID gehören nicht zum Geometrieschlüssel. `NSCache` hat Count-/Kostenlimits (512 Einträge, Zielkosten 4 MiB). Nur unveränderliche Maße werden geteilt; jede tatsächliche Layoutberechnung besitzt eigene TextKit-Objekte.

- **Ort:** `Snaprivo/Editor/EditorRenderer.swift:74`, `Snaprivo/Editor/EditorRenderer.swift:309`.
- **Nachweis:** Cache-Hits bei unveränderter Geometrie/Translation/Farbe/anderer UUID, Invalidierung bei Inhalt-/Fontänderung und parallele Messungen. Aktuelle synthetische Messung: `Text geometry benchmark: 149500 characters, cold 86.215 ms, warm mean 0.122 ms (10 measurements); cache hit/miss invalidation verified`. `workflow.log` und `canvas.log` unter `build/AuditFinalFixes/`.

Die erste Messung geänderten Inhalts bleibt synchron. Der Nachweis betrifft wiederholte Geometriemessungen, keinen vollständigen Interaktions-/p95-Benchmark.

### 7.6 Vorschläge gelöschter Schritte halten deren Bildstände weiter fest

_REMOVED: Behoben am 01.11.2026._ GuideModel meldet Dokument-/Schrittzugehörigkeitsänderungen unabhängig von der sichtbaren View. Die Vorschlagssammlung entfernt Modelle anhand von Dokument-ID und tatsächlich vorhandenen Schritt-IDs, beendet deren Arbeit und verwirft auch einen Dialog für einen entfernten Einzelschritt. Undo stellt den Schritt wieder her, ohne einen verworfenen Vorschlag oder Job wiederzubeleben. Der Callback hält die Sammlung nur schwach; GuideModel benötigt keine Abhängigkeit vom Assistenten.

- **Ort:** [GuideModel.swift:12](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/GuideModel.swift:12), [GuideAssistantModel.swift:26](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/GuideAssistantModel.swift:26).
- **Nachweis:** Entfernen fertiger und noch laufender Vorschläge ohne View-Hilfe; schwache Referenzen auf die alten Modelle werden nil, verspätete Antworten werden nicht veröffentlicht, Undo erhält die Bildschritte ohne verwaiste Vorschläge. [GuideAssistantChecks.swift:319](/Users/simon/Woerk/Swift/Snaprivo/Tests/GuideAssistantChecks.swift:319); §12.14.

### 7.7 Hintergrund-Unschärfe erzeugt weiterhin jeweils einen neuen CIContext

_REMOVED: Behoben am 01.11.2026._ Der Präsentationshintergrund verwendet denselben threadsicheren `blurContext` wie die übrigen Blur-Operationen. Die lokale Kontextneuerzeugung entfällt.

- **Ort:** [EditorRenderer.swift:958](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorRenderer.swift:958).
- **Nachweis:** Bestehende Hintergrund-Prüfungen zu tatsächlicher Pixelglättung, deckenden Kanten, Bildimport und Komposition bestehen. Keine neue Performance-Zahl oder Instruments-Messung behauptet; §12.14.

## 8. SwiftUI / UI

### 8.1 Finder-Öffnen exportierter Projekte/Sicherungen ist nicht angeschlossen

_REMOVED: Dokumenttypen sind inzwischen registriert und `application(_:open:)` in `Snaprivo/App/SnagForgeApp.swift:225–226` verarbeitet URLs. Die alte Aussage eines vollständig fehlenden Öffnungspfads ist überholt; kein frischer LaunchServices-End-to-End-Test in diesem Audit._

### 8.2 Objekte im Canvas sind für VoiceOver/Tastatur nicht einzeln erreichbar

_REMOVED: Eine zugängliche Objektliste und Tastaturverschiebung sind inzwischen implementiert; die aktuellen Tastaturprüfungen bestehen. Der frühere vollständige Funktionsmangel ist überholt. Eine komplette VoiceOver-Abnahme bleibt in §11 ausdrücklich offen._

### 8.3 Formumwandlung verliert die Auswahl nach dem View-Update

_REMOVED: Behoben am 29.10.2026._ Der SwiftUI-Observer löscht die Auswahl beim tatsächlichen Werkzeuggruppenwechsel, erhält sie aber beim Umwandeln innerhalb der Formengruppe. Der neue Workflow-Test verwendet den produktiven EditorView und echte Update-Zyklen: Rechteck/Ellipse mehrfach umwandeln, Geometrie/Selektion erhalten, anschließende Farbe am Objekt prüfen, Auswahl beim Wechsel zu Pfeil entfernen und gespeichertes Ergebnis neu laden. `build/ReleaseFixes/workflow.log`.

### 8.4 Formen merkt sich die Ellipse beim Werkzeugwechsel nicht

_REMOVED: Behoben am 29.10.2026._ `selectShape` merkt nun auch Ellipse als `defaultShapeKind`. Rückkehr zur gruppierten Formen-Schaltfläche und Übernahme beim Bildwechsel behalten diese Variante. Durch den neuen View-/Modell-Workflow und die vollständige Canvas-Suite geprüft. Keine zusätzliche Projektformatversion. `build/ReleaseFixes/workflow.log`, `canvas.log`.

### 8.5 Video-Menübefehle bieten unapplizierte Änderungen als Undo/Redo an

_REMOVED: Behoben am 29.10.2026._ Die globalen Undo-/Redo-Menüeinträge verwenden nun direkt `canUndo` beziehungsweise `canRedo` für Videos. Nicht angewendete Schnittentwürfe bieten damit keinen wirkungslosen Menübefehl an; die bestehende native Text- und Guide-Routenlogik bleibt erhalten. Video-Editing-Suite nach dieser Änderung vom Teilprüfer erfolgreich ausgeführt (Exit 0, ohne separat umgeleiteten Log). Die Release-Sandbox-Workflowprüfung besteht ebenfalls.

### 8.6 Öffentliche Datenschutzerklärung ist in der App nicht verlinkt

_REMOVED: Behoben am 29.10.2026._ Einstellungen → Datenschutz enthält nun einen nativen Link mit Accessibility-Identifier `settings.privacy.policy`. Ziel und Label sind Deutsch/Englisch lokalisiert; die URL folgt `Bundle.main.preferredLocalizations` und damit der aktuell verwendeten App-Sprache, nicht bloß der Region. Regionale Präferenzen und englischer Fallback sind im Workflow geprüft, das Label zusätzlich in der nativen Lokalisierungssuite. `build/ReleaseFixes/workflow.log`, `localization-runtime.log`, `localization-catalog.log`.

### 8.7 Angeheftete Bilder bieten ihre Aktionen nicht für Tastatur und VoiceOver an

_REMOVED: Behoben am 01.11.2026._ Das Pin-Bild ist ein expliziter Tab-Fokuspunkt. Der Panel-Einstieg übergibt den Fokus an das Bild; beim Tastaturfokus erscheinen die Controls, ein bloßes Maus-Verlassen versteckt sie dann nicht. Leertaste und Enter rufen das native Aktionsmenü auf. Unabhängig von der Hover-Leiste bietet das Bild sechs Accessibility-Aktionen: vier Deckkraftstufen, Klickdurchlass/Entsperren und Schließen. Auch die öffentliche Show-Menu-Aktion ist angeschlossen. Der Tastaturhinweis ist Deutsch/Englisch lokalisiert.

- **Ort:** [PinnedImage.swift:70](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Features/PinnedImage.swift:70), [PinnedImage.swift:160](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Features/PinnedImage.swift:160).
- **Nachweis:** Nativer Fenster-/Tab-Test, Fokus-Sichtbarkeit nach Maus-Verlassen, Ausführung aller Deckkraft-/Klickdurchlass-/Schließaktionen sowie tatsächliche NSMenu-Zielaktionen. Die Menüpräsentation ist im automatisierten Test injiziert, damit kein modaler Pop-up-Loop auf Benutzereingabe wartet; das Produkt verwendet `NSMenu.popUp`. [QuickCaptureIntegrationChecks.swift:315](/Users/simon/Woerk/Swift/Snaprivo/Tests/QuickCaptureIntegrationChecks.swift:315); §12.14. Eine vollständige physische VoiceOver-Bedienungsabnahme bleibt offen.
- **Öffentliche API:** [Apple: NSAccessibilityCustomAction](https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction), [Show Menu](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityperformshowmenu()).

## 9. Dead code / duplication / refactor

### 9.1 Xcode-Scheme führt die vorhandenen Tests nicht aus

_REMOVED: Das leere Testables-Verzeichnis ist im dokumentierten Workflow mit expliziten Testskripten kein neuer eigenständiger Produktfehler. Ob Tests lauffähig sind, wird hier konkret über §9.2 und §12.2 berichtet. Keine Umstellung des Testsystems allein wegen des leeren Scheme-Eintrags empfohlen._

### 9.2 Workspace-/UI-Abhängigkeit bricht fünf native Testskripte

_REMOVED: Behoben am 29.10.2026._ WorkspaceModel kennt den Fenstercontroller nicht mehr direkt. Ein injizierbarer Callback wird vom produktiven QuickCapturePanelController eingerichtet. Damit benötigen die isolierten Skripte keine zusätzliche UI-Quelldatei oder Controller-Attrappe. Alle fünf Skripte wurden nach den finalen Workspace-Änderungen erneut sequenziell ausgeführt und bestehen mit Exit 0: `build/ReleaseFixes/Scripts/FINAL-transfer-privacy.log`, `FINAL-library.log`, `FINAL-scroll.log`, `FINAL-settings.log`, `FINAL-trash.log`.

## 10. Cross-cutting recommendations

### 10.1 Reihenfolge der Korrekturen

Alle sechs Befunde sind korrigiert und mit den zugehörigen Regressionen abgesichert (§12.14). Neue Produktfehler wurden dabei nicht pauschal ausgeschlossen. Reale Capture-, Audio-, VoiceOver- und Store-Kandidatenabnahmen bleiben gesonderte Prüfungen.

### 10.2 Archiv und App Store Connect

Historischer Stand vom 29.10.2026: Der damals geprüfte Release-Build enthielt x86_64 und arm64, Bundle-ID `com.snaprivo.app`, Version `1.0`, Build `2`, Mindestversion `26.0`; die reguläre Signaturprüfung bestand. In diesem Audit wurde ein frischer Debug-Build geprüft, kein neues Release-Archiv oder Store-Upload. Die vom Nutzer bestätigte Kauf-/Restore- und Store-Vorbereitung bleibt anerkannt.

### 10.3 Sicherheits- und Lifecycle-Invarianten

Die Korrekturen sichern laufende Dateioperationen unabhängig vom sichtbaren View, die Integrität wiederverwendeter Assets und die Selektion über SwiftUI-Updates hinweg. Die entsprechenden Regressionen prüfen tatsächliche Wartezustände und Dateien statt nur Aktivierungsflags. Besitz, Arbeitsbudget und Abbruch großer Hintergrundjobs sind zusätzlich abgesichert (§7.3/§7.4).

### 10.4 Zuständigkeit für Vorschau-Layout vereinheitlichen

`WorkspaceView.swift:215–218` fordert weiterhin animierte Layoutaktualisierung nach Änderungen der Vorschauanzahl an, während Stack-/Controller- und Dismiss-Pfade das Layout ebenfalls aktualisieren. Der Controller besitzt einen Schutz gegen identische Zielrahmen. Deshalb ist hierdurch allein keine fehlerhafte Schließanimation nachgewiesen und es wird kein zusätzlicher Befund gezählt. Eine zentrale Zuständigkeit würde die nächste gezielte Prüfung der vom Nutzer beobachteten Animation vereinfachen. Ebenso ist für die Aufnahme-Startlatenz eine Messung vom Benutzerklick bis zum sichtbaren ersten Rahmen erforderlich.

## 11. What was NOT audited

- Keine vollständige manuelle Abnahme des Desktop-Captures, der ersten Systemberechtigungsabfrage oder eines TCC-Resets. Die nativen Capture-Prüfungen arbeiten mit kontrollierten Inhalten und beweisen keine reale Klick-bis-Rahmen-Latenz.
- Keine vollständige interaktive Prüfung der gemeldeten Miniatur-Schließanimation auf mehreren Displays; kein neuer Nachweis ihrer Ursache.
- Keine komplette VoiceOver-, Lokalisierungswortlaut-, Kontrast- oder Eingabehilfen-Abnahme. Die statische Lokalisierungsprüfung und einzelne native Tastaturprüfungen sind gelaufen.
- Kein Instruments-/Allocations-Profil und kein erzwungener Speichermangel. §7.5 enthält aktuelle Cold-/Warm-Textmessungen; kein umfassender End-to-End-/p95-Performance-Benchmark.
- Keine physische Störung eines externen Laufwerks und kein absichtlich blockierter Netzwerk-Mount. Der neue Lock-Konflikttest verwendet separate OS-Dateideskriptoren, keine zwei vollständigen App-Instanzen.
- Kein echter App-Abbruch während eines Benutzerexports; §3.1 wurde über einen kontrollierten Writer und die echte Beenden-Prüfung belegt.
- Keine vollständige Tiefenprüfung aller Tests, fremder Framework-Interna, sämtlicher Dateiformatvarianten oder aller möglichen Interleavings. Geprüft wurden konkrete Pfade, Grenzen und Hotspots.
- Im aktuellen Durchlauf keine neue Generierung mit dem echten Apple-Intelligence-Modell. Die neuen Abbruch-/Lebenszyklusfälle verwenden einen kontrollierten Service bei unveränderten produktiven Modellen. Die Textkürzung wird direkt am produktiven Helper geprüft.
- Die native Pin-Probe ist eine Prüfung des Accessibility-Baums und des Fokuswegs, keine vollständige Bedienungsabnahme mit laufendem VoiceOver.
- Kein Release-Archiv, keine neuen StoreKit-Käufe, keine Store-Signierungs-/App-Store-Connect-Abnahme und kein Test auf macOS-26-Hardware. Die lokale Release-Signatur wurde am 29.10. separat verifiziert. Ausgeführt auf lokalem arm64-Mac mit macOS 27 und Xcode 27; Deployment Target bleibt 26.

## 12. Verification

**Aktuelle Korrekturrunde: §12.14; vorausgehender Audit: §12.13.** Die folgenden Einträge §12.1–§12.12 bleiben als historische Nachweise mit ihren ursprünglichen Daten erhalten und sind keine heute erneut ausgeführten Prüfungen.

### 12.1 Historische Verifikation vor den Korrekturen

Die folgenden Nachweise stammen aus der Prüfung vor der beauftragten Korrekturrunde. Die zugehörigen High-Befunde sind inzwischen geschlossen; aktuelle Regressionsergebnisse stehen in §12.8.

- **§3.1** — Quellpfad persönlich nachgeprüft: Entfernen des Modells in `WorkspaceModel.swift:734–740`, Beenden-Warteliste in `WorkspaceModel.swift:429–444`, Besitz des PNG-Tasks und Schreibaufruf in `EditorModel.swift:1042–1062`, Pending-Work-Wartung in `EditorModel.swift:1137–1155`, Freigabe der Prozessbeendigung in `SnagForgeApp.swift:254–267`.
- **§3.1** — Zusätzlich mit produktiven App-Quellen unter Swift 6 kompiliert und ausgeführt. Keine Controller-Attrappe im fertigen Versuch. Der Writer blieb kontrolliert angehalten; die Prüfung gab trotzdem `true` zurück. Nach Freigabe entstand die Datei. Quelle und Log stehen im Befund.
- **§5.3, §8.3, §8.4** — Weitere ausgeführte Fehlernachweise sind direkt bei den Befunden dokumentiert. Deren Schwere ist aufgrund der Voraussetzungen beziehungsweise des begrenzten UX-Schadens konservativer eingestuft.
- **§3.2, §3.3, §7.3, §7.4, §8.5** — Statische Nachweise; experimentelle Grenzen sind bei jedem Befund genannt. **§7.5** besitzt zusätzlich die angegebenen Messungen. **§9.2** besitzt einen ausgeführten Compilerfehler plus Prüfung der vier weiteren Dateilisten.

- **§8.6** — `SettingsView.swift:359–380` vollständig geprüft, kein vollständiger Datenschutz-Link. Alle produktiven Quellen und Konfigurationen nach einem alternativen Link durchsucht; Apple 5.1.1(i) am 29.10. verifiziert. Die Existenz der Website wird nicht bestritten.

### 12.2 Builds und Tests vom 28.10.2026

| Prüfung | Aktuelles Ergebnis | Nachweis in `build/` |
|---|---|---|
| `./scripts/build.sh -derivedDataPath build/Audit20261028` | Frischer Debug-Build erfolgreich; keine Swift-, Concurrency- oder Deprecation-Warnung im App-Code | `audit-2026-10-28-build.log` |
| `./scripts/test.sh` | 173 Swift-Testing-Tests und 2 XCTest-Tests bestanden | `audit-2026-10-28-domain.log` |
| `./scripts/test-canvas.sh` | Bestanden, u. a. Crop/Resize, Gruppen, fortgesetzte Werkzeuge, Tastatur, Pixel und Ausgabe | `audit-2026-10-28-canvas.log` |
| `./scripts/test-color-picker.sh` | Bestanden; 232 native Pixelproben, Transformationen, Zoom, Fokus, Cursor und Abbruch | `audit-2026-10-28-color-picker.log` |
| `./scripts/test-capture.sh` | Bestanden; Auswahl, Cursor, sofortige Bestätigung, Geometrie und Masken | `audit-2026-10-28-capture.log` |
| `./scripts/test-video-editing.sh` | Bestanden; Timeline, H.264/AAC-Schnitt, Undo/Redo angewendeter Stände, Backup und Prozessneustart | `audit-2026-10-28-video.log` |
| `./scripts/test-guides.sh` | Bestanden; Ausgabe, PDF/Markdown, persistierte Assets und Prozessneustart; zusätzlich großer synthetischer Guide | `audit-2026-10-28-guides.log` |
| `python3 scripts/check-localization.py build/Audit20261028` | Bestanden: 1.252 App-, 7 Info- und 18 Domain-Schlüssel einschließlich Platzhalter-/Compilerabdeckung | Ausgabe der ausgeführten Prüfung |
| `./scripts/test-transfer-privacy.sh` | **Compilerfehler, keine ausgeführte Testsuite**, siehe §9.2 | `audit-2026-10-28-transfer.log` |
| Kontrollierter Export-/Beenden-Versuch | Fehler §3.1 reproduziert | `audit-2026-10-28-quit-probe.log` |
| Gehosteter produktiver EditorView | Fehler §8.3 und §8.4 reproduziert | `audit-2026-10-28-shape-probe.log` |
| Gleich große Guide-Asset-Beschädigung | Fehler §5.3 reproduziert | `audit-2026-10-28-guide-corruption-probe.log` |
| Synthetische Textlayout-Messung | Kosten §7.5 gemessen | `audit-2026-10-28-text-probe.log` |

Die zusätzlichen Versuche sind Diagnoseprogramme im ignorierten Build-Verzeichnis und wurden nicht als Produkt- oder Regressionstest eingecheckt. Kein Test verwendet private Benutzeraufnahmen. Ein bestandener Build ersetzt die in §11 genannten manuellen Abnahmen nicht.

### 12.3 Nacharbeit und Regressionen vom 13.10.2026

_REMOVED: Historischer Durchlauf. Aktuelle Aussagen stehen in §12.1–§12.2; alte Befundnummern bleiben in den Fachabschnitten erhalten._

### 12.4 Nacharbeit vom 18.10.2026

_REMOVED: Historischer Durchlauf, keine aktuelle Testbestätigung._

### 12.5 Nacharbeit vom 19.10.2026

_REMOVED: Historischer Durchlauf, durch diese Momentaufnahme ersetzt._

### 12.6 Stabilitätsprüfung nach früherem Videoeditor-Umbau

_REMOVED: Historischer Durchlauf. Die neue Videoeditor-Prüfung ist in §12.2 aufgeführt. Sie beseitigt den statisch bestätigten Menüwiderspruch aus §8.5 nicht._

### 12.7 Prüfung vor den Korrekturen am 29.10.2026

| Prüfung | Ergebnis | Nachweis |
|---|---|---|
| Frischer Xcode-Release-Build unter `build/PreUploadAudit` | Erfolgreich; x86_64 und arm64; keine Swift-/Concurrency-/Deprecation-Warnungen. Nur AppIntents-Metadatenhinweis. | `/tmp/snaprivo-preupload-release-build.log` |
| Reguläre Signaturprüfung | `codesign --verify --deep --strict` erfolgreich außerhalb der eingeschränkten Shell | Tool-Ausgabe; kein Store-Archiv und kein Upload |
| Lokalisierung dieses Release-Bundles | 1.252 App-, 7 InfoPlist- und 18 Domain-Schlüssel vollständig, Platzhalter und Compilerabdeckung bestanden | `/tmp/snaprivo-preupload-localization.log` |
| Domain und native Workflow-Suite | 173 Swift-Testing- und 2 XCTest-Prüfungen plus Workflow-/Filmstrip-Regressionsfälle bestanden, am heutigen unveränderten Produktcode unmittelbar vor diesem Audit | `/tmp/snaprivo-crop-tools-domain.log`, `/tmp/snaprivo-crop-tools-workflow.log` |
| Export → Schnellvorschau schließen → Beenden | §3.1 mit neu kompiliertem aktuellem Binary reproduziert | `build/PreUploadAuditProbes/Concurrency/run.log` |
| Produktiver EditorView über echten Update-Zyklus | §8.3 und §8.4 erneut reproduziert | `build/PreUploadAuditProbes/UI/shape-run.log` |
| Gleich große Asset-Beschädigung | §5.3 mit aktuellem Domain-Build erneut reproduziert | `build/PreUploadAuditProbes/Data/guide-same-length-current.log` |
| Teilprüfung der nativen Skripte | Transferprüfung scheitert weiterhin an fehlendem QuickCapturePanelController; Video-Editing und Release-Workflows laut Teilprüfer erfolgreich, ohne `--sandbox` | Ausgaben der getrennten Tool-Prüfung; kein separater frischer Log, historische Logs nicht als heutige ausgegeben |
| Native Zuschnitt-/Mehr-Bedienung | Bereits unmittelbar vor diesem Audit im neu gebauten synthetischen App-Build geprüft: Zusatzwerkzeuge freigegeben, Pipette/Gestaltung bleiben nach Wechsel aktiv | `docs/EDITOR-TOOLBAR-ABNAHME.md`; Vorher-/Nachher-Prüfung in dieser Unterhaltung |

Die Performance-Messwerte in §7.5 bleiben ausdrücklich vom 28.10.; keine neuen Profiling-Aussagen. Keine echte Bildschirm-/Audioaufnahme, kein TCC-Reset, keine vollständige macOS-26-/VoiceOver-Abnahme und kein Upload. Frühere Nachweise folgen unverändert als Historie.

### 12.8 Abschluss der Korrekturrunde am 29.10.2026

Historischer Abschluss der ersten sieben Korrekturen. Die neueste Nachprüfung einschließlich der fünf später behobenen Medium-Befunde steht in §12.12.

| Prüfung | Ergebnis | Log unter `build/ReleaseFixes/` |
|---|---|---|
| Regulärer Debug-Build des finalen Quellstands | Erfolgreich | `debug-build.log` |
| Optimierter Release-Build | Erfolgreich; x86_64 und arm64; reguläre `codesign --verify --deep --strict`-Prüfung bestanden | `release-build.log`; Signaturprüfung im Toolprotokoll |
| Compilerdiagnostik | Keine Swift-/Concurrency-/Deprecation-Warnung; nur unveränderter AppIntents-Metadatenhinweis | Beide Buildlogs |
| Domain | 174 Swift-Testing- und zwei XCTest-Prüfungen bestanden | `domain.log` |
| Vollständige native Canvas-Suite | Bestanden, einschließlich Crop/Zoom, Formen, Pixel/Masken und Persistenz | `canvas.log` |
| Produktive SwiftUI-Workflows | Formumwandlung/Selektion, Ellipsenrückkehr/Bildwechsel, bestätigter Zuschnitt, Text und Filmstrip bestanden | `workflow.log` |
| Schnellvorschau und Export-Abschluss | Zwei Writer-Gates, nachträglicher Dismiss, sichtbarer Fehler, ausdrückliche Bestätigung und eigener Bibliothekswechsel-Gate bestanden | `Capture/quick-capture-library-gated.log` |
| Datenschutz-/Transferprüfung | Exit 0 | `Scripts/FINAL-transfer-privacy.log` |
| Bibliothek, Scroll, Einstellungen, Papierkorb | Alle Exit 0, nach finalen Workspace-Änderungen | `Scripts/FINAL-library.log`, `FINAL-scroll.log`, `FINAL-settings.log`, `FINAL-trash.log` |
| Release-Abläufe im Sandbox-Testhost | Backup/Restore, unterbrochene Medien, beschädigte Daten, Finder-Routing, vorhandene Projekte, Kaufzustände bestanden | `release-workflows-sandbox.log` |
| Anleitungen im Sandbox-Testhost | Ausgabe, Assets, beschädigte Daten, Autosave/Wiederöffnen und eigener Prozessneustart bestanden; gesunde Bilddateien unverändert | `guides-sandbox.log` |
| Lokalisierung des Release-Bundles | 1.254 App-, sieben InfoPlist- und 18 Domain-Schlüssel vollständig, Platzhalter/Compilerabdeckung bestanden | `localization-catalog.log` |
| Native Sprachprüfung | Deutsch, Englisch, Fallback und regionale App-Sprachpräferenzen einschließlich Prozessneustarts bestanden; neuer Datenschutz-Text geprüft | `localization-runtime.log` |

Video-Editing wurde nach der Menükorrektur vom Teilprüfer erfolgreich ausgeführt; keine tatsächlichen Käufe oder neuen Kamera-/Mikrofonrechte. Keine echte Nutzeraufnahme wurde für die Tests erstellt oder exportiert. Der lokale Build bleibt Version 1.0 (2); tatsächliches Store-Archiv, verfügbare Buildnummer, Installation/Update und die offenen physischen macOS-26-/Capture-/Audio-/VoiceOver-Fälle bleiben separat. Kein Upload und kein Commit in dieser Runde.

### 12.9 Mehrfachkopieren am 29.10.2026

Die anschließend ausdrücklich gewünschte Mehrfachauswahl ist implementiert und geprüft: Strg-/Cmd-Klick, normale Navigation, getrennte flache PNG-Dateien, gespeicherte und ungespeicherte Abdeckungen/Zuschnitt, Clipboard-Konflikte/Fehlerbereinigung und Abschluss vor Beenden. Die native Bedienung mit drei synthetischen Bildern ist zusätzlich ausgeführt; Strg-Klick öffnet kein Kontextmenü. Allgemeine Benutzer-Zwischenablage unberührt; die Copy-Tests verwenden private Pasteboards. Build und 174+2 Domain-Tests, volle Workflow-Suite sowie deutsche/englische Laufzeitlokalisierung bestehen. Logs: `build/FilmstripMultiCopy/`. Detaillierter Umfang und Grenzen: `docs/BILDVORSCHAULEISTE-ABNAHME.md`. Kein Upload und keine zusätzliche Release-Freigabe für alle Empfänger-Apps.


### 12.10 Schnellstart und kontextbezogene Hinweise – 29. Oktober 2026

Kompakter visueller Schnellstart, optionale Kürzelwahl, synthetisches Übungsbild im normalen Editor-/Projektpfad und quittierbare Hinweise für Zuschneiden, Abdecken, erste Annotation und Bild-Mehrfachkopie ergänzt. Kein neues Domain-Format, Capture-API oder Berechtigungsweg. Debug-Build, Einstellungen, gesamte Workflow-Regression und Lokalisierungskatalog/native Sprachläufe bestanden (`build/Onboarding/`). Der native Workflow prüft Übungsprojekt, keine automatische Kopie/erste Aufnahme, Ausschnittschutz und Hint-Quittierung erst bei erfolgreicher Kopie. Live-UI-Verbindung in dieser Sitzung unzuverlässig; vollständige interaktive/VoiceOver-Abnahme bleibt offen. Details: [ONBOARDING-ABNAHME.md](docs/ONBOARDING-ABNAHME.md).


### 12.11 Animierte Onboarding-Hilfe und konstante Filmstrip-Höhe – 29. Oktober 2026

Drei endliche, wiederholbare Demonstrationen mit stetiger Zeigerbahn; gefüllte Pfeilspitze aus der vorhandenen Editor-Geometrie; statische Endzustände bei reduzierter Bewegung. Der Mehrfachauswahlhinweis bleibt bis zum ausdrücklichen Schließen sichtbar, die Bildleiste reserviert eine konstante Kopfzeilen-/Gesamthöhe. Debug-Build, vollständige Workflow-Regression mit nativen Pixel-/Höhenvergleichen, Animationskoordinaten und de/en/Fallback-Lokalisierung erfolgreich. Synthetische Zwischen-/Endzustände visuell geprüft. Nachweise unter `build/OnboardingMotion/` und in [ONBOARDING-ABNAHME.md](docs/ONBOARDING-ABNAHME.md).


### 12.12 Abschluss der fünf verbleibenden Audit-Befunde – 29. Oktober 2026

§3.2, §3.3 und §7.3–§7.5 sind am aktuellen Arbeitsbaum korrigiert. Die Nachweise verwenden synthetische Daten, gehaltene Worker/OS-Locks, echte Dateien und native Ansichten. Ursprüngliche Projekt-/Ausgabedaten bleiben unverändert; keine neue Formatversion oder Abhängigkeit.

| Prüfung | Ergebnis | Nachweis unter `build/AuditFinalFixes/` |
|---|---|---|
| Domain | 176 Swift-Testing- und 2 XCTest-Prüfungen bestanden | `domain.log` |
| Debug-Build | Erfolgreich | `debug-build.log` |
| Universeller Release-Build | arm64 und x86_64 erfolgreich; Signaturprüfung bestanden | `release-build.log`, `release-architecture.log`, `signature.log` |
| Workflow/Abbruch/Rasterbudget/Text | Erfolgreich; native Worker-, Admission-, Pixel-/Koordinaten-/Persistenzprüfungen | `workflow.log` |
| Canvas und Pipette | Erfolgreich; Crop, Redaction, Transformationen, Lupenprojektion und präzise Samples | `canvas.log`, `color-picker.log` |
| Bildausgabe/Anleitungen | Erfolgreich; PNG/JPEG/PDF und bestehende Anleitungsregressionen | `image-output.log`, `guides.log` |
| Schnellvorschau/Beenden | Erfolgreich | `quick-capture.log` |
| Speicherorte/Bibliothek/Transfer | Erfolgreich; Live-Restore, Fehlerfälle und Scope-Lebenszyklus | `settings.log`, `library.log`, `transfer-privacy.log` |
| Papierkorb/Scroll | Erfolgreich | `trash.log`, `scroll.log` |
| Lokalisierung | 1.291 App-, 7 InfoPlist- und 19 Domain-Texte; vollständige Compiler-Abdeckung und native de/en/Fallback-Läufe | `localization-catalog.log`, `localization-runtime.log` |

Die nativen CLI-Prüfungen können mit dem macOS-27-SDK bekannte AVFoundation-Deprecation-Hinweise ausgeben; die weiterhin für macOS 26 unterstützten Reader-APIs wurden dafür nicht ungefragt ersetzt. Der lokale Release-Build ist entwicklersigniert und bleibt Version 1.0 (2). Kein Store-Archiv exportiert, keine Buildnummer in App Store Connect abgefragt, kein Upload und kein Commit. Die in §11 benannten physischen und manuellen Store-Kandidatenprüfungen bleiben separat.

### 12.13 Neuer Audit des Arbeitsbaums – 1. November 2026

Historischer Befundnachweis unmittelbar vor den anschließend in §12.14 dokumentierten Korrekturen.

Alle neuen Befunde wurden an den zitierten Produktzeilen nachgelesen; §3.4, §5.4, §5.5, §7.6 und §8.7 besitzen zusätzlich synthetische Reproduktionen. Kein neuer Critical-/High-Befund blieb nach Prüfung bestätigt. Insbesondere ist die Freigabe der Apple-Intelligence-Warteschlange bei abgebrochenen Wartenden korrekt: ein geworfener Continuation-Fehler verlässt `acquire()` vor dem nachfolgenden Permit-Check. Ein zunächst vermutetes GIF-Grenzleck durch die `actualTime`-Toleranz wurde nicht reproduziert und wird nicht als weiterer Fehler geführt.

| Prüfung | Ergebnis | Nachweis |
|---|---|---|
| Frischer vollständiger Debug-Build mit eigenem DerivedData | Erfolgreich; keine Swift-Concurrency-/Deprecation-Warnungen. Nur der AppIntents-Metadatenhinweis. | [build.log](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/build.log) |
| Bestehende GuideAssistant-Suite | Exit 0; Vorschlagsübernahme, Undo/Redo, Persistenz, veraltete Quellen, Berechtigungslogik, Abbruch und Markierungen bestanden. Die neuen Randfälle sind dort nicht abgedeckt. | [guide-assistant-tests.log](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/guide-assistant-tests.log) |
| Neue Reproduktion §3.4 | Nach Verwerfen während einer angehaltenen Verfügbarkeitsprüfung trotzdem ein Generierungsaufruf. | [guide-probe.log](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/guide-probe.log), [temporärer Harness](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/GuideAuditProbe.swift:39) |
| Neue Reproduktion §7.6 | Null Dokument-Schritte, ein nicht aufgeräumtes Vorschlagsmodell mit einem Ausgangsschritt. | Derselbe Guide-Harness, Zeilen 56–65 |
| Neue Reproduktion §5.5 | Gültige Beschreibung mit `{Vorname}` wird zu „Gib“ gekürzt. | Derselbe Guide-Harness, Zeilen 67–70 |
| Neue Reproduktion §5.4 | 0,13-Sekunden-Schnitt liefert zwei identische GIF-Frames; Assertion meldet den reproduzierten Fehler, Exit 133 des Diagnoseprogramms. | [gif-probe.log](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/gif-probe.log), [temporärer Harness](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/GIFProbe.swift:24) |
| Neue Reproduktion §8.7 | Nativer Accessibility-/Tab-Test mit synthetischem Pin. | [probe.log](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/PinnedAccessibility/probe.log) |
| Domain und Scroll aus der unmittelbar vorherigen Korrektur im selben unveränderten Produktstand | 183 Swift-Testing- und zwei XCTest-Prüfungen sowie native synthetische Scroll-Suite bestanden. Hier nicht als neuer Durchlauf ausgegeben. | [domain.log](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/domain.log), [scroll-tests.log](/Users/simon/Woerk/Swift/Snaprivo/build/Audit20261101/scroll-tests.log) |

Die Diagnosequellen und Buildprodukte liegen ausschließlich im ignorierten Build-Verzeichnis. Einziges getracktes Ergebnis dieses Audits ist dieser Bericht. Die bereits vorhandenen Änderungen anderer Arbeiten bleiben unangetastet; keine neuen Abhängigkeiten, kein Commit und keine Veröffentlichung.

### 12.14 Korrektur aller sechs neuen Befunde – 1. November 2026

§3.4, §5.4, §5.5, §7.6, §7.7 und §8.7 sind am aktuellen Arbeitsbaum umgesetzt. Alle folgenden Prüfungen liefen nach den jeweiligen finalen Codeänderungen mit Exit 0; der App-Build enthält auch die abschließende Pin-Fokuskorrektur. Vorhandene Änderungen anderer Arbeiten bleiben erhalten. Keine neue Abhängigkeit, Formatänderung, Veröffentlichung oder Änderung an einer Benutzerbibliothek.

| Prüfung | Ergebnis | Nachweis |
|---|---|---|
| App-Build | Erfolgreich; keine Swift-/Concurrency-/Deprecation-Warnung. Nur der bekannte AppIntents-Metadatenhinweis. | [build.log](/Users/simon/Woerk/Swift/Snaprivo/build/AuditFixes20261101/build.log) |
| Textassistent §3.4, §5.5, §7.6 | Gehaltene Verfügbarkeit, Abbruch/Verwerfen/Ersetzen, Freigabe alter Modelle, expliziter Neustart, geänderte Hinweise während der Prüfung, Entfernen fertiger und laufender Vorschläge, spätes Ergebnis, Undo sowie gültige Klammern/JSON/Code-Fences bestanden. Bestehende Übernahme-/Undo-/Autosave-/Markup-Fälle bestehen weiterhin. | [assistant.log](/Users/simon/Woerk/Swift/Snaprivo/build/AuditFixes20261101/assistant.log) |
| GIF/Video §5.4 | Zwei unterschiedliche Bilder bei 0,13 Sekunden/8 fps; Endbild gegen die korrekt abgetastete und nach GIF konvertierte Referenz geprüft. Minimale Schnittdauer ergibt ein GIF-Bild. Vollständige Schnitt-, AAC-, Persistenz-, Backup-, Abbruch- und Originalschutzprüfungen sowie eigener Prozessneustart bestanden. | [video.log](/Users/simon/Woerk/Swift/Snaprivo/build/AuditFixes20261101/video.log) |
| Pin-/Schnellvorschau §8.7 | Tab-Fokuseinstieg, sichtbare Controls trotz Maus-Verlassen, Leertaste/Enter/Show Menu, echte NSMenu-Aktionsausführung, vier Deckkraftstufen, Klickdurchlass/Entsperren und Schließen bestanden. Bestehende Fenster-/OCR-/Export-/Beenden-/Bibliothekswechselprüfungen ebenfalls bestanden. | [pins.log](/Users/simon/Woerk/Swift/Snaprivo/build/AuditFixes20261101/pins.log) |
| Präsentationshintergründe §7.7 | Tatsächliche Pixelglättung, deckende Blur-Kanten, Orientierung, eigene Bildkopien, transparente Komposition, Seitenverhältnisse und Fehlerfälle bestanden. | [backgrounds.log](/Users/simon/Woerk/Swift/Snaprivo/build/AuditFixes20261101/backgrounds.log) |
| Domain | 183 Swift-Testing- und zwei XCTest-Prüfungen bestanden. | [domain.log](/Users/simon/Woerk/Swift/Snaprivo/build/AuditFixes20261101/domain.log) |
| Lokalisierung | 1.364 App-, 7 InfoPlist- und 19 Domain-Texte in Deutsch/Englisch; vollständige Compilerabdeckung und passende Formatargumente. | [localization.log](/Users/simon/Woerk/Swift/Snaprivo/build/AuditFixes20261101/localization.log) |

Die Pin-Tests verwenden echte NSWindows, Accessibility-Handler und NSMenu-Zielaktionen. Nur die Präsentation des modalen Pop-up-Menüs wird über den Controller injiziert; der Produktpfad ruft unverändert die öffentliche AppKit-Präsentation auf. Keine neue vollständige VoiceOver-/TCC-/Capture-Abnahme auf einem physischen Mac und kein neuer Live-Lauf des Apple-Intelligence-Modells. Das Wiederverwenden des Core-Image-Kontexts ist geprüft, aber ohne neu behaupteten Performance-Messwert. Die Grenzen aus §11 bleiben bestehen.

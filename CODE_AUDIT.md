# Code-Audit — Snaprivo

Stand: **29.10.2026**, aktueller Arbeitsbaum einschließlich der bisherigen Export-/UI-Korrekturen, Mehrfachkopieren, animiertem Onboarding und der abschließenden Audit-Korrekturen. Befundnummern bleiben stabil. Die vorherige Fassung ist unter `build/AuditFinalFixes/CODE_AUDIT-before.md` gesichert.

**Ergebnis: Alle bestätigten Codebefunde dieses Berichts sind behoben; keine offenen Critical-, High- oder Medium-Codebefunde.** Die fünf zuletzt offenen Medium-Befunde (§3.2, §3.3, §7.3–§7.5) sind korrigiert und gezielt geprüft. Die früheren sieben Korrekturen bleiben erhalten. Die Abschlussprüfung deckt Debug/Release, Domain, Canvas, Workflow, Speicherorte, Bibliothek, Datenschutztransfer, Papierkorb, Scroll-Aufnahmen, Schnellvorschau, Bild-/Anleitungs-Ausgabe und Lokalisierung ab (§12.12).

Der Bericht ist die aktualisierte Nachprüfung der dokumentierten Befunde, keine Garantie für sämtliche möglichen Geräte-, Speicher- oder Systemzustände. Tatsächliches Store-Archiv, verfügbare Buildnummer und reale macOS-26-/Capture-/Audio-/VoiceOver-Abnahme bleiben von den Codebefunden getrennt (§11). Es wurden ausschließlich synthetische Fixtures verwendet; keine Benutzerbibliothek verändert und nichts veröffentlicht.

## 1. Executive summary

1. **[Behoben] Bibliothekssperre mit Deadline und Abbruch** — §3.2 — nicht blockierender Sperrerwerb, maximal drei Sekunden, lokalisierter Konfliktfehler; keine halbe Projekttransaktion.
2. **[Behoben] Ordnerfreigaben außerhalb des MainActors** — §3.3 — Hintergrund-Wiederherstellung, explizite Readiness, Security Scope vor Dateizugriff, abgesicherte späte Ergebnisse und beschädigte Einstellungen.
3. **[Behoben] Gemeinsames Raster-Arbeitsbudget** — §7.3 — konservative Abschätzung der Zwischenraster/Encoderkosten, atomare Zulassung paralleler Jobs, begrenzte Lupenvorschau und unveränderte finale Ausgabeauflösung.
4. **[Behoben] Abbruchweitergabe an Bild-Worker** — §7.4 — Assetprüfung, Lupen-Coalescing und Vorschau-Decoding beachten Abbruch und Anforderungsgeneration; temporäre abgebrochene PNGs werden entfernt.
5. **[Behoben] Wiederholtes langes Textlayout** — §7.5 — begrenzter, threadsicherer Geometriecache mit vollständigem Inhalt-/Stilschlüssel; keine gemeinsam mutierten TextKit-Objekte.

Die bereits geschlossenen Export-/Beenden-, Formen-, Video-Menü-, Guide-Asset-, Datenschutzlink- und Skriptbefunde bleiben geschlossen. Die entsprechenden Regressionen sind im Bericht nachvollziehbar.

### 1.1 Historische Beta-Befunde und Korrekturen

Die stabilen Nummern bleiben erhalten. Die vor den Korrekturen erneut reproduzierten Fehler stehen in der gesicherten Momentaufnahme. Geschlossene Befunde sind unten ausdrücklich als behoben markiert. Frühere Kauf-/Restore- und Store-Vorbereitungsabnahmen des Nutzers bleiben anerkannt; der lokale Release-Build ersetzt die Prüfung des tatsächlichen Store-Kandidaten nicht.

## 2. Quick wins

Die dokumentierten Codekorrekturen sind abgeschlossen. Vor dem Upload den tatsächlich einzureichenden Store-Kandidaten einschließlich Versions-/Buildnummer prüfen und die gesonderten realen Aufnahme-/Tonfälle auf macOS 26 abnehmen. Diese manuellen Abnahmen sind keine noch offenen Codebefunde.

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

## 9. Dead code / duplication / refactor

### 9.1 Xcode-Scheme führt die vorhandenen Tests nicht aus

_REMOVED: Das leere Testables-Verzeichnis ist im dokumentierten Workflow mit expliziten Testskripten kein neuer eigenständiger Produktfehler. Ob Tests lauffähig sind, wird hier konkret über §9.2 und §12.2 berichtet. Keine Umstellung des Testsystems allein wegen des leeren Scheme-Eintrags empfohlen._

### 9.2 Workspace-/UI-Abhängigkeit bricht fünf native Testskripte

_REMOVED: Behoben am 29.10.2026._ WorkspaceModel kennt den Fenstercontroller nicht mehr direkt. Ein injizierbarer Callback wird vom produktiven QuickCapturePanelController eingerichtet. Damit benötigen die isolierten Skripte keine zusätzliche UI-Quelldatei oder Controller-Attrappe. Alle fünf Skripte wurden nach den finalen Workspace-Änderungen erneut sequenziell ausgeführt und bestehen mit Exit 0: `build/ReleaseFixes/Scripts/FINAL-transfer-privacy.log`, `FINAL-library.log`, `FINAL-scroll.log`, `FINAL-settings.log`, `FINAL-trash.log`.

## 10. Cross-cutting recommendations

### 10.1 Reihenfolge der Korrekturen

Auch die zuletzt offenen fünf Medium-Befunde sind geschlossen. Den tatsächlichen Store-Kandidaten und echte Aufnahme-/Tonabläufe getrennt vom lokalen Build bestätigen; keine neue Plattform- oder Kaufabnahme aus den Codeprüfungen ableiten.

### 10.2 Archiv und App Store Connect

Der heutige Release-Build enthält x86_64 und arm64, Bundle-ID `com.snaprivo.app`, Version `1.0`, Build `2`, Mindestversion `26.0`. Die reguläre `codesign --verify --deep --strict`-Prüfung besteht; die isolierte Shell konnte der Zertifikatskette zunächst nicht vertrauen. Das lokale entwicklersignierte Release-Bundle ist kein exportiertes Store-Archiv. Ob Build 2 in App Store Connect bereits verbraucht ist, wurde nicht abgefragt. Die vom Nutzer bestätigte Kauf-/Restore- und Store-Vorbereitung bleibt anerkannt; keine pauschale Wiedereröffnung dieser Abnahmen. Den tatsächlich einzureichenden Kandidaten einschließlich Installation/Update und echter Aufnahme auf macOS 26 separat prüfen.

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
- Kein Release-Archiv, keine neuen StoreKit-Käufe, keine Store-Signierungs-/App-Store-Connect-Abnahme und kein Test auf macOS-26-Hardware. Die lokale Release-Signatur wurde am 29.10. separat verifiziert. Ausgeführt auf lokalem arm64-Mac mit macOS 27 und Xcode 27; Deployment Target bleibt 26.

## 12. Verification

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

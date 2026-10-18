# Code-Audit — Snaprivo vor der ersten TestFlight-Beta

Stand: 13. Oktober 2026. Geprüft wurde der aktuelle lokale Quellstand in `/Users/simon/Woerk/Swift/Snaprivo`, nicht ein bereits hochgeladenes App-Store-Archiv. Der Nutzer hat TestFlight als ersten Distributionsweg bestätigt. Methode: frischer Release-Build, drei getrennte Leseprüfungen, anschließende SwiftUI-/AppKit-Prüfung, Verifikation der Befunde und bestehende Tests plus ein gezielter synthetischer Reproducer. Der ursprüngliche Audit war ausschließlich lesend. Die anschließend vom Nutzer beauftragten Korrekturen sind nachfolgend getrennt gekennzeichnet; Befundnummern bleiben erhalten.

34 produktive Swift-Dateien; 9.483 Swift-Zeilen einschließlich Tests/Fixtures. Kein versionierter Git-Snapshot vorhanden: die Projektdateien sind derzeit untracked. Fingerprint des ursprünglichen Audit-Stands der produktiven Swift-Dateien, `project.pbxproj`, Info.plist und Entitlements: `679217882b23d2ff61f668cfcb080f2be38c650729820a5e9cd005ebfbe91a5e` (SHA-256). Build-/Package-Caches und generierte Bilder wurden nicht als Quellcode bewertet.

**Nacharbeit (13.10.2026):** §6.1 und §3.1 sind korrigiert und mit gezielten Export-/Lifecycle-Regressionen geprüft. §2.1 ist ebenfalls korrigiert: „© 2026 Simon Raach“ wurde vom Nutzer bestätigt, eingetragen und im Debug-/Release-Bundle verifiziert. Die übrigen Befunde bleiben als eigene Aufgaben offen.

**Ursprüngliche Bewertung:** Vor einer Testerfreigabe §6.1 beheben; vor dem Upload den fehlenden Copyright-Eintrag §2.1 ergänzen. §3.1 sollte ebenfalls in den ersten Beta-Build. Kein bestätigter Critical-Befund. Die zwei High-Befunde sind eine reproduzierte Datenschutz-/Exportabweichung und fehlende Upload-Metadaten. Eine erfolgreiche TestFlight-Verarbeitung oder App-Review-Freigabe wird nicht behauptet.

## 1. Executive summary

1. **[High] Kopieren während einer Abdeck-Geste exportiert unmaskierte Pixel** — §6.1 — [Snaprivo/Editor/EditorModel.swift:423–429](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorModel.swift:423); mit synthetischen Pixeln reproduziert. **Korrigiert**, Nachweis unter §6.1.
2. **[High, korrigiert] macOS-Copyright fehlte im fertigen Release-Bundle** — §2.1 — [Snaprivo/Resources/Info.plist:4–43](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Resources/Info.plist:4). Laut Apple vor App-Store-Connect-Upload erforderlich.
3. **[Medium, korrigiert] PNG-Dateiexport wurde beim Beenden nicht abgewartet** — §3.1 — [Snaprivo/Editor/EditorModel.swift:404–420](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorModel.swift:404), [Snaprivo/App/WorkspaceModel.swift:193–200](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/WorkspaceModel.swift:193).
4. **[Medium] Große Bilddateien werden vor der Größenprüfung vollständig eingelesen** — §5.1 — [Snaprivo/App/WorkspaceModel.swift:67–82](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/WorkspaceModel.swift:67); lokale Paket-/Cache-Reads haben ebenfalls keine Byte-Grenze.
5. **[Medium] Nach Prozessabbruch bleiben versteckte Video-Arbeitsdateien ohne Wiederanlaufpfad** — §5.2 — [Snaprivo/Capture/VideoRecording.swift:120–147](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Capture/VideoRecording.swift:120).
6. **[Medium] Bearbeitbare Projektdateien sind nicht für Finder-Öffnen registriert** — §8.1 — [Snaprivo/Resources/Info.plist:5–41](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Resources/Info.plist:5), [Snaprivo/App/SnagForgeApp.swift:1–163](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/SnagForgeApp.swift:1).
7. **[Medium] Canvas bietet keine zugänglichen einzelnen Objekte** — §8.2 — [Snaprivo/Editor/EditorCanvas.swift:84–89,684–699](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorCanvas.swift:84).

**Positiv:** Frischer universeller Release-Build für arm64/x86_64 erfolgreich; keine Swift-Compilerwarnung. Sandbox und Hardened Runtime aktiv. Signaturprüfung erfolgreich. 74 Domain-Tests sowie native Capture-, Autosave-, Renderer-, Transfer-/Datenschutz- und Videotests bestanden. Bereits bestätigte Abdeckungen werden von den bestehenden PNG-/Clipboard-Tests korrekt geschützt. Keine privaten Capture-APIs, Produkt-Telemetrie, Netzwerkclients oder eingebetteten Zugangsdaten gefunden.

## 2. Quick wins

### 2.1 Copyright vor dem ersten Upload ergänzen

- **Status:** Korrigiert am 13.10.2026; ursprüngliche Severity High.
- **Location:** [Snaprivo/Resources/Info.plist](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Resources/Info.plist:5).
- **Ursprünglicher Befund:** `NSHumanReadableCopyright` fehlte in Quell-Plist und erzeugtem Release-Bundle. Apple nennt den Eintrag als Vorbereitung für macOS-Uploads. [Apple: Prepare for app distribution](https://help.apple.com/xcode/mac/current/en.lproj/dev91fe7130a.html).
- **Korrektur:** Der Nutzer hat „© 2026 Simon Raach“ ausdrücklich als Rechteinhaber-Eintrag bestätigt. Dieser Wert steht jetzt unter `NSHumanReadableCopyright` in der gemeinsamen Info.plist für Debug und Release.
- **Nachweis:** Plist-Validierung sowie Debug-/Release-Build erfolgreich. Der exakte Wert ist in beiden erzeugten App-Bundles vorhanden; Release-Signaturprüfung erfolgreich. Logs: `/tmp/snaprivo-copyright-debug.log`, `/tmp/snaprivo-copyright-release.log`. Archiv-/Organizer-Validierung folgt beim Upload durch den Nutzer und ist nicht als durchgeführt markiert.

## 3. Concurrency

### 3.1 PNG-Export hat keinen in der Beenden-Sequenz abgewarteten Task

- **Status:** Korrigiert am 13.10.2026; ursprüngliche Severity Medium.
- **Location:** [EditorModel.swift](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorModel.swift:408), [WorkspaceModel.swift](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/WorkspaceModel.swift:190), [Regressionen](/Users/simon/Woerk/Swift/Snaprivo/Tests/EditorExportChecks.swift:80).
- **Ursprünglicher Befund:** Nach Wahl des PNG-Ziels lief Rendering/Schreiben ohne in der Beenden-Sequenz gespeicherten Task. Direktes Beenden konnte ohne fertige Exportdatei enden.
- **Korrektur:** Der Editor besitzt den PNG-Task bis zum Abschluss. Beenden, Projektwechsel, Projektimport und Entfernen des geöffneten Projekts warten darauf und sichern anschließend den aktuellen bearbeitbaren Projektstand. Ein noch unbestätigter Speicherdialog wird abgebrochen; ein gestarteter Export läuft zu Ende. Währenddessen werden neue Exporte blockiert. Security-Scoped-Zugriff und atomarer Dateiaustausch bleiben erhalten. Ein Exportfehler verhindert Beenden/Projektwechsel bis zur Bestätigung der Fehlermeldung; der Projektstand wird trotzdem gesichert.
- **Nachweis:** Kontrolliert angehaltener Writer: Quit bleibt ausstehend, Datei entsteht erst nach Freigabe und enthält die Abdeckung. Simulierter Schreibfehler: vorhandenes Ziel unverändert, Projekt gesichert, Quit abgelehnt bis zur Fehlerbestätigung. Projektwechsel plus gleichzeitiges Quit wartet auf den alten Export, bevor der Editor ersetzt wird. `./scripts/test-transfer-privacy.sh` erfolgreich; `/tmp/snaprivo-audit-fix-transfer.log`.

Keine zusätzlichen belegten Actor-/Sendable-Fehler. Der frische Release-Build lief mit Swift 6 und vollständiger Concurrency-Prüfung ohne entsprechende Warnungen. Selector-/Scroll-/Video-Continuations haben Abschluss-/Abbruchpfade; `ProjectStore` serialisiert Änderungen und verwendet zusätzlich eine prozessübergreifende Sperre. Diese Aussagen ersetzen keine Tests aller Systemunterbrechungen.

## 4. API modernity

_No findings._

Keine Deprecation-/Swift-Warnung im produktiven frischen Release-Build. Die einzige Build-Warnung betrifft übersprungene AppIntents-Metadaten ohne AppIntents-Abhängigkeit; daraus ergibt sich kein Upload-Defekt. Native Testfixtures verwenden teilweise ältere AVAssetWriter-Einstiege, die weiterhin die Mindestversion 26 unterstützen und nicht im App-Target ausgeliefert werden.

## 5. Bugs / logic errors

### 5.1 Byte-Grenzen greifen nicht vor allen lokalen Bild-/Paket-Reads

- **Location:** [Snaprivo/App/WorkspaceModel.swift:67–82](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/WorkspaceModel.swift:67); [Packages/SnagForgeDomain/Sources/SnagForgeDomain/ProjectStore.swift:148–154,295–298](/Users/simon/Woerk/Swift/Snaprivo/Packages/SnagForgeDomain/Sources/SnagForgeDomain/ProjectStore.swift:148).
- **What:** Bildimport lädt die gesamte Datei in `Data`, bevor Pixelmaße und 100-MP-Grenze geprüft werden. Das Öffnen lokaler Projektoriginale und Einlesen lokaler Thumbnail-Caches hat ebenfalls keine Byte-Grenze.
- **Why:** Ein sehr großes TIFF bzw. eine beschädigte/manuell veränderte Paketdatei kann bereits vor der fachlichen Validierung hohen Speicherverbrauch oder Prozessabbruch verursachen. Dieser Ressourcenfall wurde im Audit statisch verfolgt; kein OOM auf dem Nutzer-Mac absichtlich ausgelöst. Portable Projektimporte besitzen bereits gesonderte Größen-/Regular-File-Prüfungen.
- **Action:** Für alle Eingänge zuerst reguläre Datei und Byte-Limit prüfen; Bilder möglichst aus einer Datei-ImageSource inspizieren/dekodieren. Thumbnail-Caches begrenzen bzw. bei Überschreitung verwerfen. Synthetische Tests für übergroße und mehrseitige Dateien ergänzen.
- **Severity:** Medium.

### 5.2 Versteckte Video-Arbeitsdateien nach Crash werden nicht wiederaufgenommen

- **Location:** [Snaprivo/Capture/VideoRecording.swift:120–147](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Capture/VideoRecording.swift:120); [Snaprivo/App/CaptureActions.swift:74–79](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/CaptureActions.swift:74).
- **What:** Die Aufnahme schreibt zunächst eine versteckte `.recording.mp4`. Finalisierung/Fehlerbereinigung laufen nur in der aktuellen Sitzung; ein Startscan für alte Arbeitsdateien fehlt, und die normale Auflistung überspringt versteckte Dateien.
- **Why:** Nach Crash/erzwungenem Beenden kann ein unvollständiger Clip unsichtbar Speicher belegen. Die laufende Aufnahme wird danach nicht als Problem angezeigt oder wiederhergestellt. Normales App-Beenden ist gesondert implementiert und bereits geprüft.
- **Action:** Beim Neustart alte Arbeitsdateien prüfen, als wiederherstellbar/fehlgeschlagen kenntlich machen und eine bewusste Aufbewahrungs-/Bereinigungsregel anbieten. Unfertige Filme nicht als erfolgreiche Aufnahme ausgeben.
- **Severity:** Medium.

## 6. Security

### 6.1 Live-Abdeckung und exportierter Stand können während einer Geste auseinanderfallen

- **Status:** Korrigiert am 13.10.2026; ursprüngliche Severity High.
- **Location:** [Gemeinsame Vorbedingung und Exportwege](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorModel.swift:58), [Editor-Buttons](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Features/EditorView.swift:39), [Exportmenü](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/SnagForgeApp.swift:30), [Regressionen](/Users/simon/Woerk/Swift/Snaprivo/Tests/EditorExportChecks.swift:44).
- **Ursprünglicher Befund:** Der Canvas zeigte den Live-Entwurf, während Kopieren und PNG den letzten bestätigten Stand exportierten. Ein temporärer synthetischer Reproducer bestätigte schwarze Live-Abdeckung bei rotem kopiertem Originalpixel.
- **Korrektur:** `hasExportableImage` verlangt einen bestätigten Canvas ohne aktive Geste/Live-Entwurf, offenen Zuschnitt oder Auflösungsdialog. Kopieren und beide PNG-Einstiege prüfen dies vor jeder Mutation. Buttons und Exportmenü verwenden dieselbe Vorbedingung; ⌘C erreicht dieselbe geschützte Modellfunktion. Ein abgelehnter Aufruf verändert weder Zwischenablage noch Exportdatei oder Entwurf. Nach Loslassen wird der bestätigte Stand exportiert. Die Kopieranimation bleibt auf ihren Button beschränkt.
- **Nachweis:** Synthetische Abdeckung beim Zeichnen, Verschieben und Vergrößern: Live-Pixel schwarz, während der Geste weder Clipboard-PNG noch Änderung am bestehenden Dateiziel. Auch ein übrig gebliebener Entwurf ohne Gestenflag sperrt den Export. Nach Bestätigung liefern privates Clipboard und PNG schwarze Pixel; Wiederöffnen enthält die bearbeitbaren Objekte. `./scripts/test-transfer-privacy.sh` erfolgreich, ohne Nutzer-Zwischenablage oder vertrauliche Bildschirmdaten; `/tmp/snaprivo-audit-fix-transfer.log`.

**Datenschutz-/API-Prüfung ohne weiteren Defekt:** Öffentliche ScreenCaptureKit-/TCC-Wege, keine TCC-Umgehung; Sandbox nur mit Zugriff auf vom Nutzer gewählte Dateien. Projektarchive haben Regular-File-/Symlink-/Größen-/Digest-Prüfungen. Bearbeitbare Projekte/Backups enthalten das Original ausdrücklich; flache Abdeck-Ausgaben werden separat geprüft. Keine produktiven Netzwerk-/Tracking-SDKs gefunden.

**Privacy Manifest korrekt eingeordnet:** Im Release-Bundle fehlt `PrivacyInfo.xcprivacy`. Die aktuelle [Apple-Referenz](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) verlangt Required-Reason-API-Deklarationen für iOS/iPadOS/tvOS/visionOS/watchOS; macOS ist in dieser Aufzählung nicht enthalten. Allein UserDefaults-/Disk-Space-Nutzung ist hier deshalb kein belegter macOS-Upload-Blocker. Datenerhebung/Tracking und bestimmte Drittanbieter-SDKs haben davon unabhängige Regeln; derzeit wurde nur ein eigenes lokales Domain-Paket gefunden. App-Privacy-Angaben im Portal müssen weiterhin mit dem tatsächlichen Datenfluss übereinstimmen.

## 7. Performance

### 7.1 Core-Image-Kontext wird für jede Blur-Komposition neu erzeugt

- **Location:** [Snaprivo/Editor/EditorRenderer.swift:17–25](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorRenderer.swift:17); [Snaprivo/Editor/EditorCanvas.swift:58–79](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorCanvas.swift:58).
- **What:** `drawBlur` erzeugt je Unschärfeobjekt einen neuen `CIContext`. Live-Änderungen der Unschärfe lösen weitere Kompositionen aus.
- **Why:** Wiederholte Kontextinitialisierung kann die Vorschau bei großen Bildern/vielen Blur-Objekten verteuern. Der Canvas begrenzt bereits auf einen Filterjob und verwendet fertige Vorschauen; ein unkontrolliertes Anwachsen paralleler Jobs oder garantiertes Filtern des gesamten Bildes wird nicht behauptet. Laufzeitprofiling steht aus.
- **Action:** Wiederverwendung eines dafür geeigneten Renderkontexts und Zwischenergebnisse prüfen; Auswirkungen bei mehreren Blur-Regionen messen. Die bereits vorhandene Begrenzung auf einen Job erhalten.
- **Severity:** Medium.

### 7.2 Jeder Autosave lädt Bibliotheks- und Papierkorbmetadaten erneut vollständig

- **Location:** [Snaprivo/App/WorkspaceModel.swift:47–58](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/WorkspaceModel.swift:47); [Snaprivo/Editor/EditorModel.swift:263–289](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorModel.swift:263); [Packages/SnagForgeDomain/Sources/SnagForgeDomain/ProjectStore.swift:285–301](/Users/simon/Woerk/Swift/Snaprivo/Packages/SnagForgeDomain/Sources/SnagForgeDomain/ProjectStore.swift:285); [Snaprivo/Features/LibraryView.swift:12–13](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Features/LibraryView.swift:12).
- **What:** Nach jeder gespeicherten Editorrevision wird die ganze Bibliothek einschließlich Papierkorb erneut eingelesen. Dabei werden Dokumente/Thumbnails geladen und sortiert; die View filtert/sortiert nochmals.
- **Why:** Bei vielen Projekten kann der 450-ms-Autosave-Takt wiederholt unnötige Dateiarbeit und Wartezeit auf der Store-Sperre erzeugen. Dies ist ein belegter Arbeitsumfang, kein gemessener Performancefehler auf dem kleinen aktuellen Bestand.
- **Action:** Das geänderte Bibliotheksitem gezielt aktualisieren bzw. Refreshes zusammenfassen, Thumbnail-Caches nach Bedarf laden und mit größerer synthetischer Bibliothek messen.
- **Severity:** Medium.

## 8. SwiftUI / UI

### 8.1 Finder-Öffnen exportierter Projekte/Sicherungen ist nicht angeschlossen

- **Location:** [Snaprivo/Resources/Info.plist:5–41](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Resources/Info.plist:5); [Snaprivo/App/SnagForgeApp.swift:1–163](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/SnagForgeApp.swift:1); [Snaprivo/App/WorkspaceModel.swift:244–275](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/App/WorkspaceModel.swift:244).
- **What:** Exportierte UTIs sind deklariert, aber `CFBundleDocumentTypes` und ein eingehender Datei-/URL-Handler fehlen. Die vorhandenen Importaktionen funktionieren nur über die App-Menüs.
- **Why:** Doppelklick oder „Öffnen mit Snaprivo“ auf `.snaprivo`/`.snaprivobackup` führt nicht verlässlich zum vorhandenen Importablauf. Das entspricht noch nicht der üblichen Mac-Dateibedienung.
- **Action:** Dokumenttypen registrieren und eingehende URLs in die vorhandenen, sandboxgerechten Import-/Sicherungsabläufe leiten. Für Backups die additive Wiederherstellung erläutern; keine stille Ersetzung.
- **Severity:** Medium.

### 8.2 Objekte im Canvas sind für VoiceOver/Tastatur nicht einzeln erreichbar

- **Location:** [Snaprivo/Editor/EditorCanvas.swift:84–89,684–699](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Editor/EditorCanvas.swift:84); [Snaprivo/Features/EditorView.swift:60–71](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo/Features/EditorView.swift:60).
- **What:** Die Bildfläche ist eine Accessibility-Gruppe; einzelne Pfeile, Formen und Textobjekte haben keine zugängliche Objektliste oder entsprechenden AX-Kindelemente. Die Canvas-Tastenbehandlung bietet keine gleichwertige Objektauswahl/-bewegung.
- **Why:** Toolbar-Labels allein erlauben keine vollständige Bearbeitung ohne Zeigegerät. Q03 ist daher weiterhin offen. Kein echter VoiceOver-Durchlauf wurde in diesem Audit durchgeführt.
- **Action:** Zugängliche Objektliste bzw. AX-Objekte mit Auswahl-, Bearbeitungs- und Bewegungsaktionen ergänzen und anschließend mit VoiceOver/Tastatur prüfen.
- **Severity:** Medium.

## 9. Dead code / duplication / refactor

### 9.1 Xcode-Scheme führt die vorhandenen Tests nicht aus

- **Location:** [Snaprivo.xcodeproj/xcshareddata/xcschemes/Snaprivo.xcscheme:4](/Users/simon/Woerk/Swift/Snaprivo/Snaprivo.xcodeproj/xcshareddata/xcschemes/Snaprivo.xcscheme:4); [scripts/test.sh:1](/Users/simon/Woerk/Swift/Snaprivo/scripts/test.sh:1); [scripts/test-autosave.sh:1](/Users/simon/Woerk/Swift/Snaprivo/scripts/test-autosave.sh:1).
- **What:** Die TestAction enthält keine Testables. Die vorhandenen Domain-/nativen Prüfungen laufen ausschließlich über separate Skripte.
- **Why:** Ein Testlauf allein über das Xcode-Scheme deckt die umfangreichen vorhandenen Prüfungen nicht ab. Das ist eine Integrationslücke, keine Behauptung, dass Tests fehlen.
- **Action:** Tests an Scheme/Testplan anbinden oder einen verbindlichen Skript-Gesamtlauf vor Archivierung einrichten und für Xcode-Nutzer sichtbar dokumentieren.
- **Severity:** Low.

Nicht als Defekt übernommen: das alte interne Bundle-/Speicherpräfix (bewusster Kompatibilitätsvertrag); der angeblich unerreichbare Icon-Fallback (das gebaute Bundle enthält tatsächlich `Resources/AppIcon.icns`); nur testseitig verwendete Helfer. Keine belegte umfangreiche Löschliste. Die großen Canvas-/Editor-Dateien allein sind kein Upload-Blocker und rechtfertigen vor der Beta keinen breit angelegten Umbau.

## 10. Cross-cutting recommendations

### 10.1 Reihenfolge vor der TestFlight-Testerfreigabe

- [x] §6.1: gemeinsame Exportvorbedingung und Regression für Zeichnen/Verschieben/Größenänderung, Clipboard und PNG.
- [x] §2.1: bestätigten Copyright-Eintrag ergänzt und in Debug-/Release-Bundles verifiziert. Die abschließende Archivprüfung gehört zum Organizer-Upload.
- [x] §3.1: PNG-Task beim Beenden und Editorwechsel abwarten; Schreibfehler/Fehlerbestätigung und gleichzeitigen Projektwechsel geprüft.
- [ ] §5.1: lokale Eingangsgrößen vor großen Reads begrenzen, spätestens vor breiterem Testerkreis.
- [ ] Bekannte Beta-Grenzen in „What to Test“ nennen: manuelles Scrollen, Video ohne Ton, feste Region, Videoordner statt Bibliotheks-/Backup-Integration; offene Mindestversions-/Mehrdisplay-/TCC-Tests.

### 10.2 Archiv und App Store Connect

Geprüfter lokaler Release-Stand: Snaprivo **0.1.0 (Build 2)**, Minimum **macOS 26.0**, Universal **arm64 + x86_64**, Bundle-ID **com.snagforge.app**, Kategorie Produktivität. Development-Team ist gesetzt; Sandbox/Hardened Runtime aktiv. Die Signatur ist auf dem Datenträger gültig. Das lokale Build ist mit **Apple Development** signiert und enthält kein eingebettetes Distributionsprofil. Das ist keine Feststellung über ein von Organizer neu signiertes Store-Archiv.

Vor Upload in Xcode archivieren und über den App-Store-Connect-Distributionsweg validieren lassen. Passenden App-Datensatz/Bundle-ID, Program-Mitgliedschaft und Profil-/Anwendungsidentität im resultierenden Archiv kontrollieren. Die Bundle-ID vor dem ersten Upload bewusst beibehalten; sie ist anschließend in App Store Connect nicht austauschbar. Bei erneutem Upload eine noch nicht verwendete Buildnummer wählen. [Apple: Vorbereitung](https://help.apple.com/xcode/mac/current/en.lproj/dev91fe7130a.html), [Upload](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

Testinformationen und Feedbackadresse im Portal ergänzen. Externe Tester können eine Beta-Review benötigen; interne und externe Verteilung getrennt planen. [Apple: TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

Verwendete Toolchain: Xcode **27.0 / 27A266a**, SDK macOS 27.0. Die Buildnummer stimmt mit Apples veröffentlichtem Xcode-27-Release überein; kein allein aus dem SDK-Namen abgeleiteter Beta-Blocker. [Apple-Releases](https://developer.apple.com/cn/news/releases/). Endgültige Upload-Eignung bestätigt erst die Organizer-/App-Store-Connect-Validierung.

### 10.3 Sicherheits- und Lifecycle-Invarianten

§6.1 und §3.1 sind mit gemeinsamer Exportvorbedingung und besessenem PNG-Task umgesetzt. Für den weiterhin offenen §5.1 Größen-/Dateiregeln an allen Eingängen konsistent machen. Vor der Beta kleine überprüfbare Korrekturen; Performance-/Dateiöffnungs-/Accessibility-Ausbau jeweils als eigene Aufgabe behandeln.

## 11. What was NOT audited

- Keine App-Store-Connect-Anmeldung, kein App-Datensatz erstellt, kein Upload, keine Organizer-/Servervalidierung und keine Beta-Review.
- Kein Public-Release-Go: Kaufmodell, StoreKit, externe Metadaten/URLs, Verträge und rechtliche Rechteinhaberschaft nicht geprüft.
- Kein neuer physischer Capture-Durchlauf in diesem Audit. Bereits dokumentierte Desktop-Abnahmen bleiben Hintergrund; keine Tests durch TCC-Reset oder Abschwächung von Schutzmechanismen.
- Keine separate Hardwareprüfung unter macOS 26, auf Intel, mehreren Displays/Spaces, unter Sleep/Rechteentzug oder bei tatsächlich vollem Datenträger.
- Kein Instruments-/Leckprofiling, keine Langzeitvideo-/A/V-Synchronitätsabnahme, kein echter VoiceOver-/Lokalisierungsdurchlauf.
- Kein umfassendes Fuzzing aller Importformate oder Laufzeitbeweis für jeden statischen Befund. Die Nacharbeit prüft die echte Workspace-Beenden-Sequenz mit kontrolliert angehaltenem Export; der Nutzerprozess wurde dafür nicht beendet. Ein echter Betriebssystem-Force-Quit wird dadurch nicht abgesichert.
- Keine algorithmische Vollkorrektheitsgarantie für Scroll-Stitching oder Drittanbieter-/Apple-Frameworkinternals.

## 12. Verification

### 12.1 Ursprünglich verifizierte High-Befunde

- **§6.1:** `EditorModel.swift:54` verwendet den Entwurf zur Anzeige; `:423–429` erlaubt Kopieren trotz aktiver Geste und nimmt `history.objects`; `EditorCanvas.swift:709–715` leitet ⌘C dorthin. Temporärer Reproducer lief erfolgreich mit privater Zwischenablage: schwarzer Live-Pixel, roter Exportpixel. Bestehende Abdeck-Tests prüfen bestätigte Objekte und bestanden weiterhin.
- **§2.1, ursprünglicher Audit-Stand:** vollständige `Info.plist:4–43` und Build-Einstellungen `project.pbxproj:68–69` geprüft; `NSHumanReadableCopyright` fehlte zusätzlich in `/tmp/Snaprivo-Audit-20261013/Build/Products/Release/Snaprivo.app/Contents/Info.plist`. Apples macOS-Upload-Vorbereitung fordert diesen Wert ausdrücklich.

### 12.2 Builds und Tests

| Prüfung | Ergebnis / Beleg |
|---|---|
| Frischer Release-Build, separater DerivedData-Ordner | erfolgreich; `/tmp/snaprivo-audit-release.log` |
| Swift-Compilerwarnungen | 0; nur AppIntents-Metadatenhinweis |
| Signatur `codesign --verify --deep --strict` | erfolgreich außerhalb der Tool-Sandbox; lokales Apple-Development-Build |
| Entitlements | Sandbox + user-selected read/write, Hardened Runtime |
| Domain `./scripts/test.sh` | 74 Tests erfolgreich; `/tmp/audit-domain.log` |
| Autosave | erfolgreich; `/tmp/audit-autosave.log` |
| PNG/Renderer/Crop | erfolgreich; `/tmp/audit-renderer.log` |
| Projekttransfer/Backup/Abdecken/Berechtigungszustände | erfolgreich; `/tmp/audit-transfer.log` |
| Video/MP4/Speicherung | erfolgreich; `/tmp/audit-video.log` |
| Eingefrorene Auswahl/Koordinaten/Bestätigung/Abbruch | erfolgreich; `/tmp/audit-capture.log` |
| Zusätzlicher Live-Abdeck-Kopierfall | Defekt bestätigt; `/tmp/audit-gesture-repro.log` |

Die Standard-Signaturprüfung innerhalb der eingeschränkten Tool-Umgebung lieferte zunächst einen Vertrauensfehler; die anschließende identische, nur lesende Prüfung außerhalb dieser Umgebung war erfolgreich. Daraus wird kein Produkt-Signierungsdefekt abgeleitet. Temporäre Compiler-/Auditdateien enthalten ausschließlich synthetische Daten. Produktcode wurde im Audit nicht geändert.

### 12.3 Nacharbeit und Regressionen (13.10.2026)

- `./scripts/test-transfer-privacy.sh`: neue Export-/Beenden-Regressionen sowie vorhandene Transfer-/Privacy-/Berechtigungsprüfungen erfolgreich. Log: `/tmp/snaprivo-audit-fix-transfer.log`.
- `./scripts/test-autosave.sh`: erfolgreich; `/tmp/snaprivo-audit-fix-autosave.log`.
- `./scripts/test-canvas.sh`: Canvas-/Zoom-/Crop-Prüfungen einschließlich Exportsperre bei lokalen AppKit-Mausereignissen und erneuter Freigabe nach Mouse-up erfolgreich; `/tmp/snaprivo-audit-fix-canvas.log`.
- `./scripts/test.sh`: 74 Domain-Tests erfolgreich; `/tmp/snaprivo-audit-fix-domain.log`.
- Debug- und Release-Builds erfolgreich; keine Swift-Compilerwarnung, nur der bekannte AppIntents-Metadatenhinweis. Logs: `/tmp/snaprivo-audit-fix-build.log`, `/tmp/snaprivo-audit-fix-release.log`.
- Finale Release-Signatur mit `codesign --verify --deep --strict` erfolgreich. Lokaler Apple-Development-Build mit Sandbox, benutzergewähltem Dateizugriff und Development-Entitlement `get-task-allow`; kein Store-distribuiertes Archiv. Bei Organizer-Distribution resultierende Signatur/Entitlements erneut prüfen.
- Fingerprint nach den Code- und Copyright-Korrekturen: `eebda260dbac68b540e70171038b200d25088cb696103b585173b5214c3943af` (SHA-256; produktive Swift-Dateien in App und Domain-Sources plus pbxproj/Info.plist/Entitlements; relative Pfade sortiert, jeweils Pfad + NUL + Inhalt + NUL).
- Copyright „© 2026 Simon Raach“ nach Nutzerbestätigung eingetragen. Debug-/Release-Builds und Bundle-Prüfung erfolgreich; Release-Signatur gültig. Logs: `/tmp/snaprivo-copyright-debug.log`, `/tmp/snaprivo-copyright-release.log`. Keine App-Store-Connect-Verarbeitung oder Organizer-Validierung durchgeführt.

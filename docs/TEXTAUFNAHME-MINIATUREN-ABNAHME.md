# Textaufnahme und Miniaturstapel

Stand: 27.10.2026. Ergänzung zum vom Nutzer beschriebenen unklaren Foto/OCR-Ablauf und zum Wunsch nach mehreren schwebenden Vorschauen unten links.

## Bedienung

- **Textaufnahme – nur Text kopieren** im Foto-Menü oder **⌃⇧7** wählen. Bereich aufziehen und **Text** bzw. Enter drücken. Für QR **QR-Code scannen** bzw. **⌃⇧8**; die Auswahl zeigt **QR**. Auch im Foto-Menü der bereits geöffneten Bereichsauswahl verfügbar. Foto/Video/Scroll behalten ihre eigenen Ziele.
- Die App bleibt beim Erfassen im Hintergrund. Ein schwebendes Ergebnis zeigt Fortschritt und Abbrechen, danach erkannten Text, Kopierbestätigung, leeres Ergebnis oder Fehler. **Erneut kopieren** nutzt das vorhandene Ergebnis; **Erkennung wiederholen** verarbeitet denselben Bereich nochmals. Schließen verwirft nur diesen vorübergehenden OCR-Zustand. OCR erzeugt kein gespeichertes Bildprojekt.
- Die automatische Klartextkopie erfolgt erst bei Erfolg. Wurde während der Verarbeitung etwas anderes kopiert, wird die Zwischenablage erhalten und der erkannte Text ausdrücklich zum Kopieren angeboten. QR-/Barcodewerte werden angezeigt und nur auf Knopfdruck kopiert; HTTP(S)-URLs werden ausschließlich bewusst geöffnet.
- **Einstellungen → Aufnahme → Schnellvorschau nach der Aufnahme** bleibt optional. Aktiviert zeigt sie ausschließlich unten links bis zu fünf aktuelle Aufnahmen. Das zuvor ausgeblendete Arbeitsfenster bleibt nach erfolgreicher Aufnahme verborgen; der Editor öffnet sich erst beim Klick auf die Miniatur. Je Miniatur Kopieren, PNG sichern, Anheften, PNG-Datei-Drag und Klick auf das Bild zum Bearbeiten. Mehr öffnet Text/QR und die weiteren vorhandenen Aktionen.
- Das X schließt ausschließlich die betreffende Miniatur. Verdrängte und geschlossene Bilder bleiben als Projekte in der Bibliothek. Der Stapel ist per **Letzte Schnellvorschau anzeigen** wieder erreichbar, solange Miniaturen vorgehalten werden. Beim App-Neustart bleibt die Bibliothek erhalten; der vorübergehende Stapel wird nicht wiederhergestellt.

## Verarbeitung

Ein eigener Aufnahmetyp wird von der Auswahl bis zur Weiterleitung mitgeführt. Text-/QR-Auswahl wird vor der Verarbeitung auf Pro-Zugriff geprüft. Video und Scroll normalisieren das Bildziel; sie können nicht versehentlich in OCR geraten. Die bisherigen TCC-/Sandbox-Wege bleiben erhalten.

Vision arbeitet außerhalb des MainActor. Ein abbrechbares FIFO serialisiert Erkennungsaufträge, statt neue Aufnahmen wegen eines noch laufenden/abbrechenden Auftrags als belegt zurückzuweisen. Kleine Screenshottexte werden nicht durch eine relative Mindesthöhe ausgesiebt. Die reine Textaufnahme führt keine zusätzliche Barcodeerkennung aus. Modellfehler haben weiterhin den schnellen öffentlichen Vision-Fallback; ein leeres genaues Ergebnis erhält ebenfalls einen schnellen zweiten Versuch.

Abbruch gibt den beobachteten UI-Zustand sofort frei. Anforderungskennungen verhindern, dass ein älterer Auftrag eine neue Verarbeitung freigibt oder deren Ergebnis überschreibt. Ein Clipboard-Revisionsvergleich verhindert verspätetes automatisches Überschreiben. Kopierfehler behalten den erkannten Text für einen weiteren Versuch.

Der Stapel hält getrennte Editormodelle für höchstens fünf gesicherte Projekte. Pro-Entzug und Bibliothekswechsel berücksichtigen alle Modelle. Öffnen einer Miniatur wartet auf ausstehende Änderungen im bisherigen Editor. Die PNG-Datei für Drag und Vorschau wird aus dem bestätigten sichtbaren Dokument einschließlich Abdeckungen erzeugt, nicht aus verdeckten Originalpixeln. Keine neuen Abhängigkeiten, privaten APIs oder Formatmigration.

## Prüfungen

- `scripts/test-capture.sh`: Foto/Text/QR/Scroll-Wechsel, tatsächliche Bestätigungsbeschriftung, Koordinaten und Auswahlübernahme.
- `scripts/test-code-recognition.sh`: echte synthetische QR-Codes und lesbarer Screenshottext mit Vision, reine Texterkennung, FIFO, Abbruch wartender/laufender Anfragen und erneute Nutzbarkeit.
- `scripts/test-workflow-polish.sh`: sichtbarer Zustand, Erfolg/Fehler/leeres Ergebnis, erneute Kopie, geänderte Zwischenablage, sofortiger Abbruch und verspätete Ergebnisse; bestehende Bildwechsel-/Filmstreifenprüfungen.
- `scripts/test-quick-capture-integration.sh`: mehrere Aufnahmen, Begrenzung, Schließen ohne Projektverlust, Auswahl des richtigen Editors, linke Bildschirmposition, PNG-Datei-Drag mit Masken, Zuschnitt/Skalierung/Drehung und Anheften.
- `scripts/build-capture-tools-ui.sh`, Start mit `--stack --text-result`: isolierte native Oberfläche mit temporärer Bibliothek und synthetischen Bildern für die visuelle Prüfung.

## Ergebnis der lokalen Prüfung

App-Build erfolgreich. Auswahl-, echte synthetische Vision-OCR-/QR-, Workflow-/Filmstreifen-, Miniaturstapel- und Bibliotheksprüfungen bestanden; außerdem 164 Domain-Tests und native Sprachtests mit Prozessneustarts. 1195 App-, 7 InfoPlist- und 18 Domain-Texte bestehen Katalog-/Compilerprüfung. Der letzte Workflow-Durchlauf umfasst auch Kopierfehler mit erfolgreichem erneutem Klartextschreiben in eine isolierte native Zwischenablage, Clipboard-Konflikte, verspätete abgebrochene Aufträge und Pro-Entzug. Keine erkannten Inhalte werden protokolliert.

Die isolierte native Oberfläche wurde tatsächlich bedient: Fortschritt und Erfolg sichtbar; drei getrennte Miniaturen; Schließen der OCR-Karte und einer einzelnen Miniatur; ältere Miniatur öffnet das korrekte Projekt; Foto-Menü zeigt Textaufnahme und QR. Der Freiraum unter dem Stapel wurde dabei reduziert. Native Größenwechsel dauern kurz und respektieren reduzierte Bewegung. Nachweise ausschließlich mit synthetischen Daten: `build/text-stack-native-ui.png`, `build/text-stack-thumbnails.png`; Logs `build/text-stack-{build,selection,ocr,workflow,integration,library,domain,localization}.log`.

Ein erster Sprachtest verwendete versehentlich die Ressourcen eines älteren Prüf-Builds und scheiterte an dessen fehlenden Werkzeugtexten. Mit dem aktuellen App-Build bestehen die Sprachtests vollständig.

Eine erfolgreiche synthetische OCR-Prüfung garantiert keine Erkennung jedes beliebigen Textbildes. Echte TCC-Erteilung, Bildschirmaufnahme anderer Apps, mehrere physische Monitore und verschiedene Spaces bleiben eine gesonderte Mac-Abnahme.


## Korrektur: Editor erst nach Klick auf die Miniatur

Der Aufnahme-Ablauf hatte das vor der Auswahl ausgeblendete Arbeitsfenster trotz deaktivierter App-Aktivierung wieder nach vorne geordnet. Die erfolgreiche Ausgabe in Schnellvorschau oder OCR lässt Arbeitsfenster und Aufnahmeoptionen jetzt ausgeblendet. Ein vorhandener Miniaturstapel und andere zuvor sichtbare Hilfsfenster dürfen wieder erscheinen. Normaler Editor-Einstieg sowie Wiederherstellung nach Abbruch/Fehler behalten ihren bisherigen Weg. Die native Integrationsprüfung kontrolliert Fenster-Sichtbarkeit, unveränderte Editor-/Bereichsauswahl bis zum Klick, genau einen Öffnungsaufruf für die gewählte Miniatur und keinen erneuten Editor-Aufruf bei einer anschließenden Aufnahme.


Der korrigierte Ablauf besteht den App-Build und `scripts/test-quick-capture-integration.sh`. Die Miniaturausgabe wird unabhängig von der Sichtbarkeit des Arbeitsfensters über einen UI-Adapter ausgelöst. Nachweise: `build/quick-preview-routing-build.log`, `build/quick-preview-routing-tests.log`. Die Fensterprüfung verwendet synthetische AppKit-Fenster und gespeicherte synthetische Bilder; sie erfordert keine Aufnahme fremder Bildschirminhalte und ersetzt keinen vollständigen TCC-Durchlauf.


## Direkte Miniaturaktionen und laufender Build (26.10.2026)

Die laufende Xcode-App stammte beim erneuten Nutzerbericht vom 25.10. um 22:41; die vorherige Fensterkorrektur war erst um 22:45 im Quellstand und um 22:46 im separaten Prüf-Build vorhanden. Ein erfolgreicher Build aktualisiert keinen bereits gestarteten Prozess. Die laufende Nutzer-App wird nicht ungefragt beendet oder ihre ausführbare Datei überschrieben. Für die aktuelle Fassung den neuen Build nach normalem Beenden der bisherigen App öffnen oder den aktuellen Quellstand in Xcode neu starten.

Die Fensterregel wurde zusätzlich von konkreten Kennungen unabhängig gemacht: Nach einer erfolgreichen Hintergrundaufnahme bleiben reguläre Fenster ausgeblendet, auch bei fehlender oder generierter SwiftUI-Kennung. Nur nicht aktivierende schwebende Panels werden wiederhergestellt. Abbruch/Fehler und der normale Editor-Einstieg verwenden weiterhin ihre ursprüngliche Wiederherstellung.

Auf der Miniatur werden bei Hover **Kopieren**, **Text** und **QR** in einer beschrifteten Leiste sichtbar. Dauerhafte Text-/QR-Buttons bleiben für Tastatur/Bedienungshilfen erreichbar. Bildklick, Schließen und Direktaktionen sind getrennte Buttons; Hover selbst startet keine Verarbeitung und öffnet keinen Editor. Kurze Opazitätsänderung, reduzierte Bewegung berücksichtigt. Text-/QR-Aktionen öffnen ein natives Ergebnis-Popover ohne Mehr-Menü. OCR verarbeitet den sichtbaren bestätigten Bildstand einschließlich Abdeckungen und prüft Zugriff, Bildrevision und Eigentümerschaft; Ergebniskopie wird bei veränderter Zwischenablage nicht automatisch ausgeführt.

Erweiterte Integrationstests prüfen auch native Fenster ohne Kennung bzw. mit generierter Kennung sowie echte synthetische Text-OCR, Kopierfehler, erneute Klartextkopie in eine isolierte Zwischenablage, Clipboard-Konflikte und verweigerte Ergebniskopie. `scripts/build-quick-preview-ui.sh` baut eine separate SwiftUI-Prüf-App mit echter Window-Szene, synthetischem Text/QR und ausgeblendetem Hauptfenster; keine Nutzerbibliothek oder Bildschirmfreigabe.


App-Build, erweiterte Miniatur-Integration und 164 Domain-Tests bestehen; Katalog-/Compilerabdeckung mit 1196 App-, 7 InfoPlist- und 18 Domain-Texten vollständig. Der erste zusätzliche OCR-Lauf überschritt auf dem macOS-27-Prüfsystem das 30-Sekunden-Limit des Integrationstests. Die Clipboard-/Ergebniszustände werden deshalb in diesem Test mit dem schnellen echten Vision-Modus auf lesbarem synthetischem Text geprüft; die App behält ihre genaue Erkennung mit vorhandenem schnellen Fehler-/Leerresultat-Fallback. Ein schneller Integrationstest ist keine zugesicherte Laufzeit der genauen Erkennung. Nachweise: `build/preview-hover-build.log`, `build/preview-hover-tests.log`, `build/preview-hover-domain.log`.


Die native Prüfoberfläche zeigt die dauerhaft direkt erreichbaren Text-/QR-Buttons neben Kopieren/Sichern/Anheften (`build/preview-hover-native-controls.png`). Die isolierte SwiftUI-App benötigt wie das Produkt eine Menüleisten-Szene, um nach dem Ausblenden ihres einzigen Arbeitsfensters weiterzulaufen. Die anschließende Bedienung per UI-Prüfwerkzeug lieferte wechselnde Fensterzustände bzw. ungültige Menüelemente; deshalb keine abgeschlossene manuelle Abnahme des Hover-Klickablaufs oder einer echten Bildschirmaufnahme behauptet. Die aktive Nutzer-App und ihre Bibliothek wurden nicht verändert. Den gesamten Ablauf mit tatsächlicher Bildschirmaufnahme nach Start des aktuellen Builds erneut am Mac prüfen.


## Lesbares Schließen-X (27.10.2026)

Das X oben rechts auf einer Schnellvorschau erscheint beim Darüberfahren über die Miniatur sowie bei Tastatur- oder Bedienungshilfen-Fokus auf den Schließen-Button. Ein kräftigeres Symbol auf einer deckenden, der Systemdarstellung folgenden Kreisfläche hält den Kontrast unabhängig vom Bildinhalt. Die Trefferfläche beträgt 24 × 24 Punkte mit 8 Punkten Abstand zum Bildrand. Ohne Hover/Fokus fängt die unsichtbare Schließenfläche keine Bildklicks ab. Die Einblendung respektiert „Bewegung reduzieren“. Schließen entfernt weiterhin ausschließlich die Miniatur und erhält das gespeicherte Projekt.

Nur die Darstellung des Button-Labels wird ausgeblendet; der beschriftete native Button bleibt für Bedienungshilfen erreichbar. In der isolierten SwiftUI-Prüfapp mit synthetischem Bild wurden der Ruhezustand ohne sichtbares X, die Hover-Einblendung und die kontrastreiche Darstellung geprüft. Der finale Fokusaufbau wurde zusätzlich im nativen Accessibility-Baum bestätigt: „Vorschau schließen“ ist dort auch im ausgeblendeten Zustand vorhanden. Ein vollständiger VoiceOver-Bedienlauf wurde dabei nicht durchgeführt.

Der finale App-Build und `scripts/build-quick-preview-ui.sh` bestehen. Nachweise: `/tmp/snaprivo-preview-close-build.log`, `/tmp/snaprivo-preview-close-ui-build.log`. Die laufende Nutzer-App wurde nicht beendet; die Änderung ist im neuen Build unter `build/GuideWorkflowBuild/Build/Products/Debug/Snaprivo.app` enthalten.


Ergänzung vom 27. Oktober: Pfeiltastenauswahl, Eingabe zum Editor und Rückschritt zum Schließen sind umgesetzt. Die anschließend ergänzte Rückgängig-Einblendung beim Schließen wurde auf Nutzerwunsch vollständig entfernt. Die letzte geschlossene Miniatur hinterlässt kein sichtbares Fenster; die Aufnahmen bleiben in der Bibliothek. Explizites Anzeigen aktiviert den Tastaturfokus, neue Aufnahmen bleiben im Hintergrund. Die native Bedienung und die verifizierten Grenzen stehen unter [Bedienverbesserungen](BEDIENVERBESSERUNGEN-27-10-2026.md).


## Schließen ohne schwebenden Hinweis – 27. Oktober 2026

Auf Nutzerwunsch ist „Vorschau geschlossen / Rückgängig“ vollständig entfernt, einschließlich Wiederherstellungszustand, Zehn-Sekunden-Aufbewahrung, Tastaturfokus und zusätzlicher Panelhöhe. Schließen entfernt eine Miniatur aus dem Stapel; nach der letzten Miniatur wird das Panel synchron ausgeblendet. Ein leerer Stapel wird auch durch erneutes Anzeigen nicht sichtbar. Die Bibliotheksprojekte bleiben erhalten. Ausblenden eines noch gefüllten Stapels und dessen erneutes Anzeigen bleiben verfügbar.

Prüfungen: regulärer App-Build, 173 Swift-Testing- und zwei XCTest-Domainprüfungen, native Schnellvorschau-Integration und Katalog-/Compilerabdeckung erfolgreich. Der Integrationstest prüft Nachbarauswahl, verbleibende Miniaturen, unmittelbares Verschwinden des letzten Panels, leere Present-/Restore-Aufrufe und unveränderte Anzahl gespeicherter Projekte; die bestehenden Transfer-/OCR-Prüfungen bleiben enthalten. In der isolierten Test-App mit synthetischen Bildern wurden zwei Miniaturen per Rückschritt und die letzte über X geschlossen: Das Vorschaupanel verschwand vollständig, ohne Rückgängig-Hinweis; alle vier Fixture-Aufnahmen blieben in der Bibliotheks-/Editorleiste sichtbar.


## Miniatur schließen ohne Stapelanimation – 27. Oktober 2026

Auf Nutzerwunsch entfällt die kombinierte Ausblend-/Schiebetransition einzelner Miniaturen und die implizite Layoutanimation des Stapels. Änderungen der Miniaturenliste passen auch die Panelgröße ohne AppKit-Fensteranimation an. Die betreffende Miniatur wird unmittelbar entfernt; die übrigen bleiben in ihrer Reihenfolge erhalten. Die gezielte Fokusweitergabe beim Schließen findet nur statt, wenn zuvor das geschlossene Bild fokussiert war. Ein X-Klick auf eine andere Miniatur setzt keinen zusätzlichen Bildfokus und löst dadurch keinen unnötigen Scrollsprung aus. Die kleinen Hover-Animationen der Bedienelemente bleiben separat.

Prüfungen: App-Build, native Miniatur-Integration mit Schließen/Nachbarauswahl/Panelende und erhaltenen Bibliotheksprojekten, 173 Swift-Testing- plus zwei XCTest-Prüfungen und Katalog-/Compilerabdeckung bestanden. Protokolle unter `build/PreviewRemovalWork/`.

# Native PNG-Freigabe und Öffnen mit (E06)

Stand: 14. Oktober 2026. Implementiert; tatsächlicher Versand über AirDrop/Mail und fremde Erweiterungen wird durch den Nutzer geprüft.

## Verhalten

**Teilen** steht direkt rechts neben **PNG speichern …**, mit demselben Symbol-/Beschriftungsstil und derselben einstellbaren Werkzeuggröße. Der native SwiftUI-ShareLink verwendet die von macOS angebotenen Freigabeziele. AirDrop, Mail und andere Apps hängen von Systemkonfiguration, Verfügbarkeit und installierten Teilen-Erweiterungen ab. Nicht jede installierte App ist automatisch ein Teilen-Ziel.

Ein unveränderlicher `EditorPNGShare` enthält den aktuellen Bildstand. Seine einzige exportierte Darstellung ist `public.png`; CoreTransferable fordert die Bytes asynchron an. Der gemeinsame Renderer läuft in einem Task außerhalb des MainActor. Zuschnitt, Zielgröße und alle Markierungen entsprechen Speichern/Kopieren. Spätere Änderungen ersetzen den bereits angebotenen Bildstand nicht. Die Freigabe enthält weder Projekt-JSON noch Originaldatei. Die Systemvorschau verwendet ein neutrales Bildsymbol, damit sie keine unbearbeiteten Originalpixel zeigt.

Der vorgeschlagene Dateiname endet auf `.png`; Pfad-/Steuerzeichen werden entfernt bzw. ersetzt und die UTF-8-Länge begrenzt. macOS verwaltet seine Transferdateien. Die App legt dafür keinen eigenen dauerhaften Exportcache an. Laufende Canvas-Gesten, unbestätigte Zuschnitte, Größenentwürfe, PNG-Export und anstehendes Beenden sperren die Aktion. Abbruch/Fehler im Teilen-Ablauf werden vom System behandelt; sie verändern das Projekt nicht.

## Öffnen mit

Der zusätzliche Button rechts neben Teilen zeigt sein Symbol über der Beschriftung und öffnet ein natives NSMenu. Die Gruppe Teilen/Öffnen mit ist durch einen senkrechten Strich von PNG speichern getrennt. Das Menü zeigt die von `NSWorkspace.urlsForApplications(toOpen: .png)` gemeldeten Apps; Vorschau wird über ihre Bundle-ID ermittelt und steht zuerst. Doppelte App-Pfade und die eigene App werden entfernt; App-Namen sind lokalisiert. Die Liste wird bei jedem Öffnen des Menüs neu geladen. Der reguläre SwiftUI-Button verwendet dieselben Größen, Hover-/Druckzustände und Accessibility-Eigenschaften wie die übrigen Toolbar-Aktionen; er lässt sich auch per Tastatur auslösen. Ein unsichtbarer AppKit-Anker positioniert das native Menü am Button. **Andere App …** öffnet einen nativen NSOpenPanel für App-Bundles. Abbrechen erzeugt keine Arbeitskopie und verändert das Projekt nicht.

Nach der Wahl schließt die App laufende Text-/Stilbearbeitung ab und erzeugt denselben flachen PNG-Bildstand wie beim Teilen. Rendern und atomares Schreiben laufen außerhalb des MainActor. Jede Übergabe erhält einen eigenen UUID-Unterordner unter `temporaryDirectory/Snaprivo-OpenWith`. `NSWorkspace.open(_:withApplicationAt:configuration:)` übergibt nur diese PNG-Kopie an die gewählte App. Kein eigenes Apple-Event und keine neue Berechtigung werden verwendet; die Sandbox bleibt aktiv.

Erfolgreiche Arbeitskopien werden während späterer Exporte und beim App-Beenden nicht entfernt, damit Vorschau und andere Apps ihre Quelldatei weiter lesen oder speichern können. Sie bleiben temporäre Dateien und unterliegen der macOS-Bereinigung. Änderungen in anderen Apps werden nicht automatisch in das bearbeitbare Projekt zurückübernommen. Bei fehlgeschlagener Übergabe wird nur deren ungenutzter UUID-Ordner entfernt und ein Fehler angezeigt. Beenden/Projektwechsel warten auf eine gestartete Übergabe; ein noch nicht bestätigter App-Dialog wird abgebrochen. Ein unbestätigter Ausgabefehler verhindert versehentliches Beenden wie beim PNG-Speichern.

## Prüfung

- `./scripts/build.sh`: signierter macOS-Build erfolgreich.
- `./scripts/test.sh`: 82 Domain-Tests erfolgreich.
- `./scripts/test-transfer-privacy.sh`: Die tatsächliche Transferable-Darstellung, NSItemProvider und CoreTransferable-Dateiausgabe liefern bytegleich dasselbe PNG wie die Zwischenablage. Synthetischer Zuschnitt und Resize auf 41 × 29 Pixel stimmen. Unterschiedliche verdeckte Originalpixel/Texte bleiben vollständig abgedeckt. Ein bestehender Share-Snapshot bleibt nach weiteren Änderungen stabil. Live-Vorschau, Zeichen- und Größen-/Crop-Entwürfe sowie laufender PNG-Export sperren Teilen. Dateityp und Dateinamenbegrenzung sind geprüft.
- Die tatsächlichen Eigenschaften-/Toolbar-Komponenten wurden isoliert mit NSHostingView gerendert. Der Eigenschaftenbereich ist 260 statt 224 pt breit; PNG, Teilen und Öffnen mit zeigen dieselbe vertikale Ausrichtung und den neuen Gruppentrenner. Kein Dienst und kein Empfänger wird im Test aufgerufen.
- `./scripts/test-transfer-privacy.sh` prüft zusätzlich Öffnen mit einem injizierten App-Aufruf: ausgewählte App-URL, bytegleiches PNG samt Zuschnitt/Resize auf 50 × 30 Pixel, deckende Abdeckung, getrennte unveränderte Arbeitskopien, Warten auf laufende Übergabe, späteres Sichern des Projekts, Fehlerbereinigung/-bestätigung und installierte PNG-App-Liste. Es wird keine andere App gestartet.

## Noch manuell

Systemmenüs per Maus und Tastatur öffnen/abbrechen; AirDrop zu einem zweiten Gerät, Mail-Anhang und tatsächlich installierte Erweiterungen prüfen. Öffnen in Vorschau, einer weiteren PNG-App und über Andere App prüfen; den App-Dialog abbrechen. Dateiname, PNG-Pixelmaße, Inhalt und externes Speichern in der jeweiligen Ziel-App bestätigen. Diese System-/Ziel-App-Abnahme ist Teil von Q01; automatisierte Transferprüfungen ersetzen sie nicht.

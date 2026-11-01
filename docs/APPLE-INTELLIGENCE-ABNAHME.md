# Apple Intelligence für Anleitungstexte

Stand: 1. November 2026. Nutzerauftrag: die zuvor vorgeschlagene lokale KI-Unterstützung einbauen. Keine neue externe Abhängigkeit oder Berechtigung; Deployment Target bleibt macOS 26.0. Zum Bauen wird das macOS-27-SDK benötigt.

## Bedienung

1. Eine Anleitung öffnen und **Apple Intelligence …** im Editor wählen. Das Schrittmenü bietet **Text mit Apple Intelligence …** für einen einzelnen Schritt.
2. **Texte vorschlagen**, **Texte überarbeiten** oder **Texte kürzen** sowie Deutsch/Englisch wählen. Optional Ziel und zusätzliche Hinweise eingeben. Eine noch leere Anleitung benötigt ein Ziel und erzeugt ausschließlich Titel/Einleitung. Auch ein gerade geleertes Titelfeld kann so neu ausgefüllt werden.
3. **Vorschläge erstellen** startet die lokale Verarbeitung. Die Anzeige zählt die fertigen Texte; ganze Anleitungen werden schrittweise bearbeitet, danach entstehen Titel und Einleitung. Kein gemeinsamer unbeschränkt wachsender Modellverlauf.
4. Vorschläge mit den zugehörigen Screenshots prüfen und bei Bedarf direkt bearbeiten. Bisherige Schrittbeschreibungen lassen sich aufklappen. Hinweise auf mögliche Modellfehler stehen vor der Vorschau.
5. **Übernehmen** ändert die vorgesehenen Texte als einen gemeinsamen Undo-Schritt. Normales Autosave, Wiederöffnen und Redo bleiben erhalten. **Abbrechen**, Schließen und **Generierung stoppen** übernehmen nichts; verspätete Antworten geschlossener oder geänderter Anfragen werden verworfen.

Die Aktion bearbeitet nur die geöffnete Anleitung beziehungsweise den gewählten Schritt. Sie erzeugt keine Screenshots, Bildschritte oder neuen Klickfolgen. Anleitungsbearbeitung einschließlich KI-Texten bleibt Pro. Datenzugriff und bestehende Export-/Sicherungswege bleiben unverändert.

## Verarbeitung und Grenzen

- Ausschließlich `SystemLanguageModel`, keine Private-Cloud-Compute- oder Drittanbieter-Modelle, API-Schlüssel oder Netzwerk-Endpunkte. Verfügbarkeit und gewünschte Sprache werden vor Generierung geprüft. Nicht unterstützte Geräte, deaktiviertes Apple Intelligence, nicht bereite Modelle und nicht unterstützte Sprachen erhalten verständliche Zustände mit erneuter Prüfung.
- Ab macOS 27 wird zusätzlich die tatsächliche `.vision`-Fähigkeit des Modells geprüft. Dann erhält es ein auf höchstens 512 Pixel begrenztes Schrittbild plus lokalen OCR-Text. Ohne Bildfähigkeit dient Vision-OCR mit Ziel/Hinweisen als Grundlage. Für Bilder ohne lesbaren Text sind dabei ergänzende Hinweise nötig.
- Eingaben verwenden ausschließlich die bereits flachen Anleitungssnapshots. Unveränderte Originale, Editorobjekte, lokale Quellpfade oder Projektverweise gelangen nicht ins Modell. OCR-Text und Hinweise werden weder protokolliert noch als zusätzlicher Index gespeichert. Nur ausdrücklich übernommene Texte werden Teil der Anleitung.
- `@Generable` liefert getrennte Titel-/Beschreibungsfelder. IDs und Zuordnung stammen aus dem Programm, nicht aus der Modellausgabe. Die Referenzdaten werden als JSON getrennt von der Schreibaufgabe übergeben; keine Tools oder ausführbaren Modellaktionen.
- Pro Schritt eine frische Sitzung mit begrenzter Ausgabe. Text-/Schema-Token werden ab macOS 26.4 gegen die tatsächliche Kontextgröße geprüft; ältere Systeme erhalten ein konservatives UTF-8-Limit. Erkennungstext und globale Schrittübersichten sind als Ausschnitte begrenzt. Zu lange Ausgangstexte müssen gekürzt werden; die Anleitung selbst behält ihre bestehenden Textgrenzen.
- Auf dem geprüften macOS 27 meldet das Modell Bildfähigkeit, aber `tokenCount` mit einem Bildanhang schlägt unabhängig von erfolgreicher Bildgenerierung fehl. Daher zählen wir Text/Schema separat, reservieren Platz für das begrenzte Bild und behandeln verbleibende Kontextfehler ohne Datenübernahme. Dies umgeht keine Berechtigung und benutzt ausschließlich öffentliche APIs.
- Verweigerungen, Kontextüberschreitungen und Frameworkfehler werden kontrolliert angezeigt. Rohfehler können Eingabekontext enthalten und werden nicht angezeigt oder geloggt. Die normale manuelle Bearbeitung bleibt unabhängig davon verfügbar.
- Modellantworten sind nicht deterministisch und können falsche Begriffe oder Handlungen enthalten. Vorschau und bewusstes Übernehmen sind daher Teil des Ablaufs. Die KI rekonstruiert keine zuverlässig beobachtete Klickhistorie.

## Sichere Übernahme

Das Domain-Paket kennt weiterhin keine UI-, Vision- oder Foundation-Models-Frameworks. `GuideTextDraft` prüft bei Annahme Dokumentidentität, vorgesehenen Umfang, vorhandene Schritt-IDs und unveränderte Ausgangstexte/-pixel. Ganze Entwürfe erfordern dieselbe Schrittfolge; Einzel-Schritt-Entwürfe erhalten andere gleichzeitige Änderungen. Autosave-Revisionsänderungen allein machen einen Vorschlag nicht ungültig. Eine inzwischen geänderte Quelle wird nicht überschrieben.

Die Übernahme erhält aktuelle Revision, PDF-Stil, Titelseite, Bilder, IDs und Quellverknüpfungen. Es gibt keinen neuen Dateiformatstand. Die normale History-/Autosave-Logik nimmt den validierten Entwurf als einen Bearbeitungsschritt auf. Ein fehlgeschlagener oder abgebrochener Modellaufruf verändert die Anleitung nicht.

## Prüfungen

- `./scripts/test.sh`: 183 Domain-Tests bestanden. Neue Fälle: Erhalt von Bildern/Quellverweisen und letzter Revision, Einzel-Schritt-Umfang, unverwandte Änderungen, veraltete/ersetzte Quellen, fehlende/doppelte/unbekannte IDs, Textgrenzen und leere Anleitung.
- `./scripts/test-guide-assistant.sh --sandbox --live`: deterministische Modellprüfungen für Vorschau vor Annahme, bearbeitete Vorschläge, einen Undo-/Redo-Schritt, Speicherung/Wiederöffnen, Konflikte, Pro-Sperre, alle Nichtverfügbarkeitszustände, Abbruch/Lebensdauer/späte Ergebnisse, Retry und Konfigurationswechsel. Leere Anleitungen benötigen ein Ziel und erhalten keine Bildschritte.
- Derselbe Sandbox-Lauf verwendet zusätzlich synthetische beschriftete Bilder und das echte lokale Apple-Modell: Vision liest die sichtbare Toneinstellung; deutsche strukturierte Titel/Schritttexte funktionieren mit Bildanhang und erzwungenem OCR-Fallback. Englisches Überarbeiten und Kürzen sind geprüft; Kürzen reduziert einen absichtlich wiederholenden Ausgangstext. Bilder bleiben bytegleich. Ein zusätzlicher echter Modellaufruf füllt den leeren Titel einer Anleitung ohne Bildschritte. Keine Nutzerbibliothek oder echten Screenshots.
- `./scripts/test-guides.sh --sandbox`: bestehende Bild-/Export-/PDF-/Markdown-, Undo-, Autosave-/Neustart-, Papierkorb- und große Asset-Regressionsfälle bestanden.
- `./scripts/test-guide-navigation.sh`: den echten Assistenten über seine native Aktion öffnen, sichtbares Hinweise-Feld und deaktiviertes Übernehmen vor einer Generierung prüfen, über Schließen beenden und unveränderte Anleitung bestätigen. Zusätzlich langsame und wiederholte native Anleitungswechsel ohne leere Bildframes, stabile Import-/Papierkorbflächen, Mehrfachauswahl, beide Löschtasten, Isolation von Textfeldern, Wiederherstellung und Fehlerfälle bestanden. Die Dialogelemente behalten eigene Accessibility-Identifier; eine gemeinsame Kennung auf dem gesamten SwiftUI-Container würde sie überschreiben.
- `./scripts/build.sh -derivedDataPath "$PWD/build/LocalizationBuild"`: regulärer App-Build einschließlich Typprüfung bestanden. `python3 scripts/check-localization.py`: 1.335 App-, sieben InfoPlist- und 19 Domain-Texte Deutsch/Englisch mit vollständiger Compilerabdeckung bestanden. `git diff --check` ohne Befund.

Prüfhost: Entwicklungs-Mac mit macOS 27 und Xcode 27. Der OCR-Fallback wurde dort erzwungen getestet. Ein echter Mac mit macOS 26, weitere Geräte-/Regions-/Downloadzustände und vollständiges VoiceOver bleiben reale Abnahmen. Lokale Modelltests beweisen keine allgemeine inhaltliche Fehlerfreiheit. Es wurde nichts veröffentlicht.

## Apple-Referenzen

- [Foundation Models – lokales Systemmodell und Überblick](https://developer.apple.com/foundation-models-framework/)
- [Strukturierte Swift-Ausgabe](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Bildunterstützung und Vision](https://developer.apple.com/videos/play/wwdc2026/237/)
- [SystemLanguageModel und Verfügbarkeitsprüfung](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

# Apple Intelligence für Anleitungstexte

Stand: 1. November 2026. Nutzerauftrag: die zuvor vorgeschlagene lokale KI-Unterstützung einbauen. Keine neue externe Abhängigkeit oder Berechtigung; Deployment Target bleibt macOS 26.0. Zum Bauen wird das macOS-27-SDK benötigt.

## Bedienung

1. Eine Anleitung öffnen und **Apple Intelligence** in der Fensterleiste, **Mit Apple Intelligence schreiben** im Editor oder **Texte erstellen** auf der Hinweiskarte wählen. Für einen einzelnen Schritt stehen **Text vorschlagen** (ohne Beschreibung) beziehungsweise **Text überarbeiten** direkt im Schrittkopf sowie **Text mit Apple Intelligence …** im Schrittmenü bereit. Die Einstiege mit einem Klick starten die Erstellung sofort (siehe „Überarbeitung“ unten).
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

## Überarbeitung: schneller und sichtbarer – 1. November 2026

Nutzerbefund: zu langsam, Einstieg zu versteckt. Messung auf dem Prüf-Mac (macOS 27, echtes lokales Modell, vier synthetische Schritte 2560 × 1600 plus Titel/Einleitung, Messprogramm außerhalb des Repositorys):

| | Vorher | Nachher |
|---|---|---|
| Erster Lauf nach längerer Pause | erster Schritt nach 64 s, gesamt 72,7 s | Modell wird vor dem Klick vorgeladen (Wirkung bei kaltem System nicht gezielt reproduzierbar, daher nicht gemessen) |
| Warmes Modell, nur Text | erster Text erst mit fertigem Schritt nach 3,7 s; gesamt 11,8 s | erster Text nach 3,1 s, nach Vorladen 1,9–2,8 s; jeder Schritt erscheint live; gesamt 11,7 s |
| Warmes Modell, mit Bild | gesamt 17,4 s | erster Text nach 3,8 s; gesamt 16,5 s |

Die Erkennung (OCR) braucht für vier Bilder zusammen nur 0,8 s; die Gesamtdauer begrenzt die Textgenerierung selbst (rund 2 s pro Schritt, mit Bild rund 3,5 s). Vier gleichzeitige Anfragen waren nur etwa 13 % schneller als nacheinander und werden deshalb nicht verwendet.

- **Vorladen:** `LanguageModelSession.prewarm()` beim Öffnen einer Anleitung mit Schritten ohne Beschreibung, beim Darüberfahren über die Apple-Intelligence-Buttons und beim Öffnen des Dialogs ohne Sofortstart. Höchstens einmal pro Minute; nur bei verfügbarem Modell und Pro.
- **Streaming:** `streamResponse` liefert Titel und Beschreibung während des Schreibens. Die Vorschau zeigt sie schreibgeschützt in denselben Feldern (rund zehn Aktualisierungen pro Sekunde). Übernehmen bleibt bis zum vollständigen, validierten Entwurf deaktiviert; Abbrechen verwirft auch die Teilvorschau.
- **Überlappung:** Bild dekodieren und OCR des nächsten Schritts laufen parallel zur Generierung des aktuellen. Token-Zählungen für Anweisungen und Schema werden je Sprache, Aufgabe und Ausgabetyp im Speicher zwischengespeichert. Kein OCR-Text wird gespeichert.
- **Sichtbarkeit:** Button **Apple Intelligence** in der Fensterleiste, Glass-Button **Mit Apple Intelligence schreiben** im Editorkopf, Hinweiskarte **Anleitung mit Apple Intelligence schreiben** über den Schritten, solange mindestens ein Schritt keine Beschreibung hat (pro Anleitung mit **Nicht jetzt** ausblendbar), und **Text vorschlagen**/**Text überarbeiten** im Kopf jedes Schritts. Karte und Schrittbuttons erscheinen nur bei verfügbarem Apple Intelligence; Fensterleiste und Editorkopf erklären im Dialog auch Nichtverfügbarkeit.
- **Sofortstart:** Alle diese Einstiege starten mit „Texte vorschlagen“ (bei vorhandener Schrittbeschreibung „Texte überarbeiten“) in der Systemsprache. Aufgabe, Sprache und Hinweise bleiben im Dialog änderbar; jede Änderung verwirft den laufenden Vorschlag wie bisher.

## Markierungen, Vorschlag im Schritt und Mitschreiben beim Aufnehmen – 1. November 2026

**Markierungen auswerten.** Für Schritte, deren Bildprojekt seit der Übernahme unverändert ist (gleiche Revision), zeichnet `GuideStepMarkup` jede Markierung einzeln als Probe auf eine leere Fläche der Originalgröße und rendert sie mit denselben Parametern wie das Anleitungsbild (Zuschnitt, Größe, Zeichenfläche, Drehung, Präsentation, verkleinert auf 640 px). Der Vergleich mit der leeren Fläche liefert die genaue Lage im Anleitungsbild, ohne die Render-Geometrie nachzubauen; rund 35–55 ms pro Schritt. Ausgewertet werden Pfeilspitzen, Rahmen/Formen/Freihand, Markierungen, Spotlight, Lupenquellen, nummerierte Marken (nach ihrer Nummer sortiert) sowie Text- und Callout-Notizen (Callouts zusätzlich ihre Spitze). Unschärfe, Abdecken und eingefügte Bilder nicht. Zugeordnet wird OCR-Text des flachen Anleitungsbilds: im Rahmen, nächstgelegen zu Spitze oder Marke, Notiztext getrennt. Leere Rahmen werden einmal gezielt erneut gelesen, weil Vision eng umrahmten Text im Gesamtbild gelegentlich auslässt. Dem Modell werden nur diese Texte und ihre Reihenfolge übergeben; Objekte, Notizinhalte aus dem Projekt oder Originalpixel nicht.

Messung mit dem echten lokalen Modell (Bild mit zwei Nummern, Rahmen, Pfeil und Notiz „Hier klicken“, Zuschnitt und Präsentationshintergrund, je vier Läufe):

- Als englische Beschreibungssätze im JSON übergeben, lief das Modell in zwei von zwei Läufen in Endloswiederholungen. Als Feld im JSON folgte es der Reihenfolge nicht zuverlässig und hielt die Notiz für ein Bedienelement.
- Jetzt stehen die markierten Elemente in der Aufgabe selbst, der OCR-Ausschnitt ist dann auf 400 Zeichen gekürzt: vier von vier Läufen ergeben „„Safari“ auswählen, „Mitteilungen erlauben“ aktivieren, „Stil: Banner“ setzen, „Ton abspielen“ aktivieren.“
- Das Modell schrieb danach gelegentlich über das Feld hinaus (`} ```json …`) bis zur Tokengrenze. Solche Ausläufe werden beim Streamen erkannt und beendet, der Text davor bleibt; die Ausgabegrenze für Vorschläge liegt bei 320 Token. Laufzeit des Messprogramms dadurch 12,4–13,4 s → 5,6–7,7 s.
- Auch ohne Markierungen formuliert das Modell durch die neue Anweisung („kurze, natürliche Sätze, keine Label-Listen“) häufiger Handlungen, etwa „Du kannst auf „Mitteilungen erlauben“ klicken.“ statt „Einstellungen: Stil: Banner, Ton abspielen …“.

**Vorschlag direkt im Schritt.** **Text vorschlagen**/**Text überarbeiten** im Schrittkopf öffnet keinen Dialog mehr, sondern schreibt unter der Beschreibung live in eine Glass-Karte. **Übernehmen** nutzt dieselbe geprüfte Übernahme wie der Dialog (ein Undo-Schritt, Schutz vor zwischenzeitlich geänderten Schritttexten, andere Schritte bleiben erhalten), daneben **Neu erstellen** und **Verwerfen**. Vorschläge bleiben beim Wechsel zwischen Bibliothek, Editor und Anleitungen erhalten und werden beim Wechsel zu einer anderen Anleitung verworfen. Der Dialog mit Ziel, Aufgabe und Sprache bleibt über Fensterleiste, Editorkopf, Hinweiskarte und das Schrittmenü erreichbar.

**Mitschreiben beim Aufnehmen.** Ein mit **Schritt aufnehmen** angehängter Schritt erhält sofort einen Vorschlag im Schritt, sobald die Anleitung gesichert ist. Abschaltbar mit **Beim Aufnehmen Text vorschlagen** unter den Aufnahme-Buttons; die Einstellung ist standardmäßig an und wird gespeichert. Schritte aus der Bibliothek erhalten keinen automatischen Vorschlag.

**Warteschlange.** Der Dienst bearbeitet Anfragen nacheinander und lässt weitere warten, statt sie mit „Ein anderer Textauftrag läuft noch“ abzulehnen. Abbrechen entfernt auch wartende Anfragen.

## Aktivitätsanzeige und Hintergrund – 1. November 2026

Nutzerbefund: Während des Wartens zeigte der Dialog nur „0 von 4 Textvorschlägen erstellt“ mit leerem Balken; unklar, was passiert. Der Dienst meldet jetzt seine Phase (`GuideAssistantProgress.Activity`): wartet auf andere Vorschläge, Bild von Schritt n wird gelesen, Schritt n wird geschrieben, Titel und Einleitung werden geschrieben. Dialog, Vorschlagskarte im Schritt und Statusanzeige zeigen Drehsymbol, Phase und ab drei Sekunden die laufende Zeit; solange noch kein Text da ist, erklärt der Dialog nach acht Sekunden das mögliche Laden des Modells. Der Fortschrittsbalken erscheint erst nach dem ersten fertigen Text.

**Im Hintergrund weiter** (sichtbar während der Erstellung) schließt den Dialog, ohne abzubrechen. Die Anfrage gehört dann zur Anleitung, nicht zum Dialog. Im Editorkopf steht eine Glass-Statusanzeige mit Phase und **Anzeigen**; nach Abschluss **Vorschläge bereit · Prüfen**, bei einem Fehler **Keine Vorschläge erstellt · Anzeigen**. Alle Apple-Intelligence-Einstiege öffnen eine laufende oder fertige Anfrage wieder, statt eine neue zu starten. Übernommen wird weiterhin erst nach Prüfung im Dialog. Abbrechen, Schließen und der Wechsel zu einer anderen Anleitung beenden die Anfrage.

Prüfung: `./scripts/test-guide-assistant.sh --sandbox --live` prüft die Phasen (Start, Warteschlange ohne Überschreiben des Fortschritts, Schreiben, Abschluss) und dass eine Hintergrundanfrage nur beim Wechsel der Anleitung verworfen wird. `./scripts/test-guide-navigation.sh` öffnet und schließt den Dialog nativ. Das Zurückkehren aus dem Hintergrund und die Statusanzeige wurden nicht in der laufenden App geprüft.

## Sichere Übernahme

Das Domain-Paket kennt weiterhin keine UI-, Vision- oder Foundation-Models-Frameworks. `GuideTextDraft` prüft bei Annahme Dokumentidentität, vorgesehenen Umfang, vorhandene Schritt-IDs und unveränderte Ausgangstexte/-pixel. Ganze Entwürfe erfordern dieselbe Schrittfolge; Einzel-Schritt-Entwürfe erhalten andere gleichzeitige Änderungen. Autosave-Revisionsänderungen allein machen einen Vorschlag nicht ungültig. Eine inzwischen geänderte Quelle wird nicht überschrieben.

Die Übernahme erhält aktuelle Revision, PDF-Stil, Titelseite, Bilder, IDs und Quellverknüpfungen. Es gibt keinen neuen Dateiformatstand. Die normale History-/Autosave-Logik nimmt den validierten Entwurf als einen Bearbeitungsschritt auf. Ein fehlgeschlagener oder abgebrochener Modellaufruf verändert die Anleitung nicht.

## Prüfungen

Ergänzung vom 1. November 2026 (Markierungen und Vorschläge im Schritt): `./scripts/test-guide-assistant.sh --sandbox --live` prüft zusätzlich die Lage von Markierungen bei Zuschnitt und Präsentationshintergrund, das Auslassen von Unschärfe und nicht mehr passender Geometrie, die geordnete Zuordnung von Rahmen-, Pfeil- und Markentext, getrennte Notizen, das erneute Lesen leerer Rahmen, das Abschneiden von Ausläufen, Vorschläge in zwei Schritten mit je eigenem Undo-Schritt, Verwerfen und Anleitungswechsel sowie zwei gleichzeitige echte Anfragen. `./scripts/test-guides.sh --sandbox` prüft, dass nur aufgenommene Schritte für einen Vorschlag markiert werden. `./scripts/test-guide-navigation.sh`, `./scripts/test-settings.sh`, `./scripts/test-quick-capture-integration.sh`, `./scripts/test.sh` (183 Tests), App-Build und Lokalisierungsprüfung bestanden. Nicht geprüft: echte Aufnahme mit Bildschirmfreigabe und sichtbarer Vorschlag in der laufenden App, VoiceOver.

Überarbeitung vom 1. November 2026: `./scripts/test-guide-assistant.sh --sandbox --live` prüft zusätzlich die schreibgeschützte Live-Vorschau (sichtbar, nicht übernehmbar, durch den vollständigen Entwurf ersetzt), den einmaligen Sofortstart mit übergebener Aufgabe und das Vorladen beim Öffnen ohne Sofortstart; die echten Modellprüfungen laufen jetzt über Streaming. `./scripts/test-guide-navigation.sh` öffnet den Dialog über den neuen Button mit Sofortstart und schließt ihn ohne Änderung. `./scripts/test-guides.sh --sandbox`, `./scripts/test.sh` (183 Tests), App-Build und `python3 scripts/check-localization.py build/QuickWinsBuild` bestanden.

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

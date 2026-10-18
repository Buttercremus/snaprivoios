# Release-Workflows – Umsetzung und Abnahme

Stand: 18. Oktober 2026. Autorisiert sind gemeinsame Sicherung/Speicherverwaltung, Video-Papierkorb, Finder-Öffnen, direkte Anleitungserstellung, optionale Schnellvorschau, Objektliste und der StoreKit-Unterbau für einen Einmalkauf. Keine Veröffentlichung oder echte Kaufaktivierung durch diesen Auftrag.

## Bedienung

- **Ablage → Alles sichern … / Alles wiederherstellen …** ist der gemeinsame Weg. Er steht auch im Dateienmenü der Bild-/Videobibliothek und unter Einstellungen → Speicherorte. Die bisherigen einzelnen Sicherungsformate bleiben lesbar und ihre gezielten Aktionen verfügbar.
- **Einstellungen → Speicherorte** zeigt die logischen Dateigrößen von Bildern, Videos und Anleitungen einschließlich Papierkörben sowie verfügbaren Platz am Bildspeicherort. „Speicherbelegung aktualisieren“ liest erneut. Keine automatische Löschung.
- **Bibliothek → Videos → Papierkorb:** entfernen, wiederherstellen oder nach ausdrücklicher Bestätigung endgültig löschen. Karten zeigen Dateigrößen. Auch fehlgeschlagene/unterbrochene Einträge sind entfernbar. Ein geöffnetes Video zuerst schließen. Laufende Aufnahmen werden nicht gelöscht.
- **Finder-Doppelklick:** `.snaprivo`, `.snaprivoguide`, `.snaprivobackup` und `.snaprivoall` sind registriert. Dateieingänge werden auch vor dem ersten Workspace-Fenster vorgemerkt und nacheinander verarbeitet. Die vorhandenen Import-/Validierungspfade erstellen eigene Kopien; externe Projektdateien werden nicht überschrieben. Die Dateiöffnung unterdrückt das Erststart-Onboarding.
- **Bibliothek → Bilder auswählen → Anleitung erstellen:** mehrere Bilder markieren, einmal erstellen. Reihenfolge entspricht der aktuell sichtbaren Bibliothekssortierung. Sichtbare, bearbeitete Bildstände werden übernommen; der Stil der aktuell geöffneten Anleitung wird wiederverwendet, andernfalls Standard. Offene Änderungen werden vorher gesichert. Höchstens 100 Schritte.
- **Einstellungen → Aufnahme → Schnellvorschau nach der Aufnahme:** zunächst aus. Aktiviert erscheint eine Vorschau mit Kopieren, Markieren, Anheften und Verwerfen. Schließen bewahrt die bereits gespeicherte Aufnahme; Verwerfen verschiebt sie in den Bildpapierkorb. Erst „Markieren“ ersetzt den bisherigen Editor. Bildimporte und Videos lösen diese Vorschau nicht aus.
- **Editor → Objekte:** native Liste in Malreihenfolge, vorn oben; native Mehrfachauswahl, Alle auswählen, Umbenennen, Ebenenaktionen und Löschen. Die einfachere bisherige Checkboxliste wurde ersetzt. Benennung und Anordnung sind rückgängig machbar und werden gespeichert. Abdeckungen bleiben immer über anderen Objekten. Eine Listenzeile kann auch ein einzelnes Gruppenmitglied ansprechen.

## Gesamtsicherung und Wiederherstellung

`.snaprivoall` ist ein als Finder-Paket registrierter Ordner. Format 1 enthält `complete.json` mit Dateinamen, Größen und SHA-256, die bestehende Bildsicherung in `images/`, Videoformat 2 in `videos/` und vollständige aktuelle Anleitungsdokumente in `guides/`.

Enthalten sind aktive und entfernte Bildprojekte, Originalbilder/Bildassets, Bearbeitungen, Tags/Sammlungen, fertige und entfernte Videos mit Schnittdaten sowie Anleitungen mit Bildern/Texten/Stil. Vorhandene unterbrochene Videodaten werden als undurchsichtige Arbeitsdaten erhalten und niemals allein wegen eines Restore als abspielbar deklariert. Ein unterbrochener Eintrag ohne Medien bleibt als solcher erhalten. Es wird keine laufende Aufnahme gesichert. Wiederaufbaubarer OCR-Cache, App-Einstellungen, Ordnerfreigaben, Kaufbelege, Sitzungs-Undo und historische Dokumentrevisionen sind kein Bestandteil dieser Inhaltssicherung.

Erstellen erfolgt unter neuem Namen in einem benachbarten Arbeitsordner und wird erst nach Abschluss veröffentlicht. Vorhandene Sicherungen werden nicht ersetzt. Vorher werden die eigenen offenen Bild-, Video- und Anleitungsänderungen abgeschlossen. Die einzelnen Stores liefern jeweils konsistente Stände; die Sicherung ist keine Transaktion über gleichzeitig bearbeitende weitere App-Prozesse.

Restore liest einen begrenzten Index, lehnt unsichere Namen, symbolische Links, unerwartete Pfadtiefen und Prüfsummenabweichungen ab und kopiert die Quellen in einen privaten temporären Bereich. Bilddekodierung, Dokumentformate, Anleitungsbilder und Fakten fertiger MP4s werden dort vollständig geprüft, bevor Nutzerbibliotheken verändert werden. Alle importierten Inhalte erhalten neue Identitäten. Verknüpfungen zu mitgesicherten Bildprojekten werden auf die neuen IDs und den Zielbibliotheksschlüssel abgebildet. Fremde/nicht mitgesicherte Bildbezüge werden gelöst; die flachen Anleitungsbilder bleiben erhalten.

Bei normalen Schreibfehlern werden die in diesem Auftrag angelegten Inhalte aus allen drei Stores zurückgenommen. Jeder Rücknahmepfad wird auch bei Fehlern eines anderen Stores versucht. Ein Fehler bei der Rücknahme wird ausdrücklich als mögliche Teilübernahme gemeldet. Ein harter Prozess-/Stromabbruch während der letzten Veröffentlichung kann vollständige Teilmengen hinterlassen; vorhandene Arbeit wird nicht überschrieben. Erneutes Restore ergänzt weitere Kopien. Diese Stromausfall-/Lastabnahme bleibt Q02.

Video-Papierkorb verwendet ein dauerhaftes `trashedAt` im Metadatenformat 3; Originale bleiben am bisherigen Ort, damit kein großer Film für eine Papierkorbaktion kopiert werden muss. Öffnen/Exportieren aus dem Papierkorb sind gesperrt. Endgültiges Löschen entfernt Medien und Thumbnail vor der Metadatei. Bei Unterbrechung bleibt damit ein erneut löschbarer Papierkorbeintrag. Formate 1–2 werden gelesen. Projektformat 10 ergänzt optionale Objektnamen; Gruppen/Bildassets aus Format 9 bleiben bei Migration erhalten.

## Identität und bisherige Daten

Aktuelle Build-ID: **`com.snaprivo.app`**, Team **`24C8L59PV7`**. Die App-ID wurde in diesem Auftrag nicht erneut geändert. Historische Aussagen über eine unveränderte `com.snagforge.app` waren im aktuellen README nicht mehr zutreffend.

Auf diesem Mac sind sowohl alte als auch neue Container vorhanden. Geprüft wurden nur Existenz und Struktur, keine persönlichen Bild-/Videoinhalte. Ein anderer Bundle-Identifier bedeutet einen anderen Sandbox-Container; identische relative Unterordner führen nicht zu einer automatischen Datenübernahme. TCC-Freigaben der alten Identität sind kein Nachweis für die aktuelle signierte App.

**Übernahme:** alte App beenden, Einstellungen → Speicherorte → Bisherige Snaprivo-Daten übernehmen … wählen. Den alten Container `~/Library/Containers/com.snagforge.app` oder dessen `Data/Library/Application Support` ausdrücklich freigeben. Erkannt werden die bekannten Unterordner `SnagForge/Projects`, `SnagForge/Guides` und `Snaprivo/VideoRecordings`. Der gemeinsame Sicherungs-/Validierungspfad importiert neue Kopien. Bestehende Zielprojekte und alte Originale bleiben erhalten. Eine eigene externe Bildbibliothek kann weiterhin über die bestehenden Sicherungs- und Speicherortwege übernommen werden.

Die App liest keinen fremden Container automatisch und setzt keine Systemberechtigungen zurück. Ein echter Rechte-/Update-Test mit der alten und neuen signierten App bleibt Q01/R03. Die lokale Ordnerübernahme ist mit einem synthetischen alten Container auch im Sandbox-Testhost geprüft.

## Einmaliger Pro-Kauf

Produktvorschlag: nicht verbrauchbar, ID `com.snaprivo.pro.lifetime`. `StoreKitProClient` lädt lokalisierte Produktpreise und prüft ausschließlich verifizierte, passende Apple-Transaktionen. `currentEntitlements` dient für Neustart/Offline-Belege; `Transaction.updates` berücksichtigt spätere Freigabe und Widerruf. Erfolg wird nach Verifikation bestätigt und die Transaktion abgeschlossen. `AppStore.sync()` wird nur durch „Käufe wiederherstellen“ ausgelöst. Abbruch, ausstehende Freigabe, Fehler und ungültige Belege sind eigene Zustände. Keine lokale Kaufbehauptung in UserDefaults und kein Lizenzserver.

**Kommerzieller Schalter bleibt aus.** Die Paywall ist über Snaprivo Pro erreichbar und erklärt den Entwicklungsstand. Alle vorhandenen Funktionen bleiben zugänglich. Vor Aktivierung sind genaue Free-/Pro-Liste, Preis, Kaufversprechen und das Produkt in App Store Connect zu bestätigen; anschließend Sandbox/TestFlight mit dem tatsächlichen Produkt. Es gibt keine vorläufigen Funktionsschranken oder öffentliche Preiszusage. Der Betrag 1,23 im lokalen `.storekit` ist ausschließlich eine synthetische Testkonfiguration.

Das getrennte Xcode-Scheme **SnaprivoStoreTests** verwendet einen eigenen minimalen Host mit eigener Bundle-ID und ohne Zugriff auf die Nutzerbibliothek. Native Tests prüfen Produktladen, verifizierten Kauf, Neustart, explizites Wiederherstellen und Erstattung. Der öffentliche StoreKit-Testprozess benötigt ein gültiges Präsentationsfenster; der Host stellt dieses bereit. Die Tests lösen keine echten Käufe aus.

## Reale Scroll-Beispiele

Browser-Viewport-Aufnahmen öffentlicher Seiten wurden lokal durch den produktiven `ScrollStitcher` ausgewertet. Nachgewiesen sind der pixelbasierte Abgleich und konservative Ablehnungen; diese Browser-Aufnahmen ersetzen keine ScreenCaptureKit-/TCC-Abnahme der ganzen App.

Der Abgleich berücksichtigt jetzt Bruchteile von Pixeln beim Scrollen: ein separater Analysepuffer mit etwa einem Pixel Glättung und Viertelpixel-Phasen reduziert Unterschiede der Textrasterung. Exportierte Aufnahme-/Bildpixel werden nicht geglättet oder interpoliert. Bewegungserkennung bleibt auf Originalpuffern. Eindeutigkeit, dichte Gegenprüfung, Mindestüberlappung und Erkennung fester Ränder bleiben erforderlich.

| Seite / Ausschnitt | Ergebnis im aufgenommenen Beispiel |
| --- | --- |
| Apple ScreenCaptureKit, Inhaltsbereich | 213 px Versatz erkannt |
| Swift Documentation, Inhaltsbereich | 214 und 213 px erkannt |
| Wikipedia „Screenshot“, Inhaltsbereich | zweimal 285 px erkannt |
| Ganze Ansichten mit fester Navigation/Seitenleisten | als fest oder unsicher abgelehnt |
| Zusätzlich beobachteter Wechsel der Viewportbreite | als Dimensionswechsel abgelehnt |

Öffentliche Seiten: [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [Swift Documentation](https://docs.swift.org/latest/documentation/), [Wikipedia Screenshot](https://en.wikipedia.org/wiki/Screenshot). Bildbelege liegen nur lokal unter `/tmp/snaprivo-real-scroll`, der Ergebnisbericht unter `/tmp/snaprivo-real-scroll-results-final.log`. Keine fremden Seitenbilder im Git-Repository. Die Aufnahmen zeigen fünf gültige Inhaltsübergänge, keine allgemeine Kompatibilitätsgarantie. Virtuelle Listen, Animationen, dynamische Inhalte, weitere Websites, mehrere Displays und der vollständige Aufnahmeablauf bleiben P01/Q01. Synthetische negative Tests prüfen weiterhin Bewegung, wiederholte Muster, Sticky Header/Footer, Überlappung und Grenzen.

## Nachweise

- `./scripts/build.sh -derivedDataPath "$PWD/build/ReleaseWorkflows"`: signierter Debug-Build und Signaturprüfung erfolgreich; App Sandbox im fertigen Bundle aktiv. Referenz: arm64, macOS 27.0, SDK 27; macOS 26 bleibt separat abzunehmen. Keine neue externe Produktabhängigkeit.
- `./scripts/test.sh`: **127 Domain-Tests** erfolgreich, einschließlich Format-9-/10-Migration, Objektnamen, Videopapierkorb und Bruchteil-Pixel-Abgleich.
- `./scripts/test-release-workflows.sh --sandbox`: gemeinsame Sicherung/Restore, wiederholte Übernahme, beschädigte Anleitung, Rücknahme nach Fehler der letzten Komponente, alte Container, Bildbezüge, kalte Finder-Warteschlange, Video-Dateigrößen/Papierkorb/Löschen, Objektnamen/Undo, direkte Anleitungen, Schnellvorschau und kontrollierte Kaufzustände erfolgreich.
- `./scripts/test-video-library.sh --sandbox`: bestehende Video-/Backupregression und echter Prozessneustart erfolgreich; Erwartung an erweiterte Sicherungen angepasst, unterbrochene Inhalte bleiben unterbrochen.
- `./scripts/test-guides.sh --sandbox`: PDF/Markdown, Datenschutz, Persistenz und echter Prozessneustart erfolgreich.
- `./scripts/test-scroll.sh`: native synthetische Aufnahme-/Vorschau-/Naht-/Undo-/Autosave-/Exportregression erfolgreich. SDK-27-Deprecationhinweise des bestehenden AVAssetReader-Pfads sind keine Laufzeitfehler; Mindestversion bleibt 26.
- `./scripts/test-storekit.sh`: natives Xcode-StoreKit-Scheme erfolgreich, einschließlich Kauf, Wiederherstellen und Erstattung.
- `python3 scripts/check-localization.py build/ReleaseWorkflows`: **894 App-Texte, 7 InfoPlist-Texte, 13 Domain-Texte**, vollständige Compiler-Abdeckung Deutsch/Englisch. Native Bundle-/Sprachprüfungen bestanden für Deutsch, Englisch und englischen Rückfall bei Französisch.
- Isolierte Produktionsoberfläche mit synthetischen Bildern bedient: Objekt auswählen/umbenennen, native Mehrfachauswahl, Einmalkauf-Paywall ohne aktiven Kauf und zwei Bilder markieren → Anleitung mit zwei Schritten erstellen. Keine persönliche Aufnahme verwendet. Visueller Beleg: `build/release-workflows-guide-ui.png`.
- Reproduzierbarer Ausgangsstand: lokaler Git-Commit `d4b5039`. Änderungen werden separat lokal gesichert; keine Veröffentlichung.

Offen bleiben umfassende VoiceOver-/Tastaturabnahme, physischer Finder-/Berechtigungs-/Upgrade-Test auf weiteren Macs, reale Datenmengen/Stromausfall, breite Scroll-/Videoabnahme sowie die kommerzielle Paket-/Store-Konfiguration. Ein erfolgreicher Build ersetzt diese Abnahmen nicht.

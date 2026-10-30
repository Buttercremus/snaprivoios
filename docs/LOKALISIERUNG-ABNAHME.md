# Deutsch und Englisch

Stand: 14. Oktober 2026. Implementiert, automatisiert und visuell auf macOS 27 mit Retina-Anzeige geprüft; macOS 26 bleibt die Mindestversion.

## Sprachwahl und Umfang

Die App liefert Deutsch (`de`) und Englisch (`en`). Unter Einstellungen → Allgemein → Sprache sind seit dem 18. Oktober 2026 Systemsprache, Deutsch und Englisch wählbar. Die Auswahl verwendet die native App-Überschreibung `AppleLanguages` im eigenen UserDefaults-Domain und gilt nach dem nächsten App-Start. Systemsprache entfernt diese Überschreibung; danach wählt macOS die am höchsten bevorzugte unterstützte Sprache. Englisch ist Entwicklungssprache und Rückfall. Die globale macOS-Sprache und regionale Formate werden nicht geändert. Bestehende native App-Überschreibungen einschließlich regionaler Kennungen werden übernommen. Ein zusätzlicher persistierter Sprachschlüssel, Bundle-Swizzling oder das Austauschen von Bundle-Klassen ist nicht erforderlich.

Übersetzt sind 518 App-Texte, zwei Dateityp-Beschreibungen und 13 Domain-Texte: App-/Menüleistenbefehle, Bibliothek/Papierkorb, Einstellungen, Aufnahme/Berechtigungsführung, Auswahl-Overlay, Scroll-/Videosteuerung, Editorwerkzeuge und Eigenschaften, Zuschnitt/Bildgröße, Export/Teilen/Öffnen mit, Bedienungshilfen, eigene Fehlermeldungen und der Support-E-Mail-Entwurf.

Benutzertexte und bereits gespeicherte Projekttitel werden nicht übersetzt. Formatversion, IDs, Werkzeug-Rohwerte, Tastenkürzel, Dateiendungen und vorhandene Bibliothekspfade bleiben gleich. Der technische Ordnername `Snaprivo-Bibliothek` bleibt auch auf Englisch bestehen; die englische Speicherortbeschreibung nennt deshalb diesen tatsächlichen Namen. Neue Titelzusätze wie „Kopie“/„Copy“ folgen der App-Sprache. Namen installierter Apps und Schriftfamilien kommen weiter vom System.

## Native Umsetzung

- `Snaprivo/Resources/Localizable.xcstrings`: stabile vorhandene Textschlüssel mit vollständigen deutschen und englischen Werten. Die Schlüssel selbst bleiben bewusst unverändert; die angezeigten Texte stammen aus der gewählten Sprache. `String(localized:)` erfasst auch String-Eigenschaften, dynamische Meldungen und AppKit-Texte, die SwiftUI nicht automatisch lokalisieren würde.
- `InfoPlist.xcstrings`: lokalisierte Beschreibungen für Projektdatei und Bibliothekssicherung. Die von Xcode zusätzlich extrahierten Produktnamen und der Copyright-Vermerk sind ausdrücklich als unveränderliche, nicht zu übersetzende Metadaten markiert.
- `SnagForgeDomain`: native `en.lproj`/`de.lproj`-Ressourcen über SwiftPM; `Bundle.module` für Fehlertexte. Das Paket kennt weiterhin keine UI- oder Capture-Frameworks. Direkt kompilierte bestehende Testprogramme lösen Ressourcen über ihr Host-Bundle auf.
- Projekt-/Markierungs-/Abschnittszähler verwenden native Pluralvarianten. Ganze Meldungen bleiben übersetzbar; dynamische Werte behalten Typ und Reihenfolge. Sprachabhängige Zahlenformatierung kommt von Foundation, z. B. `10,000 projects` und `10.000 Projekte`.
- Die Extraktion lokalisierbarer Strings durch den Swift-Compiler ist aktiviert. `scripts/check-localization.py` gleicht die extrahierten Schlüssel mit den Ressourcen ab und prüft Sprachvollständigkeit, Status und Formatargumente. Neue/umbenannte Schlüssel benötigen beide Sprachwerte.

Englische Terminologie: Capture, Library, Trash, Arrow, Callout, Highlight, Steps, Blur, Redact, Crop, Image Size, Open With. Tastatursymbole, Produktnamen und Bildformate bleiben erhalten.

## Automatisierte Nachweise

Erfolgreich:

```sh
./scripts/build.sh -derivedDataPath "$PWD/build/LocalizationBuild"
python3 scripts/check-localization.py
./scripts/test-localization.sh
./scripts/test.sh
./scripts/test-support.sh
./scripts/test-settings.sh
./scripts/test-canvas.sh
./scripts/test-transfer-privacy.sh
./scripts/test-renderer.sh
./scripts/test-resize.sh
./scripts/test-capture.sh
./scripts/test-scroll.sh
./scripts/test-video.sh
./scripts/test-autosave.sh
./scripts/test-library.sh
./scripts/test-trash.sh
./scripts/test-layers.sh
./scripts/test-typography.sh
```

Der Sprachtest verwendet ein isoliertes temporäres Host-Bundle mit den tatsächlich gebauten App-Ressourcen. Drei getrennte Prozesse starten mit englischer, deutscher und französischer Sprachpräferenz. Der letzte Prozess bestätigt den englischen Rückfall; die Sprache des Nutzers wird nicht geändert.

Geprüft sind native Sprachwahl, echte Produktionsbeschriftungen für Werkzeugleisten/Aufnahme/Fehler, Zähler 0/1/2/10.000, Singular mit unabhängigem Plural im selben Satz, dynamische Fehlermeldungen und Aufnahmeabmessungen, Videozeitformat, Support-Entwurf einschließlich Sonderzeichen, das eingebaute Domain-Ressourcenbundle und InfoPlist-Texte. Ein Projekt mit deutschen Benutzertexten bleibt beim Serialisieren/Wiederöffnen unverändert. Kein Mailclient, Browser oder Versand wird durch diese Tests gestartet.

**88 Domain-Tests und alle genannten bestehenden Regressionen bestehen.** Der signierte App-Build enthält beide Sprachen. Bestehende Warnungen im synthetischen Videotest betreffen auf macOS 27 abgekündigte AVAssetWriter-Test-APIs; der Test besteht und sie gehören nicht zur Lokalisierungsänderung.

## Englische Oberfläche: visuelle Prüfung

Die Produktionsansichten wurden in einer separaten englischen Prüf-App bedient und per Screenshot sowie Accessibility-Baum geprüft. `Tests/Fixtures/EnglishUIFixture.swift` verwendet eine eigene temporäre Bibliothek, isolierte Einstellungen, deaktivierte globale Kürzel und ausschließlich synthetische Bilder. Die Prüf-App erhält nur die englischen App-Ressourcen. Die laufende Nutzer-App und ihre Sprache, Bibliothek und Berechtigungen bleiben unverändert. Das ist eine Prüfung der echten Ansichten in einem eigenen Host, kein zusätzlicher Sandbox-/TCC-Nachweis.

Reproduzieren:

```sh
./scripts/build.sh -derivedDataPath "$PWD/build/LocalizationBuild"
./scripts/build-english-ui-fixture.sh
```

Anschließend `build/EnglishUIFixture/SnaprivoEnglishQA.app` öffnen. Im zusätzlichen Menü **UI QA** lassen sich 800 Pixel Fensterbreite, die Standardgröße sowie synthetische Auswahl-Overlays und Vorschau-Steuerfenster öffnen. Die Scroll-Vorschau nicht um echte Abschnitte ergänzen und die Videoaufnahme nicht starten; diese Schaltflächen benutzen weiterhin die Produktionsaufnahme.

| Bereich | Geprüft |
| --- | --- |
| Einstellungen | Alle sechs Bereiche, längere Erklärungen und Speicherpfade, Support-Schaltfläche, Tastenkürzel während der Eingabe |
| Bibliothek | Standard- und minimale Fensterbreite, lange Projekttitel, leere Papierkorbansicht, Filter-/Sortierbeschriftungen |
| Editor | Schmale Fensterbreite; kompakte, normale und große Werkzeugbeschriftungen; Eigenschaften für Text, Callout, Formen, Highlight, Schritte, Blur, Redact und Crop; lange Hinweise im scrollbaren Inspector |
| Dialoge | Umbenennen und Bildauflösung einschließlich ungültiger Eingaben, nativer PNG-Speicherdialog |
| Menüs | App, File, Edit, View, Capture, Help, Zoom und Open With; native englische Beschriftungen und Accessibility-Texte |
| Aufnahme | Aufnahmeoptionen; Screenshot- und Video-Bereichsauswahl vor/nach dem Aufziehen eines Rahmens; Scroll-Vorschau und Video-Steuerung vor Aufnahmestart |

Gefunden und korrigiert:

- In der schmalen Bibliothek wurden **Files**, **Trash** und **Favorites** gekürzt. Die Leiste verteilt Zähler/Status und Aktionen bei Bedarf auf mehrere Zeilen, ohne Beschriftungen zu kürzen.
- **Image Size…** und **100 %** wurden im Editor abgeschnitten. Werkzeugbeschriftungen erhalten ihre natürliche Textbreite; die Zoomgruppe wird nicht mehr zusammengedrückt.
- Große Bildaktionen ließen zu wenig Platz für ein vollständiges Werkzeug. Bei Platzmangel wechseln Werkzeuge und Bildaktionen in zwei horizontal bedienbare Zeilen.
- Englische Formulierungen für Zuschnitt, Scroll-Übergänge/Überlappung, Sortierung, Schrittnummerierung und den Bibliotheksordner wurden präzisiert. Der feste tatsächliche Ordnername steht in Anführungszeichen.

In den geprüften Ansichten wurden keine fehlenden englischen Übersetzungen gefunden. Lange **Benutzer-Projekttitel** dürfen weiterhin mit Auslassungszeichen erscheinen; der vollständige Titel bleibt für Bedienungshilfen und im Umbenennen-Dialog verfügbar. Datums- und Zahlendarstellung kann der separat eingestellten macOS-Region folgen, auch bei englischer App-Sprache.

## Verbleibende Abnahme

Offen bleiben macOS 26, VoiceOver-Aussprache, Finder-Dateityp-Anzeige nach Launch-Services-Registrierung und ein echter Sprachwechsel über Systemeinstellungen. Aufnahmestart/-stopp, Berechtigungsdialoge und seltene Fehlerzustände wurden für diese visuelle Sprachprüfung nicht durch echte Aufnahmen ausgelöst; ihre Texte sind im Ressourcen- und Laufzeittest abgedeckt. Es wurde keine Nachricht verschickt und keine Bildschirmfreigabe erteilt.

App-Store-Beschreibung, Schlüsselwörter, Werbetexte, rechtliche Texte und Store-Screenshots sind eine separate Release-Aufgabe. Es wurden keine Store-Einträge oder Webseiten veröffentlicht.

Grundlagen: [Apple String-Kataloge](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog), [native App-Sprachauswahl](https://support.apple.com/de-de/guide/mac-help/mh26684/mac), [lokalisierbare Dateityp-Beschreibungen](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html).

## P06 – 16. Oktober 2026

Anleitungsbereich, PDF-/Markdown-/Arbeitsstand-Dialoge, Speicherfehler und Konfliktkopie sind in Deutsch/Englisch übersetzt. Aktuell 668 App-Texte, vier InfoPlist-Texte (drei Dateitypbeschreibungen und Mikrofontext), 13 Domain-Texte; Compiler-Abdeckung, Singular/Plural der Schritte sowie native deutsche/englische und englische Rückfallauswahl bestanden. Die englische Anleitungsoberfläche wurde bei 800 Pixel Fensterbreite tatsächlich bedient, einschließlich PDF-Vorschau, allen Exporten, Import und sichtbarer Speicherfehler. [Nachweise](ANLEITUNG-AUSGABE-ABNAHME.md).


## I07 Bildvorschauleiste – 16. Oktober 2026

Die neue Editorleiste einschließlich Bildzahl-Pluralen, Vor-/Zurück, Tastenkürzel-Hinweisen und Accessibility ist in Deutsch/Englisch übersetzt. Aktuell 677 App-Texte, vier InfoPlist-Texte und 13 Domain-Texte; Compiler-Abdeckung und native 0/1/2/10000-Bildzahlprüfungen bestanden. Die englische Oberfläche wurde mit 14 synthetischen Bildern bei 800/1180 Pixel Fensterbreite bedient. [Nachweise](BILDVORSCHAULEISTE-ABNAHME.md).

## V03 Videovorschau und Trimmen – 16. Oktober 2026

Interne Videovorschau, Trimmgrenzen, Abspielposition-Aktionen, Arbeitsstand-/Verwerfen-/Konflikthinweise und Exportabbruch sind in Deutsch/Englisch übersetzt. Aktuell **755 App-Texte**, vier InfoPlist-Texte und 13 Domain-Texte; vollständige Compiler-Abdeckung, passende Formatargumente und native Bundle-/Sprachprüfungen bestanden. Die deutsche Produktionsoberfläche ist mit synthetischen Clips einschließlich nativer Speicherdialoge und 800 Pixel Hauptfensterbreite bedient. Eine eigene englische visuelle V03- und umfassende VoiceOver-Abnahme bleiben Q03. [V03-Nachweise](VIDEO-TRIMMEN-ABNAHME.md).

## V04 Teilabnahme – 16. Oktober 2026

Die neuen Hinweise zu Speicherplatz, Ruhezustand und geänderter Bildschirmkonfiguration sind in Deutsch/Englisch übersetzt. Aktuell **758 App-Texte**, vier InfoPlist-Texte und 13 Domain-Texte; Compiler-Abdeckung im separaten Lokalisierungsbuild, passende Formatargumente und native Sprachprüfungen am abschließenden App-Bundle bestanden, einschließlich englischem Rückfall bei französischer Präferenz. Die tatsächliche Aufnahmeabnahme bleibt teilweise offen; Ton-/Synchronitätstests sind weiter verschoben. [V04-Nachweise und Grenzen](VIDEO-V04-ABNAHME.md).

## Sprachschalter in den App-Einstellungen – 18. Oktober 2026

- Nativer Menü-Picker unter Einstellungen → Allgemein → Sprache mit Systemsprache, Deutsch und Englisch. Der vorhandene Sprachkatalog enthält alle neuen Beschriftungen auf Deutsch/Englisch.
- Änderungen gelten nach dem nächsten App-Start für SwiftUI, AppKit, Menüs, Aufnahmefenster und Domain-Ressourcen. Ein Hinweis erklärt das; bei geänderter Auswahl erscheint „Snaprivo beenden“. Diese Aktion verwendet den bestehenden NSApplication-Beenden-Ablauf mit Sicherung/Finalisierung, keine erzwungene Prozessbeendigung und keinen automatischen Neustart. Zur ursprünglichen Auswahl zurückzukehren entfernt den ausstehenden Neustarthinweis.
- AppPreferences liest nur den expliziten eigenen Preferences-Domain. Eine geerbte globale Sprachliste wird nicht als App-Überschreibung ausgegeben. Systemauswahl entfernt nur den eigenen AppleLanguages-Schlüssel. Andere Einstellungen und Nutzerdaten bleiben erhalten.
- Eigene Katalogänderungen wurden additiv ergänzt; die bereits vor der Aufgabe vorhandenen Katalogeinträge bleiben erhalten.

Erfolgreich ausgeführt:

```sh
./scripts/build.sh -derivedDataPath "$PWD/build/ProPackage"
python3 scripts/check-localization.py build/ProPackage
./scripts/test-settings.sh
./scripts/test-localization.sh "$PWD/build/ProPackage/Build/Products/Debug/Snaprivo.app"
./scripts/test.sh
```

Signierter App-Build erfolgreich. **939 App-, sieben InfoPlist- und 13 Domain-Texte** mit vollständiger Compiler-Abdeckung und passenden Formatargumenten. Einstellungsprüfungen bestätigen Speicherung und erneutes Laden der Auswahl, regionale native Überschreibungen, Rückkehr zur ursprünglichen Auswahl, Entfernen der App-Überschreibung sowie unveränderte andere Einstellungen und globale Sprache. Alle **128 Domain-Tests** bestehen.

Der native Sprachtest startet zusätzlich getrennte Prozesse mit einer pro Lauf eindeutigen Test-Bundle-ID. Ohne Kommandozeilen-Sprachüberschreibung prüft er die gespeicherte Auswahl Englisch → Deutsch → Systemsprache und eine vorhandene `de-DE`-Überschreibung. Nach jedem Neustart stimmen App-/Aufnahmetexte und Domain-Ressourcen mit der Auswahl überein; ein synthetischer Benutzertitel bleibt unverändert. Der Test entfernt anschließend nur seinen eigenen Preferences-Domain. Die reale Snaprivo-App und die globale Sprache werden nicht geändert.

Die Prüfungen liefen auf macOS 27; macOS 26 und vollständige manuelle VoiceOver-Abnahme bleiben separate Release-Prüfungen.

### Bedienprüfung des neuen Pickers

Die echten Produktionsansichten wurden in einer eigenen Kopie der deutschen UI-Prüf-App mit eindeutiger Bundle-ID und synthetischer Bibliothek geöffnet. Einstellungen über ⌘, geöffnet; der native Picker zeigt Systemsprache, Deutsch und Englisch. Englisch ausgewählt: Auswahlwert, Beenden-Schaltfläche und Hinweis zum erneuten Öffnen sind im Accessibility-Baum und im Fenster sichtbar. Rückkehr zur Systemsprache entfernt Beenden-Schaltfläche und ausstehenden Hinweis wieder. Die Texte und Bedienelemente passen in das Einstellfenster; weitere Bereiche bleiben scrollbar. Die Prüf-App wurde danach regulär beendet. Dies ersetzt keine neue vollständige englische oder VoiceOver-Abnahme und keinen Sandbox-Capture-Test. Die Produktions-App und ihre Spracheinstellungen blieben unverändert. Zusätzlich wurde die Debug-App-Signatur erfolgreich verifiziert; App Sandbox bleibt aktiv.

## Ergänzung – 19. Oktober 2026: Tastaturbearbeitung

„Im Bild bearbeiten“ und der Hinweis zu 1/10 Ausgabepixeln sind auf Deutsch und Englisch ergänzt. Finaler Build `build/QualityImprovements`: 944 App-, sieben InfoPlist- und 13 Domain-Texte mit vollständiger Compilerabdeckung und passenden Formatargumenten. `test-localization.sh` mit diesem Bundle besteht einschließlich Deutsch/Englisch/Rückfallsprache und echten Prozessneustarts der isolierten Sprach-Fixture.

## Ergänzung – 19. Oktober 2026: Scroll-Aufnahme

Foto-/Aufnahmepfeile, kompakte Fertig-Leiste, laufender Status, Teilbildbestätigung und Vorschau sind übersetzt. ScrollUX-Build: 964 App-, sieben InfoPlist- und 13 Domain-Texte, vollständige Compilerabdeckung und passende Formatargumente. Die neuen Menü- und Statuswerte werden zusätzlich im nativen Sprach-Testhost geprüft. Die Grenze der laufenden Aufnahme beschreibt Ausgabepixel statt einer manuellen Abschnittszahl.


## Aufnahmegestaltung – 19. Oktober 2026

Bildschirmmenü und Aktion für ganze Monitore ergänzt. CaptureDesign-Build: 966 App-, sieben InfoPlist- und 13 Domain-Texte, vollständige Compilerabdeckung, passende Formatargumente und bestandene deutsche/englische Laufzeitprüfung. Bestehende Breite-/Höhe-/Übernehmen-Texte werden in der nativen Maßeingabe wiederverwendet.

### 19. Oktober 2026 – überarbeiteter Videoeditor

`VideoEditorDesign`: 990 App-, sieben InfoPlist- und 13 Domain-Texte mit vollständiger Compilerabdeckung. Native deutsche/englische Laufzeitprüfungen einschließlich „Video kürzen“, „Schnitt sichern“, MP4-Export und Einzelbild-Auswahl sowie Sprachpräferenz-/Neustartphasen bestanden. [Bedienprüfung und Nachweise](VIDEO-TRIMMEN-ABNAHME.md).

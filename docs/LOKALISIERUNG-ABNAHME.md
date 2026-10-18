# Deutsch und Englisch

Stand: 14. Oktober 2026. Implementiert, automatisiert und visuell auf macOS 27 mit Retina-Anzeige geprüft; macOS 26 bleibt die Mindestversion.

## Sprachwahl und Umfang

Die App liefert Deutsch (`de`) und Englisch (`en`). macOS wählt die am höchsten bevorzugte unterstützte Sprache; Englisch ist die Entwicklungssprache und der Rückfall, wenn keine unterstützte Sprache bevorzugt wird. Die Sprache einer einzelnen App lässt sich unter Systemeinstellungen → Allgemein → Sprache & Region → Apps wählen. Snaprivo anschließend neu starten. Es gibt keinen zweiten app-eigenen Sprachzustand.

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

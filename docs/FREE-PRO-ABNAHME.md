# Free, Pro und Einmalkauf

Stand: 18. Oktober 2026. Paket und Preis vom Nutzer bestätigt. Diese Entscheidung ersetzt frühere Vorschläge im Product Brief. Die technische Umsetzung ist keine Freigabe zur Store-Veröffentlichung.

## Bestätigte Aufteilung

| Free | Pro |
| --- | --- |
| Unbegrenzte Bereichs-, Fenster- und Bildschirm-Screenshots, Hotkeys, Countdown, Schnellvorschau, Kopieren, Anheften | Scroll-Aufnahmen |
| Pfeile, Text, Rechtecke, Ellipsen, Zuschneiden, Größenänderung, Abdecken und Unschärfe | Callouts, Schrittnummern, Textmarker, weitere Formen und handgezeichnete Stile |
| Objektliste, Auswahl, Benennung, Ebenenreihenfolge, Gruppen und Undo | Eigene Stilvorlagen anwenden und neu speichern, Bilder als Objekte einfügen |
| Lokale Bibliothek ohne künstliches Mengenlimit, Titelsuche, Favoriten | Tags, Sammlungen, direkte Texterkennung und OCR-Inhaltssuche |
| PNG, JPEG, einzelnes Bild-PDF, Zwischenablage, Teilen und bearbeitbare Projektdateien | Präsentationshintergründe, Außenabstand, runde Ecken und Schatten |
| Vorhandene Anleitungen öffnen, ansehen und als PDF/Markdown/bearbeitbare Kopie exportieren | Anleitungen erstellen, Schritte/Beschriftungen/Stil bearbeiten und Bilder aktualisieren |
| Vorhandene Videos ansehen und den gespeicherten Ausschnitt als MP4 exportieren | Videos aufnehmen, Systemton/Mikrofon und Schnitt bearbeiten |
| Alle Inhalte importieren, sichern, wiederherstellen, umbenennen, in den Papierkorb verschieben und löschen; Speicherverwaltung | Kein Aufpreis für Datenrettung oder Datenzugriff |

Vorhandene Pro-Objekte werden in Free weder entfernt noch aus dem Renderer ausgeblendet. Position, Reihenfolge, Objektname und Entfernen bleiben verfügbar; neue Pro-Objekte und Pro-Werkzeug-/Stilaktionen benötigen die Freischaltung. Vorhandene eigene Stilvorlagen dürfen weiter verwaltet und gelöscht werden. Bearbeitbare Kopien und Wiederherstellung dürfen Pro-Inhalte enthalten. Es gibt keine Wasserzeichen, Aufnahmezähler oder neuen Bibliothekslimits. Bereits vorhandene technische Format-/Speichergrenzen bleiben bestehen.

## Umsetzung

- `ProFeature` beschreibt die Paketgrenzen ohne UI-, Capture- oder StoreKit-Abhängigkeiten im Domain-Paket.
- `WorkspaceModel` installiert dieselbe MainActor-Policy in Bildeditor, Anleitungen, Videobibliothek/-editor und Capture-Koordinator. Einzelne Renderer-/Persistenzmodelle bleiben unabhängig testbar; der Produktions-Workspace erzwingt die Apple-geprüfte Freischaltung.
- Aktionen öffnen eine Paywall mit dem angefragten Vorteil. Im regulären App-Build ist dies ein eigenes natives Fenster, damit sie auch aus Einstellungen, Ausgabedialog und Videovorschau erreichbar bleibt. Der Ersatz als Sheet dient isolierten Hosts.
- Capture wird vor Berechtigungsanfragen und erneut nach der Auswahl autorisiert. Der Wechsel Bild → Video in der Auswahl ist eingeschlossen. Stoppen und Finalisieren einer schon gestarteten Aufnahme bleiben möglich.
- OCR beginnt in Free nicht, auch wenn eine frühere Pro-Einstellung noch gespeichert ist. Während der ersten Belegprüfung und Bibliotheksauflistung startet keine Erkennung und ein vorhandener Pro-Cache bleibt erhalten. Bei bestätigtem Free-Status oder Verlust des Entitlements werden Jobs abgebrochen und der OCR-Cache entfernt. Tags und Sammlungen bleiben in den Projekten erhalten; Free sucht nur nach Titeln.
- Ein Widerruf setzt neue Pro-Werkzeugvorgaben und ungespeicherte Video-Schnittgrenzen zurück, ohne gespeicherte Objekte, Anleitungen oder Ausschnitte zu verändern. Vorher ausgeführte Änderungen dürfen weiterhin gesichert werden.
- Kauf, ausstehender Kauf, Abbruch, Fehler, Restore, Neustart und Widerruf bleiben am verifizierten StoreKit-Entitlement ausgerichtet. Keine lokale Boolean-Einstellung oder eigene Lizenzserverlogik schaltet Pro frei.

## Preis und Einrichtung im Store

Nicht verbrauchbarer In-App-Kauf: `com.snaprivo.pro.lifetime`, Name **Snaprivo Pro**. **29,99 € zur Einführung, danach 39,99 € einmalig** im deutschen Store. Einführung: die vorgeschlagenen ersten vier Wochen ab öffentlichem Verkaufsstart; Kalenderdaten vor Release festlegen. Enthaltene Pro-Funktionen dauerhaft freigeschaltet, kein Abo und keine spätere Nachzahlung für einen Einführungskauf. Eine Pro-Testphase wurde nicht beauftragt und ist nicht implementiert.

Die App verwendet ausschließlich `Product.displayPrice` und das aktuelle Produkt von Apple. Nur wenn der Store tatsächlich **29,99 EUR** liefert, erscheint zusätzlich „Einführungspreis“ und der in derselben Währung/Locale formatierte spätere Preis **39,99 EUR**. Bei 39,99 EUR oder anderen Preisen/Währungen erscheint keine erfundene Einführungsermäßigung. Ohne Produkt/Preis bleibt Kaufen gesperrt; Free und Restore sind erreichbar. Der Preis wird vor dem Kauf neu geladen; bei einer Änderung muss der neue Preis erneut bestätigt werden.

**Noch extern einzurichten:**

1. In App Store Connect das obige nicht verbrauchbare Produkt für `com.snaprivo.app` anlegen, deutsche/englische Beschreibung und Review-Screenshot hinzufügen, Verträge/Verfügbarkeit prüfen.
2. Im deutschen Store 29,99 € zum Verkaufsstart einstellen und den Wechsel auf 39,99 € nach vier Wochen planen. Andere Storefronts bewusst über Apples Preispunkte konfigurieren; keine pauschale 1:1-Währungsumrechnung in der App.
3. Produkt und Preisplan im Store prüfen und den signierten Kandidaten in Apples Sandbox/TestFlight mit Kauf, Wiederherstellung, Offline-Neustart und Erstattung abnehmen. Keine Veröffentlichung wurde vorgenommen.

Die lokale Datei `Tests/Fixtures/Snaprivo.storekit` enthält den Einführungspreis in einer deutschen Test-Storefront. Der native StoreKit-Test erzeugt zusätzlich eine temporäre Konfiguration für 39,99 €. Diese Dateien richten keine Preise in App Store Connect ein. Der kommerzielle Client ist im Code aktiviert; ein Kauf ist nur mit einem vom Store gelieferten Produkt möglich.

Apple-Referenzen: [Produktpreis formatieren](https://developer.apple.com/documentation/storekit/product/priceformatstyle), [IAP-Preise und zeitlich begrenzte Preisänderungen](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/).

## Prüfung

- `./scripts/build.sh -derivedDataPath "$PWD/build/ProPackage"`: signierter Debug-Build; Signaturprüfung und aktive App Sandbox bestätigt. Referenzrechner: arm64, macOS/SDK 27; Mindestversion macOS 26 bleibt separate Release-Abnahme.
- `./scripts/test.sh`: 128 Domain-Tests einschließlich expliziter Free-/Pro-Grenzen für Objekte, Zeichenstile und Werkzeuge.
- `./scripts/test-release-workflows.sh --sandbox`: bestehende Gesamtsicherung/Restore/Finder-/Papierkorb-/Anleitungs-/Schnellvorschau-Regression plus Free-/Pro-Prüfungen. Neue Pro-Aktionen abgelehnt, bevor Daten geändert oder Capture-Rechte angefragt werden; Kaufabbruch/ausstehender Kauf schalten nichts frei. Kauf entsperrt vorhandene Modelle. Widerruf erhält Bildobjekte, Tags, Anleitung und gespeicherten Videoausschnitt. PNG, Anleitungs-PDF, Video-MP4, Backup und Papierkorb funktionieren danach ohne Pro. Preisänderung bei offener Paywall verlangt einen neuen Klick; fehlende Angebote verhindern Kauf; reguläre/fremde Währung erhält keinen falschen Einführungsvermerk.
- `./scripts/test-storekit.sh`: zwei native StoreKit-Xcode-Tests mit deutschem Test-Store: 29,99 € einschließlich späterem Preis, verifizierter Kauf über das App-Modell, Neustart, Restore, Erstattung/Entitlement-Update; 39,99 € ohne Einführungsvermerk. Keine echten Käufe.
- `./scripts/test-library.sh --sandbox`: echte Vision-Erkennung synthetischer Bilder, persistenter OCR-Cache, Metadaten, Ausschalten/Löschung, veraltete Erkennung nach Abdeckungen, erste Belegprüfung bei bestehendem Cache sowie Bildwechsel/Autosave/Export/Persistenz erfolgreich.
- `./scripts/test-settings.sh`: Einstellungen, Shortcuts, Ordnerfreigaben, Bibliothekswechsel und automatisches Kopieren erfolgreich.
- `./scripts/test-video-editing.sh --sandbox`: Schnittgrenzen, Undo/Redo, H.264-/AAC-/stiller Export, unverändertes Original, Backup/Restore und echter Prozessneustart erfolgreich.
- `./scripts/test-capture.sh`: vorhandene Aufnahmeauswahl-, Koordinaten-, Hover-/Fenster-, Tastatur- und Abbruchregression erfolgreich.
- `python3 scripts/check-localization.py build/ProPackage`: 934 App-, 7 InfoPlist- und 13 Domain-Texte vollständig auf Deutsch/Englisch, passende Formatargumente und vollständige Compilerabdeckung.
- Isolierte Produktionsoberfläche mit synthetischen Bildern: Free zeigt Pro-Kennzeichnung und kontextbezogene OCR-Paywall; Einführungspreis, späterer Preis und sichtbare Vorteile geprüft. Ein ausschließlich lokal simulierter Kauf zeigt „Pro ist aktiviert“ und entsperrt den vorhandenen Editor samt Callout ohne Neustart. Visueller Nachweis: `build/pro-paywall-launch-ui.png`. Die Test-App verwendet eigene temporäre Daten und einen ausschließlich in der Fixture definierten Store-Client.

Im Widerrufstest gefundene Rekursion bei Video-Schnittgrenzen wurde vor Abschluss behoben und in der Sandbox erneut erfolgreich geprüft. Bereits offene Hardware-/Capture-/Ton-/vollständige VoiceOver-Abnahmen aus dem Arbeitsplan bleiben bestehen. App-Store-Connect-Produkt, kalenderbasierter Preisplan und reale Store-Sandbox/TestFlight-Prüfung sind durch lokale Tests nicht ersetzt.

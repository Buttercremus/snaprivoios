# Speicherorte und Erscheinungsbild

Stand: 14. Oktober 2026. Implementiert auf Nutzerwunsch für PNG-Ausgaben und bearbeitbare Bildprojekte. Die bestehenden Aufnahme-/Editorfunktionen und das Dokumentformat 6 bleiben kompatibel.

## Bedienung

- **Einstellungen → Allgemein → Darstellung:** System, Hell oder Dunkel. System folgt macOS; Hell/Dunkel überschreiben die App-Darstellung sofort und bleiben nach Neustart erhalten. Alle App-Fenster verwenden die gemeinsame `NSApplication.appearance`; Bildpixel werden nicht verändert.
- **Einstellungen → Speicherorte → PNG-Standardordner:** Ein nativer Ordnerdialog legt den Anfangsort für „PNG speichern …“ fest. Dateiname und Ziel bleiben im Speicherdialog wählbar. Zurücksetzen entfernt nur diese Vorgabe. Es entsteht keine zusätzliche automatische PNG-Datei nach einer Aufnahme.
- **Einstellungen → Speicherorte → Projektbibliothek:** Der gewählte Ordner enthält anschließend `Snaprivo-Bibliothek`. Wird direkt ein Ordner dieses Namens ausgewählt, wird er selbst verwendet. Vorhandene Projekte einschließlich Papierkorb werden übernommen; neue Aufnahmen und Bearbeitungen verwenden danach den neuen Ort.
- Der bisherige Bibliotheksordner bleibt als Kopie erhalten. Eine bereits vorhandene andere Zielbibliothek wird abgelehnt; Zusammenführen oder stilles Überschreiben ist nicht implementiert. Wer zu einer früheren Kopie zurückkehren möchte, muss deren Daten bewusst verwalten; die Ordnerwahl ist kein Import bestehender Bibliotheken.
- Nicht erreichbare oder widerrufene Bibliotheksfreigaben werden angezeigt. „Ordner erneut freigeben …“ nimmt den bisherigen Ort wieder in Betrieb; ohne Zugriff entstehen keine Projekte in einem versteckten Standardordner.
- Videoaufnahmen behalten ihre separate bisherige Ablage. Diese Einstellung betrifft Bildprojekte.

## Datenübernahme und Sandbox

Die PNG-/Bibliotheksordner haben getrennte Security-Scoped Bookmarks in den App-Einstellungen. Der native Ordnerdialog erteilt Zugriff; die öffentlichen Bookmark-APIs erhalten ihn über einen Neustart. Veraltete Bookmarks werden nach erfolgreichem Zugriff erneuert. Fehlgeschlagene Freigaben ersetzen keine bisherige Einstellung. Der Zugriff bleibt während der Nutzung aktiv und wird bei Wechsel/Zurücksetzen/Beenden beendet. Sandbox und benutzergewählter Lese-/Schreibzugriff bleiben aktiv; ergänzt wurde `com.apple.security.files.bookmarks.app-scope`.

Die eingebetteten Entitlements des Apple-Development-Builds wurden gelesen: Sandbox, benutzergewähltes Lesen/Schreiben und App-Scope-Bookmarks sind aktiv. Die strenge Signaturprüfung bestätigt ein gültiges Bundle. Dies ersetzt den persönlichen Ordner-/Neustarttest nicht.

Der Bibliothekswechsel wartet auf offene Schreib-/Text-/Stilarbeit. `ProjectStore` kopiert unter seiner Dateisperre außerhalb des MainActor die vollständigen Projektpakete samt `.Trash` in einen temporären Zielordner. Alle Dateinamen und Bytes werden verglichen; aktuelle/vorherige Revisionen, Originale, Vorschaubilder und Metadaten bleiben erhalten. Ungültige Projekte, Symlinks sowie verschachtelte Quell-/Zielorte werden abgelehnt. Erst nach erfolgreicher Prüfung wird der Ordner atomar veröffentlicht und die neue Einstellung gespeichert. Fehler entfernen den temporären Zielstand und lassen Quelle/Einstellung aktiv. Der offene Editor behält Sitzung, Auswahl, Zoom und Undo; sein Speicherziel wird auf die kopierte Bibliothek umgestellt. Normales Beenden wartet auf eine laufende Übernahme.

Öffentliche API-Grundlagen: [NSApplication.appearance](https://developer.apple.com/documentation/appkit/nsapplication/appearance), [Sandbox und Bookmarks](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

## Automatisierte Nachweise

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-settings.sh
./scripts/test-transfer-privacy.sh
./scripts/test-autosave.sh
```

87 Domain-Tests einschließlich fünf neuer Bibliothekskopierprüfungen: Originale/Revisionen/Thumbnail/Papierkorb erhalten, unabhängiges Weiterspeichern, bestehende und verschachtelte Ziele abweisen, Symlink- und unvollständige Projektfehler ohne veröffentlichtes Ziel, temporäre Daten bereinigen, leere Erstbibliothek.

Die nativen Settings-Prüfungen verwenden ausschließlich temporäre Defaults/Ordner und synthetische Bilder. Geprüft werden die tatsächlichen App-Typen: System/Hell/Dunkel einschließlich Fensterdarstellung und erneutem Laden; PNG-Anfangsort im echten `NSSavePanel`; Erneuern/Verweigern/Fehler von Bookmarks mit ausgeglichenem Zugriff; Übernahme mit offenem Editor, Favorit, Crop, Zielauflösung, Papierkorb und ausstehenden Änderungen; Undo schreibt anschließend nur im neuen Ort; Zielkonflikte erhalten Einstellung/Editor; erneut geladene Bibliothek nimmt neue Bilder am gewählten Ort auf; Zugriffsausfall schreibt nicht im Standardordner und erneute Freigabe stellt die Bibliothek wieder her.

Transfer-/Datenschutz- und Autosaveprüfungen schützen die bestehenden Export-/Speicherabläufe. Die Einstellungsansichten werden zusätzlich in einem isolierten Prozess in Hell/Dunkel gerendert. Nutzerbibliothek, reale Einstellungen und Bildschirmfreigaben werden dabei nicht geändert.

## Noch persönlich zu prüfen

Der Nutzer übernimmt die Bedienprüfung. Die injizierten Bookmark-Prüfungen ersetzen keinen Neustart des signierten Sandbox-Builds mit echten macOS-Zugriffstoken. Ordnerdialog abbrechen/wählen, PNG speichern, Bibliothek wechseln, App beenden/neu starten und Freigabe auf realen externen Datenträgern erneut prüfen. Nicht angeschlossene Laufwerke, tatsächlich voller Datenträger, Prozessabbruch während großer Kopien und breite Accessibility-/Darstellungsabnahme bleiben Q02/Q03. Atomare Veröffentlichung ist keine Garantie gegen defekte Datenträger; die Quellkopie bleibt deshalb erhalten.

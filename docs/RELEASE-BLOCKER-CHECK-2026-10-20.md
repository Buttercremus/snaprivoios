# Release-Blocker-Prüfung – 20. Oktober 2026

Ergebnis: In den überprüften Abläufen kein nachgewiesener P0/P1-Fehler (Absturz, Datenverlust, ungeschützter flacher Export oder defekter Kaufpfad). Das ist keine vollständige Freigabe des noch nicht geprüften Store-Artefakts. Diese Runde änderte keinen Produktcode.

## Frisch ausgeführte Prüfungen

- Optimierter Release-Build mit Xcode, Ziel macOS 26.0: erfolgreich. `lipo` bestätigt arm64 und x86_64. Ausführung der nativen Tests auf arm64/macOS 27.0; keine Intel- oder macOS-26-Laufzeitabnahme.
- `codesign --verify --deep --strict`: erfolgreich. Sandbox, Mikrofon, benutzergewählte Dateien und Bookmarks im Bundle vorhanden. Die isolierte erste Signaturprüfung konnte der Zertifikatskette nicht vertrauen; die reguläre Prüfung bestand. Der lokale Build ist entwicklersigniert und enthält `get-task-allow`; er ersetzt kein für den Store exportiertes Archiv.
- `test-release-workflows.sh --sandbox`: vollständige Sicherung/Wiederherstellung, Papierkorb, beschädigte Daten, unterbrochene Videos, Finder-Routing, Anleitungen, Free/Pro und simulierte Kaufzustände bestanden.
- `test-transfer-privacy.sh`: deckende PNG-/Clipboard-/Transferausgabe nach Crop/Resize, stabile Exportstände, Fehler/Zieldateierhalt, Beenden während Export, Backup/Neustart und simulierte Berechtigungswechsel bestanden. Kein tatsächlicher Versand an externe Dienste.
- `test-video-editing.sh --sandbox`: Schnitt, Live-Griffe, Vorschau, synthetische H.264-/AAC-Ausgabe, GIF samt Zeitgrenze/Abbruch/Zieldateierhalt, Originalschutz, Backup/Restore und echter Testprozessneustart bestanden. Keine neue physische ScreenCaptureKit-/Mikrofonaufnahme.
- `test-storekit.sh`: zwei native lokale StoreKit-Tests, null Fehler; Kauf/Restore/Erstattung und regulärer Preis. Keine echten Käufe.
- Lokalisierung des Release-Builds: 1070 App-, 7 InfoPlist- und 18 Domain-Texte, vollständige Deutsch-/Englisch-Abdeckung.
- 89 direkt im Quelltext angegebene SF-Symbole über AppKit auf macOS 27 aufgelöst; keine fehlenden Symbole.
- `git diff --check`: bestanden.

Die zuvor am selben aktuellen Funktionsstand geprüfte vollständige Canvas-Suite einschließlich beider Lupenarten bleibt grün; in dieser Audit-Runde ohne weitere Codeänderung nicht wiederholt. Die letzte Domain-Runde bestand mit 149 Swift-Testing-Tests plus zwei XCTest-Prüfungen.

Lokale Logs: `/tmp/snaprivo-release-audit-build.log`, `-workflows.log`, `-privacy.log`, `-video.log`, `-storekit.log`, `-symbols.log`. Release-Bundle: `build/ReleaseAudit/Build/Products/Release/Snaprivo.app`.

## Kleiner Codebefund – am 21. Oktober behoben

Beim Umstellen einer bestehenden normalen Lupe auf Versetzt verschiebt `EditorModel.updateMagnifierOffset` den großen Kreis um einen Durchmesser nach rechts. Der folgende `updateInstructionObject`-Commit erweitert die Zeichenfläche nicht. Nahe dem rechten Bildrand kann deshalb ein Teil der Lupe außerhalb der Ausgabe liegen. Die Objektdaten bleiben erhalten; die Lupe kann zurückbewegt oder zurückgestellt werden. Befund aus dem konkreten Codepfad, nicht durch einen neuen nativen Randfalltest reproduziert. Das ist ein begrenzter Darstellungs-/Bedienfehler, kein nachgewiesener Datenverlust oder Crash.

Nachtrag 21. Oktober: Die Umschaltung verwendet jetzt den bestehenden Commit mit Zeichenflächenerweiterung. Lupengeometrie, Zeichenfläche, Zuschnitt und Ausgabegröße werden gemeinsam rückgängig gemacht. Die neue native Randfallprüfung mit und ohne Zuschnitt/freier Skalierung bestätigt Undo/Redo, Wiederöffnen und PNG-Rahmenpixel. App-Build und vollständige Canvas-Suite bestanden. Der untenstehende Release-Abnahmebedarf bleibt bestehen.

## Vor öffentlichem Release noch bestätigen

1. Den tatsächlich einzureichenden signierten Store-Kandidaten installieren und ein Update mit vorhandenen Projekten durchführen: Öffnen, Bearbeiten, Neustart, Export. Der lokale Release-Build ersetzt diesen Schritt nicht. Projektformat 14 liest alte Formate; ältere App-Versionen können neue Projekte nicht lesen.
2. Aufnahme, Berechtigungen und neue Klickmarkierungen auf der zugesagten Mindestversion macOS 26 prüfen; längere echte Videoaufnahme mit den beworbenen Tonoptionen und anschließendem Schnitt/Export. Die bestehende 15-Minuten-/Mehrdisplay-Abnahme ist weiter offen.
3. Versions-/Buildnummer des tatsächlichen Uploads prüfen. Lokal steht 0.1.0 (2); ob diese Nummer schon in App Store Connect verwendet ist, wurde nicht abgefragt. Daraus wird kein bestätigter Upload-Blocker abgeleitet.

Die vom Nutzer bereits bestätigten Kauf-/Restore- und Store-Vorbereitungsabnahmen bleiben anerkannt. Veraltete offene Store-Einträge in älteren Dokumenten heben diese Bestätigung nicht auf.

## Geprüfter Fehlalarm: Privacy-Manifest

Im lokalen Bundle liegt kein PrivacyInfo.xcprivacy. Apples aktuelle Required-Reason-API-Dokumentation nennt für diese Deklarationspflicht iOS, iPadOS, tvOS, visionOS und watchOS, nicht macOS. Deshalb wird die fehlende Datei in dieser reinen nativen macOS-App nicht allein als nachgewiesener Store-Blocker gewertet. Es sind keine externen SDK-Abhängigkeiten hinzugekommen. Quelle: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api (am 20.10.2026 geprüft, Markdown-Fassung).

# Auswahlrahmen und Debug-Erweiterungen

Stand: 2. November 2026. Nutzerauftrag: mehrere Bildeditor-Objekte im Auswahlwerkzeug durch Ziehen mit der linken Maustaste markieren und gemeinsam löschen.

## Bedienung und Umsetzung

Auf freier Bild- oder Arbeitsfläche beginnt ein möglicher Auswahlrahmen. Ab 3 pt Mausbewegung erscheint eine dünne Akzentkontur mit dezenter Systemfarbfüllung. Geschnittene sichtbare Objektgrenzen werden live hervorgehoben. Die Vorschau bleibt bis zum Loslassen lokal im Canvas; sie verändert weder Dokument noch bisherige Auswahl. Umschalt ergänzt die vorherige Auswahl. Escape, Fokusverlust, Werkzeugwechsel, Zuschneiden oder Bildwechsel verwerfen den Rahmen. Ein einfacher Hintergrundklick wählt weiterhin das Quellbild, Objektziehen und bestehende Griffe behalten Vorrang.

Auswahl verwendet vorhandene Quell-/Ansichtsprojektion und bemalte Objektgrenzen, damit auch waagerechte Pfeile sowie Text, Callouts und gedrehte Bilder berücksichtigt werden. Der wählbare Bereich wird auf den aktuellen Zuschnitt begrenzt. Gruppen werden vollständig ausgewählt. Rücktaste/Entf nutzen die vorhandene gemeinsame Löschung samt Undo/Redo und Autosave; das Originalbild wird nicht gelöscht. Keine Persistenz neuer Auswahlzustände, keine Export- oder Projektformatänderung. Die Werkzeughilfe erklärt den Rahmen und Umschalt auf Deutsch und Englisch.

## Technischer Nachweis

- `./scripts/build.sh -derivedDataPath build/MarqueeSelection/Xcode`: bestanden.
- `./scripts/test.sh`: 192 Domain-Tests bestanden.
- `./scripts/test-canvas.sh`: vollständige Regression einschließlich der neuen Auswahlrahmen-Tests bestanden; fokussierter Wiederholungslauf mit `--marquee-only` ebenfalls bestanden.
- `python3 scripts/check-localization.py build/MarqueeSelection/Xcode`: 1449 App-, 7 InfoPlist- und 19 Domain-Einträge vollständig auf Deutsch/Englisch.

Neue synthetische `MarqueeSelectionChecks`: vorwärts/rückwärts/teilweise Überschneidung, additive Auswahl, mehrere Zoomstufen, nicht proportional verkleinerte und zugeschnittene Bilder, globale Drehung/Spiegelung, waagerechte Pfeile, außerhalb des Bildes begonnener Rahmen und unsichtbare Objekte außerhalb des Zuschnitts. Außerdem Abbruch, bestehender Quellbildklick, Sperre von Delete/Undo während des Ziehens, Gruppen, beide Löschtasten, ein Undo/Redo und tatsächlich neu geladene Projektdateien. Bestehende Canvas-Prüfungen decken weiter Verschieben, Griffe, Text, Schwenken und andere Werkzeuge ab.

## Gemeldete Strip-Warnungen

`COPY_PHASE_STRIP` war im Debug-App-Target implizit `YES` (Vorgabe der lokalen Xcode-Buildspezifikation). Beim Einbetten der schon signierten `.appex`-Bundles versucht `builtin-copy` dadurch nochmals Symbole zu entfernen und meldet zu Recht, dass es signierte Binärdateien nicht verändert. Im Debug-App-Target ist diese Kopieroption nun ausdrücklich `NO`. Release-Konfiguration und reguläre Signierung bleiben erhalten.

Der abschließende Debug-Build enthält keine `not stripping binary because it is signed`-Warnung. Die beiden Embed-Copy-Aufrufe enthalten keinen Strip-Schritt mehr. `codesign --verify --deep --strict --verbose=2` validiert die App und beide eingebetteten Quick-Look-Erweiterungen einschließlich ihrer Debug-/Preview-Dylibs. Keine Änderung an Sandbox, Entitlements oder Signaturprüfung.

Die isolierte deutsche Prüf-App zeigt das aktive Auswahlwerkzeug mit neuer Werkzeughilfe, unveränderten übrigen Werkzeugen und drei synthetischen Objekten. Eine zusätzliche sichtbare Mausbedienung ließ sich in dieser Sitzung nicht abschließen: Die UI-Steuerung konnte das native Fenster lesen und per Accessibility bedienen, meldete beim Ziehen jedoch wiederholt `windowNotFoundAtPosition`, auch nach Anheben und Größenänderung des Fensters. Der vollständige Ziehen-/Löschen-/Undo-Ablauf ist deshalb hier durch die echten Canvas-Eventhandler im Offscreen-Fenster nachgewiesen; eine sichtbare Pointer-Abnahme und vollständiges VoiceOver bleiben davon getrennt. Logs: `/tmp/snaprivo-marquee-{build,canvas,focused,domain,signatures,fixture}.log`; synthetische Prüf-App und Buildprodukte liegen ausschließlich im ignorierten `build`-Verzeichnis.

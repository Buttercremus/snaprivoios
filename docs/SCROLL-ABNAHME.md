# Scroll-Aufnahme – Bedienung und Abnahme

Stand: **19. Oktober 2026, nach Korrektur des Maskenwechsels, Live-Abgleichs und Abschlusses**. Der Nutzer hat nach der Snagit-Referenz ausdrücklich **selbst scrollen, automatisch zusammensetzen, Fertig** gewählt. Der neue Ablauf ersetzt das manuelle Hinzufügen einzelner Abschnitte. Breite reale Website-/Hardwareabnahme bleibt P01; die historischen Desktop-Nachweise weiter unten betreffen den früheren T01-Prototyp.

## Bedienung

1. In der Bildübersicht den kleinen Pfeil neben **Neue Aufnahme** öffnen und **Scroll-Aufnahme** wählen. Alternativ im Auswahlrahmen den kleinen Pfeil neben **Foto** verwenden oder **Aufnahme → Scroll-Aufnahme …** wählen. Scroll gehört zu Pro.
2. Nur den scrollenden Inhalt markieren und bestätigen. Der ursprüngliche Ausschnitt wird übernommen; kein erneutes Aufziehen nach der Menüwahl nötig. Der normale Fotoklick und die direkte Videoaktion bleiben erhalten.
3. Selbst langsam nach unten scrollen. Snaprivo prüft Bildstände und setzt sie automatisch zusammen. Die vorhandene Auswahlmaske bleibt mit derselben Abdunklung und demselben Rahmen sichtbar; nur der eingefrorene Inhalt wird live und klickdurchlässig. Eine kleine Vorschau zeigt das wachsende Bild. Es gibt keine Abschnittsliste und keinen Hinzufügen-Knopf.
4. **Fertig** wartet die laufende Prüfung ab und prüft den letzten Bildstand. Ist dieser vorübergehend nicht zuzuordnen, wird kurz automatisch nachgeprüft. Ein bereits enthaltenes Ende öffnet direkt, ein passender neuer unterer Streifen wird noch ergänzt. Danach öffnet das lange Bild als normales bearbeitbares Projekt im Editor. Auch ohne Scrollbewegung ist das erste Bild übernehmbar.
5. Bei einem uneindeutigen Übergang etwas zurück und langsamer weiter scrollen. Kann das letzte Stück nicht übernommen werden, wird dies angezeigt; **Übernehmen** bestätigt ausdrücklich nur das bisherige Teilbild. Abbrechen verwirft die Sitzung. Kein stiller vollständiger Erfolg bei einem fehlenden letzten Stück.

Unter **…** sind **Neu beginnen**, der anfängliche Ausschluss fester oberer/unterer Bereiche und die Originalgrößenvorschau erreichbar. Der Ausschluss kann vor der ersten erfolgreichen Ergänzung geändert werden, auch wenn gerade eine Abtastung läuft. Er passt die Bildkomposition an; Fenster und Bereich werden weiterhin nicht verschoben. Die frühere Rücknahme einzelner manuell hinzugefügter Abschnitte entfällt zugunsten dieses Ablaufs.

## Technik und Grenzen

ScreenCaptureKit friert den Desktop für die Bereichsauswahl ein. Beim Bestätigen einer Scroll-Aufnahme werden dieselben Auswahlfenster samt Views, Rahmen und 42-%-Außenmaske an die Sitzung übergeben. Kein Ausblenden, Schließen, Neuaufziehen und keine künstliche Startwartezeit. Nur der gewählte Ausschnitt wird transparent und live; der eingefrorene Außenbereich samt Abdunklung bleibt pixelgleich erhalten. Sämtliche Maskenfenster lassen Eingaben durch. Die Quell-App wird wieder aktiviert, die Fertig-Leiste und die Vorschau liegen über der Maske. Der erste Ausschnitt bleibt als Ausgangsbild erhalten, damit sofortiges Scrollen den Anfang nicht überspringt. Danach liefert `SCScreenshotManager` unveränderte Bildstände über den vorhandenen Retina-/Display-Crop-Pfad; eigene Fenster, Vorschau, Maske und Cursor sind aus Live-Bildständen ausgeschlossen. Filter und Konfiguration werden pro Sitzung wiederverwendet, statt für jedes Bild sämtliche Fenster neu aufzuzählen. Es wird **keine MP4-Datei** geschrieben oder nachträglich zerlegt. Ein Video-Zwischenschritt würde die notwendigen Überlappungsprüfungen nicht ersetzen und zusätzliche Kodierung/Dekodierung benötigen.

Die automatische Abtastung läuft von Beginn an. Jeder neue Bildstand wird direkt mit dem zuletzt übernommenen verglichen; die passende Überlappung bestätigt den Übergang. Es wird nicht mehr auf ein zweites stillstehendes Bild gewartet. Die Analyse verwendet höchstens 128 über die Breite verteilte Spalten, behält aber jede vertikale Pixelzeile und erkennt auch Bewegungen von 1–3 Pixeln. Eine grobe Kandidatensuche wird anschließend dichter und mit Subpixelphasen verifiziert; die Ausgabepixel werden unverändert angehängt. Die CPU-Verarbeitung bleibt außerhalb des MainActor; nur ein Aufnahme-/Verarbeitungsauftrag läuft gleichzeitig. Nach einem Durchlauf folgen 60 ms Pause, keine künstlichen 100 ms zwischen zwei Bildern. Nicht eindeutige Übergänge werden weiter konservativ abgelehnt, statt unbemerkt Streifen zu verlieren oder doppelt einzufügen.

Beim Abschluss wird nach einem nicht eindeutigen Übergang höchstens dreimal mit jeweils 150 ms Pause erneut aufgenommen und geprüft, insgesamt höchstens vier Abschlussversuche. Ein unverändertes Bild ist bereits enthalten und beendet die Prüfung sofort. Ein passender neuer Bildstand wird unverändert ergänzt. Größen-/Pixelgrenzen und Aufnahmefehler werden nicht als vorübergehender Bildabgleich behandelt. Bleibt der Übergang unklar, ist die ausdrückliche Teilbildbestätigung weiterhin nötig; Abbrechen funktioniert auch während der Nachprüfung.

Weiterhin nur **abwärts**, unveränderte Position/Breite/Skalierung, keine horizontale oder automatische Scroll-Steuerung fremder Apps. Maximal 4.096 px pro Eingangskante, 20.000 px Gesamthöhe und 40 MP. Die frühere 50-Abschnitt-Grenze gilt für den historischen manuellen Testpfad; die neue laufende Abtastung wird anhand der Ausgabepixel begrenzt und sammelt keine Liste aller Frames. Originale und Markierungen bleiben im normalen Projektformat. Ein unfertiger Scroll-Vorgang wird bei Abbruch nicht persistiert.

## Neue Prüfnachweise – 19. Oktober 2026

- Signierter Build: `./scripts/build.sh -derivedDataPath "$PWD/build/ScrollContinuity"`.
- `./scripts/test.sh --disable-sandbox`: **140 Domain-Tests**; Pixelgrenzen der laufenden Aufnahme getrennt von der historischen manuellen Abschnittsgrenze geprüft. Der Schalter betrifft die verschachtelte SwiftPM-Compiler-Sandbox in der Entwicklungsumgebung; die App-Sandbox bleibt aktiv.
- `./scripts/test-capture.sh`: Auswahlpfeil am Foto-Button, Foto-/Scroll-/Video-Routing, unveränderter Ausschnitt, ausgeschlossene Videoquelle bei Bild/Scroll, vorhandene Griffe, Koordinaten und Abbruch geprüft.
- `./scripts/test-scroll.sh`: tatsächliche Übergabe derselben sichtbaren Auswahlfenster/Views, unveränderte Außenpixel/Abdunklung/Ausschnitt, transparente Live-Fläche, klickdurchlässige Maske, kein nachträgliches Schließen durch den alten Selektor und vollständiges Aufräumen geprüft. Hinzu kommen pixelgleiche Zusammensetzung, direkte 1–3-px-Bewegung, Ablehnung unsicherer Übergänge, Pixelgrenzen statt Abtastzähler über 50, Fertig während laufender Abtastung, letzter Bildstand, ausdrückliche Teilbildbestätigung, Randmenüs, Abbruch und kein spätes Anhängen. Editor/Autosave/Neustart/Undo/PNG-Regression weiterhin enthalten.
- Abschlussnachprüfung: Vorübergehend leeres Neuzeichnen beim Klick auf Fertig simuliert. Nach passendem Bildstand öffnet ein bereits enthaltenes Ende mit einem Klick (keine doppelte Zeile); ein neuer letzter Streifen wird bis zur exakten Höhe ergänzt. Dauerhaft unzuordenbares Ende stoppt nach vier Abschlussversuchen und verlangt ausdrücklich Übernehmen. Abbruch während einer Wiederholung startet keinen weiteren Auftrag und veröffentlicht kein spätes Bild. Die kurze Meldung lautet jetzt „Ende unklar. Übernehmen öffnet das bisherige Bild.“ statt sicher fehlenden Inhalt zu behaupten.
- Große synthetische Textseite: 2.200 × 1.400 px Eingangsbild; vier nahtlose Übergänge bei Positionen 2/137/391/732 px. Danach zeitgesteuertes Scrollen mit 600 px/s, unabhängig von der Verarbeitung: fünf Abtastungen im ursprünglichen Lauf, sechs im Folgelauf mit stärker variierenden synthetischen Textzeilen; automatische Eckvorschau bis 2.200 × 2.132 px. Keine Einzelabschnitte und keine Pause pro Bild nötig.
- Vergleich auf demselben Testhost im unoptimierten nativen Prüfprogramm: vier Bildübergänge nach der Breitenbegrenzung zunächst 4,09 s, nach vorab berechneten Grenzen, festem Faltungskern und ganzzahliger Kandidatenbewertung 0,85 s. Das ist Verarbeitungszeit mit synthetischen Bildern, keine Messung der ScreenCaptureKit-Gesamtlatenz.
- In der isolierten deutschen Produktionsoberfläche mit ausschließlich synthetischen Projekten das neue Menü neben Neue Aufnahme tatsächlich geöffnet: Foto/Scroll-Aufnahme vorhanden. Foto-/Scroll-Menü und Leiste wurden zusätzlich nativ gerendert. Die UI-Fixture injiziert synthetische Scroll-Frames und fragt keine neue Bildschirmfreigabe an.
- Deutsche/englische Katalog-/Compilerprüfung und Laufzeitprüfung für den ScrollContinuity-Build. Keine privaten Referenzbilder oder OCR-Texte als Fixtures übernommen.

**Nutzerrückmeldung am 19.10.:** Der neue Scroll-Ablauf hat funktioniert. Beim Abschluss erschien noch die Meldung zum letzten Stück; ein weiterer Klick übernahm das Bild. Das belegt einen erfolgreichen praktischen Ablauf, aber nicht, dass das Ende vollständig enthalten war: Der zweite Klick bestätigt im bisherigen Ablauf das bisherige Teilbild. Die kurze automatische Abschlussnachprüfung wurde anschließend ergänzt; die konkrete Seite/Hardware und die Wiederholung dieser Korrektur sind noch nicht protokolliert.

**Offen:** weitere echte ScreenCaptureKit-Aufnahmen mit gleichmäßiger manueller Scrollbewegung, langsamen und dynamischen Seiten, festen Rändern, Vollbild, mehreren Displays, macOS 26 sowie Last/Speicher. Native synthetische Tests und der frühere manuelle Desktop-Test ersetzen diese neue Gesamtprüfung nicht. P01 bleibt entsprechend offen.

## Vergleich mit der Referenz

Die Nutzerbilder von Snagit zeigen ebenfalls eigenes Scrollen und einen Fertig-Button; der entscheidende Unterschied zum alten Snaprivo-Prototyp ist die automatische Zusammensetzung ohne Abschnittsbedienung. Die gewählte Umsetzung folgt diesem Ablauf.

Snagit dokumentiert die zusätzliche Accessibility-Freigabe für seinen **Automatic Scrolling**-Modus: [TechSmith – Enable Scrolling Capture on macOS](https://support.techsmith.com/hc/en-us/articles/203732578-Enable-Scrolling-Capture-on-macOS). CleanShot führt Start und automatisches Scrollen als separate Optionen auf: [CleanShot – URL scheme API, scrolling-capture](https://cleanshot.com/docs-api). Diese Herstellerangaben sind keine Freigabe oder technische Garantie für eine automatische Scroll-Steuerung im sandboxed Snaprivo-Store-Build. Dieser Auftrag fordert dafür keine zusätzlichen Rechte an.

## Historische T01-Nachweise – 13. Oktober 2026

- `./scripts/build.sh`: erfolgreich, Deployment Target macOS 26, Sandbox und bestehende Development-Signierung. Testhost: macOS 27; keine separate Hardware-Abnahme unter macOS 26 behauptet.
- `./scripts/test.sh`: 72 Tests erfolgreich. Scroll-Fälle: exakte Verschiebungen, zu große Sprünge, unveränderte/leere Bilder, wiederholte Muster, feste Kopf- und Fußzeilen, wiederkehrende scrollende Textzeilen, Bewegung, Größen-/Abschnittslimits.
- `./scripts/test-scroll.sh`: drei Ausschnitte pixelgenau rekonstruiert, Orientierung/Naht geprüft, Bewegung und Abschnittslimit abgelehnt. Zusammengesetztes Bild im Editor geöffnet, Pfeil/Text/Rechteck per echtem Autosave gespeichert, mit neuer Workspace-/Store-Instanz geladen, weiterbearbeitet, Undo/Redo und PNG-Auflösung geprüft. Keine echten Bildschirmdaten in Testfixtures.
- `./scripts/test-capture.sh`: Capture-/Berechtigungsregression erfolgreich. Ein Build ersetzt keine Systemfreigabe; der Desktop-Test nutzte die vorhandene Freigabe.

## Desktop-Abnahme am 13.10.2026

Durchgeführt mit dem aktuellen signierten Xcode-Debug-Build und ausschließlich synthetischem Aufnahmeinhalt:

1. Den scrollbaren Bereich der nativen Testfixture gewählt und bestätigt: 1 Abschnitt, 1.295 × 1.370 px.
2. Jeweils 120 pt nach unten gescrollt und Abschnitt hinzugefügt: 2 Abschnitte, 1.295 × 1.610 px; anschließend 3 Abschnitte, 1.295 × 1.850 px.
3. Im Editor geöffnet; fortlaufende Abschnitte 1–8 ohne sichtbare doppelte oder fehlende Textzeilen geprüft.
4. Projekt in `Snaprivo-T01-Abnahme` umbenannt; Pfeil, Text „T01: bearbeitbar“ und Rechteck eingefügt.
5. Snaprivo normal beendet und denselben Build neu gestartet. Bibliothek zeigte `Snaprivo-T01-Abnahme` mit 3 Markierungen.
6. Projekt geöffnet: Auflösung und alle Markierungen erhalten. Pfeil erneut ausgewählt und verschoben, Rückgängig/Wiederholen über die Editoraktionen geprüft. Globaler Tastaturtest wurde dabei nicht erneut abgenommen.

Vorherige Desktop-Tests zeigten auch die sichtbare Ablehnung eines uneindeutigen Übergangs sowie Abbruch ohne neues Projekt. Das fertige synthetische Abnahmeprojekt bleibt in der lokalen Bibliothek zum Nachprüfen erhalten.

### Reproduzierbare Testfixture

`./scripts/build-scroll-fixture.sh` baut `build/ScrollFixture.app` aus `Tests/Fixtures/ScrollFixtureApp.swift`. Die Fixture enthält ausschließlich lokale synthetische Texte und Farbbalken. „Zum Anfang“ setzt zurück; „120 pt nach unten“ führt einen reproduzierbaren Scroll-Schritt aus. Nur den Inhalt links aufnehmen, die Bedienelemente rechts ausschließen. Die tatsächlichen Pixelmaße hängen vom aufgezogenen Bereich und der Displayskalierung ab. Die Fixture gehört nicht zum ausgelieferten App-Target.

## Ordnerumbenennung

Projektwurzel: `/Users/simon/Woerk/Swift/Snaprivo`. Innerer Quellordner: `Snaprivo/`; Xcode-Projekt und Skripte angepasst. `Packages/SnagForgeDomain` ist weiterhin benötigter Quellcode. Die damaligen Angaben zur Identität sind historisch; aktuell gilt `com.snaprivo.app`, alte Container werden ausdrücklich als Kopien übernommen. Keine Nutzerprojekte gelöscht.

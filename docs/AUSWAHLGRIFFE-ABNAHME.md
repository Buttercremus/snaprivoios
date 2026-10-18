# Einheitliche Auswahlgriffe

Stand: 14. Oktober 2026. Implementiert; automatisiert und visuell mit synthetischen Bildern geprüft. Die persönliche Bedienprüfung übernimmt der Nutzer.

## Darstellung und Bedienung

Aufnahmeauswahl, Formen, Callout-Rahmen, Schrittmarken, rechteckige Textmarker, Abdeckungen und Zuschneiden zeichnen ihre Größenänderungsgriffe über die gemeinsame UI-Komponente `SelectionGrips`:

- Ecken: weißer Kreis, 10 pt Durchmesser.
- Oben/unten: weiße Kapsel, 22 × 8 pt.
- Links/rechts: weiße Kapsel, 8 × 22 pt.
- Akzentkontur: 1,5 pt; leichter Schatten.
- Trefferfläche: zusätzlich 7 pt um jede Form. Überlappende Flächen wählen den nächstgelegenen Griffmittelpunkt.

Die Editorprojektion zeichnet die Griffe in Ansichtspunkten. Zoomen und unterschiedliche X-/Y-Skalierung des Bildes verändern ihre Größe und Proportionen nicht. Die Trefferprüfung und Resize-Cursor verwenden dieselben Rechtecke. Nicht sichtbare Objektgriffe außerhalb eines bestätigten Zuschnitts bleiben inaktiv. Textbreitengriffe verwenden die senkrechte Kapsel; Pfeil-Endpunkte und Callout-Ziele den runden Stil.

Ziehen berücksichtigt den tatsächlichen Greifpunkt und lässt das Objekt nicht zur Griffmitte springen. Bestehende Resize-/Umschalt-/Undo-Regeln bleiben erhalten. ⌥ im Zuschneidewerkzeug beginnt ausdrücklich eine neue Auswahl, auch innerhalb einer Grifffläche. Die Griffe gehören nur zur Ansicht und erscheinen nicht im PNG.

## Nachweise

- `./scripts/build.sh`: signierter macOS-Build erfolgreich.
- `./scripts/test.sh`: 82 Domain-Tests erfolgreich.
- `./scripts/test-canvas.sh`: Bisherige Formen-/Callout-/Text-/Zuschnitt-/Zoomprüfungen bestanden. `SelectionGripChecks` misst zusätzlich die tatsächlichen weißen Griffpixel im AppKit-Canvas bei 50/100/400 % und bei einer freien Bildauflösung von 960 × 240 statt 640 × 480. Kreisform, Kapselausrichtung und konstante Ansichtspunktmaße stimmen.
- Native Mausereignisse treffen die erweiterten Flächen außerhalb des bisherigen Radius in allen acht Richtungen, für Formen und Zuschnitt. Kleine Rahmen wählen trotz überlappender Trefferflächen den nächsten Griff. Form-Resize benötigt einen Undo-Schritt; gerenderte PNG-Pixel bleiben nach Undo unverändert.
- `./scripts/test-capture.sh`: Aufnahmeauswahl mit derselben Zeichenkomponente bestanden, einschließlich sichtbarer Griffpixel, acht vergrößerter Trefferflächen, kleiner Rahmen und bestehender Standbild-/Retina-/Abbruchregressionen.
- Tatsächlich gerenderte synthetische Form- und Zuschnittansichten wurden visuell geprüft. Es wurde keine laufende Nutzer-App bedient und keine Nutzeraufnahme als Fixture übernommen.

## Noch manuell

Greifgefühl, Cursorfeedback und Kontrast auf den verwendeten Bildern/Displays persönlich prüfen. Die übergreifende Hardware-/Releaseabnahme Q01–Q04 bleibt offen.

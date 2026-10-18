# Sanfter Wechsel erkannter Fenster

Stand: 14. Oktober 2026. Implementiert und auf macOS 27 mit synthetischen Fenstern geprüft.

## Verhalten

- Rahmen und heller Ausschnitt bewegen und vergrößern/verkleinern sich gemeinsam in **180 ms**, mit kubischem Ease-out ohne Überschwingen. Keine Wartezeit vor dem Start.
- Bei einem weiteren Fensterwechsel beginnt der neue Übergang am aktuellen Zwischenstand. Mausbewegungen innerhalb desselben Fensters starten ihn nicht erneut.
- Verlässt die Maus alle Fenster, verschwindet die Markierung über **100 ms**. Ein unmittelbar folgendes Fenster übernimmt den noch sichtbaren Zwischenstand. Zwischen Displays wird lokal überblendet, kein Rahmen durch den gesamten Desktop gezogen.
- Hit-Testing und Zielrechteck ändern sich sofort. Klicken während des Gleitens übernimmt ausschließlich das tatsächlich erkannte Fenster. Bestätigter Rahmen, freie Ziehauswahl und Größenänderungen werden ohne Nachlauf angezeigt.
- „Bewegung reduzieren“ überspringt den Übergang. Abbrechen friert den sichtbaren Zwischenstand für das bestehende Ausblenden ein.

## Umsetzung

`CaptureHoverHighlight` in `ScreenshotSelector.swift` trennt Ziel- von Darstellungsgeometrie. Ein öffentlicher, an die jeweilige `NSView` gebundener `CADisplayLink` zeichnet nur die Auswahlhilfen synchron zum Display neu. Bei Stillstand, Bestätigung, Abbruch und Entfernen der Ansicht wird der Link invalidiert; sein Ziel hält die Ansicht nur schwach. Das eingefrorene Bild wird weder neu berechnet noch transformiert. SCK-Quellen, Fensterreihenfolge, Koordinatenumrechnung, TCC und Sandbox bleiben gleich. Keine neue Abhängigkeit.

## Nachweise

- `./scripts/build.sh -derivedDataPath "$PWD/build/LocalizationBuild"`: erfolgreicher signierter App-Build.
- `./scripts/test.sh`: 88 Domain-Tests bestanden.
- `./scripts/test-capture.sh`: bestehende Standbild-/Retina-/Deckkraft-/Griff-/Klick-/Drag-/Bestätigungsprüfungen bestanden. Neue Prüfungen messen Zwischenposition und -größe, Abbremsen, Abschluss nach 180 ms, schnelle Richtungswechsel ohne Sprung/Überschwingen, unveränderte Animation bei Bewegung innerhalb eines Fensters, kurze Lücken, reduzierte Bewegung und Displaygrenzen. Produktions-View-Handler bestätigen die exakte Klickauswahl während einer Animation und sofortiges freies Aufziehen. Ein geschlossener View wird trotz laufender Animation freigegeben; Abbruch hält die sichtbare Position fest.
- Die separate Prüf-App zeigt über **UI QA → Window Hover Motion Preview** drei synthetische Fenster. Darstellung, heller Ausschnitt und Rahmen wurden beim Wechsel zwischen großen und kleinen Zielen visuell geprüft. Aufbau: `./scripts/build-english-ui-fixture.sh`; Voraussetzung ist der obige Prüfbuild. Es werden keine privaten Bildschirminhalte aufgenommen und keine Projekte der laufenden Nutzer-App verändert.

## Verbleibende Geräteabnahme

Persönliches Bewegungsgefühl beim freien Darüberfahren und Bildrate unter Last auf 60-/120-Hz-Geräten prüfen. macOS 26, reale Mehrdisplay-/Space-/Stage-Manager-Wechsel und ein echter Umschaltvorgang der macOS-Einstellung „Bewegung reduzieren“ bleiben Teil der Hardwareabnahme. Die automatisierte Prüfung des deaktivierten Animationspfads und synthetische Darstellung ersetzen diese Abnahme nicht.

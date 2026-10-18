# Screenshot-Aufnahme und Abnahme

Stand: 14. Oktober 2026, Standbild-Auswahl mit klarerer Abdunklung, größerem Cursor, kurzen Übergängen und besser erkennbaren Griffen nach Nutzerreferenz.

## Aktueller Ablauf

**Neue Aufnahme** in Symbolleiste, App-Menü, Statusmenü und über ⇧⌘2 verwendet dieselbe automatische Fenster- und Bereichsauswahl. Bei bestehender Freigabe erscheint kein vorgeschalteter Einrichtungsdialog.

1. Nach optionalem Vorlauf werden eigene Fenster ausgeblendet. ScreenCaptureKit erfasst pro Display ein unveränderliches Bild im Arbeitsspeicher.
2. Deckende, nicht verschiebbare Auswahlpanels zeigen diese Bilder. Die Auswahlfläche bleibt auch innerhalb eines markierten Fensters vollständig deckend und nimmt Mausaktionen entgegen.
3. Hover erkennt Fenster anhand der beim Start ermittelten Geometrie und Z-Reihenfolge. Klicken markiert ein Fenster; Ziehen markiert einen freien Bereich.
4. Ziehen innerhalb einer bereits gewählten Fläche startet eine neue freie Auswahl. Ziehen an der Rahmenkante verschiebt nur den Auswahlrahmen; acht Griffe ändern dessen Größe. Die Loslassposition unterscheidet Klick und Ziehen auch ohne Zwischenereignis. Hover überschreibt keine laufende Bereichsgeste.
5. **Aufnehmen** oder Enter schneidet die Auswahl aus denselben eingefrorenen Pixeln aus und öffnet sie als automatisch gesichertes Projekt im Editor. Kein zweiter Live-Screenshot. **Neu auswählen** verwendet weiterhin dasselbe Standbild; Escape oder **Abbrechen** verwirft die Sitzung ohne neues Projekt.

Die Fensterwahl übernimmt den sichtbaren rechteckigen Ausschnitt des Standbilds, einschließlich sichtbarer Überdeckungen. Es gibt in diesem Ablauf keinen nachträglichen unabhängigen Fensterfilter und keine Rekonstruktion verdeckter Inhalte. Fremde Apps werden nicht angehalten; ihre weitere Darstellung und Eingaben liegen während der Auswahl hinter den deckenden Panels.

Das Kreuz ist ein einzelner 40-Punkte-NSCursor mit segmentierten orangefarbenen Armen, schwarzer/weißer Kontur, Zielring und Mittelpunkt. Der Hotspot liegt genau bei (20,20). Die Fläche behält den Aufnahmecursor; Rahmenkanten und Griffe verwenden Hand- bzw. Resize-Cursor, nur die Bestätigungsleiste den normalen Pfeil. Cursor-Rechtecke und cursorUpdate verwenden dieselbe Zuordnung. Der tatsächliche Systemcursor ist in den App-Screenshots des UI-Werkzeugs nicht enthalten; eine visuelle Abnahme seiner Form wird nicht behauptet.

## Auswahlgriffe (14. Oktober)

Aufnahme und Editor nutzen dieselbe Komponente `SelectionGrips`. Die vier Ecken sind weiße Kreise mit 10 pt Durchmesser. Oben/unten stehen 22 × 8 pt große weiße Kapseln; links/rechts sind sie vertikal gedreht. Akzentkontur (1,5 pt) und ein leichter Schatten halten sie auf hellen und dunklen Bildstellen erkennbar. Die Ausrichtung zeigt die jeweilige Ziehrichtung. Die Trefferfläche reicht zusätzlich 7 pt über die gezeichnete Form hinaus. Bei kleinen Auswahlen mit überlappenden Trefferflächen entscheidet der Abstand zum Griffmittelpunkt.

`./scripts/test-capture.sh` prüft tatsächliche weiße Griffpixel und die verlängerten Seiten-Griffe im gerenderten AppKit-Auswahlview. Native Mausereignisse treffen alle acht vergrößerten Griffflächen einschließlich Positionen außerhalb der früheren 14-pt-Trefferfläche. Kleine überlappende Auswahlen verwenden den nächsten Griff; alle bisherigen Aufnahme-/Koordinatenprüfungen bestehen. Eine synthetische Retina-Vorschau wurde visuell geprüft. Die persönliche Bedienprüfung übernimmt weiterhin der Nutzer.

## Ursache und Korrektur

Die frühere Auswahl schnitt ein vollständig transparentes Loch über dem markierten Fenster aus. isMovable = false und NSView-Hit-Testing allein schlossen das Durchreichen auf der Ebene des Window Servers nicht aus. Jetzt sind Panel und View opaque, das Panel nimmt Mausaktionen an, und die View zeichnet zuerst einen deckenden Hintergrund und anschließend das Standbild. Der optische Ausschnitt verändert ausschließlich die Abdunklung; es entsteht kein transparentes Loch.

Die tatsächliche Aufnahme lag früher nach dem Bestätigen. Jetzt liegt sie vor der Auswahl. Dadurch stimmen Vorschau und Editor auch bei inzwischen veränderten Fensterinhalten überein. Die Cursoroption übernimmt den Mauszeiger beim Erstellen des Standbilds.

## Nachweise für diesen Stand

- Normaler Xcode-Debugbuild mit bestehender Apple-Development-Signierung erfolgreich. Keine neue App-Kopie oder TCC-Änderung.
- Erweiterte Offscreen-AppKit-Tests erfolgreich: deckende Pixel über die gesamte Fläche, auch im markierten Fenster und bei transparenten synthetischen Quellpixeln; aufrechte Darstellung des asymmetrischen Standbilds; unveränderliche Retina-Ausschnitte trotz geänderter synthetischer Quelle; unbekannte Displays und veränderte Geometrie abgewiesen; Cursorzuordnung auf Fläche, Kante und Leiste. Dazu Klick/Drag, fehlendes Zwischenereignis, Hover-Isolation, erneute freie Auswahl, Live-Vorschau, Verschieben/Resize, native Schaltflächen, Enter und Abbruch. Diese Tests rufen View-Handler auf und ersetzen keinen Hardware-Eingabetest.
- Laufender Standbild-Build: Neue Aufnahme zeigt die eingefrorene Desktopansicht. Fenster per Klick markiert (3024 × 1750 Pixel). Ziehen über dessen Titelleiste erzeugt einen freien Bereich mit 200 × 138 Pixeln. Enter öffnete diesen Ausschnitt um 16:24:47 im Editor, dort „Alle Änderungen gesichert“. Nach Neustart steht er in der Bibliothek.
- Abschließender Build mit cursorUpdate: ⇧⌘2 startet die Auswahl. Fensterklick, danach Ziehen über der fremden Titelleiste erzeugt 280 × 170 Pixel. Escape stellt die Bibliothek mit unverändert 14 Projekten wieder her.
- Die unveränderten Domain-Tests waren vor dieser Änderung mit 26 erfolgreichen Tests geprüft, unter anderem Koordinaten, Retina-Rundung, Drag-Schwelle, Verschieben und acht Resize-Griffe. Neue Standbild- und Cropping-Logik liegt im AppKit-Testharness.

## Koordinaten, Rechte und Lebenszyklus

ScreenCaptureKit liefert aufnehmbare Fenster einschließlich Hintergrundfenstern (`onScreenWindowsOnly: false`). `CGWindowListCopyWindowInfo` mit `optionOnScreenOnly` bestimmt die tatsächlich vorhandenen Desktopfenster, aktuelle Geometrie und Reihenfolge von vorn nach hinten. Nur die Schnittmenge wird zum Auswahlkandidaten; am Mauspunkt gewinnt das vorderste Fenster. Es wird nicht nach aktiver Anwendung gefiltert. Eigene, minimierte und nicht aufnehmbare Fenster entfallen. Fensterinformationen verwenden Quartz-Koordinaten, die UI AppKit-Koordinaten. Ein Ausschnitt bleibt auf seinem Startdisplay und wird an dessen Grenzen begrenzt. Die Skalierung stammt aus den eingefrorenen Bildpixeln; Crop-Grenzen werden nach außen auf volle Pixel gerundet. Die Display-ID und Geometrie müssen zum Standbild passen. Displaygeometrieänderungen brechen die Auswahl ab. Die Bilder mehrerer Displays werden nacheinander erfasst, nicht als atomarer gemeinsamer Zeitpunkt.

Eigene Hauptfenster und Paletten bleiben während der Auswahl ausgeblendet. Fokusbeobachter geben den Fokus an das Auswahlpanel zurück. Nach Abschluss werden die Beobachter entfernt und vorher sichtbare Fenster wiederhergestellt. Panels und Bilder werden mit der Sitzung freigegeben. Nur der bestätigte Ausschnitt gelangt in das Projekt; es wird kein zusätzliches vollständiges Desktopbild gespeichert.

Die Berechtigungsprüfung bleibt bestehen: Erklärung vor der ausdrücklichen Systemanfrage, bei fehlender Freigabe Einstellungen-Link und erneute Prüfung. Kein Ändern von TCC-Einstellungen. Vorlauf und Vorbereitung bleiben abbrechbar. ScreenCaptureKit-Fehler erscheinen in den Aufnahmeoptionen; ein bereits bearbeitetes Bild bleibt erhalten.

## Übergang in den Screenshot-Modus: kurzer Zoom (13. Oktober 2026)

Nach dem Nutzerhinweis auf ein kurzes Flackern bzw. Zoomen wird die automatische Ein-/Ausblendanimation der Auswahlpanels ausdrücklich mit `animationBehavior = .none` abgeschaltet. Die zusätzliche ausdrückliche App-Aktivierung vor dem Einblenden entfällt. Die Panels können sich mit `canJoinAllApplications` dem aktuellen Stage-Manager-Fenstersatz anschließen; Space- und Vollbildunterstützung bleiben gesetzt. Der erste Hover-Zustand entsteht vor dem Einblenden. Ordering und Zeichnen werden in einer gemeinsamen `NSAnimationContext`-Gruppe mit Dauer 0 und ohne implizite Animation eingereicht. Öffentliche API: [NSWindow.animationBehavior](https://developer.apple.com/documentation/appkit/nswindow/animationbehavior-swift.property).

Die Aufnahmeauswahl-Tests prüfen zusätzlich die ausgeschaltete Fensteranimation, den nicht aktivierenden Panelstil, Tastaturfokusfähigkeit und die Collection-Behaviors. Regulärer signierter Xcode-Build und 74 Domain-Tests bestanden. Ein kleiner synthetischer Paneltest am Window Server bestätigt erreichbaren Tastaturfokus und Zeichnen im folgenden Runloop; es werden keine Bildschirmbilder aufgenommen. AppKit kann beim Anfordern des Tastaturfokus weiterhin die App aktivieren. Deshalb wird aus diesen technischen Prüfungen keine visuelle Abnahme des Zooms oder eines Space-/Stage-Manager-Wechsels abgeleitet.

Noch manuell prüfen: mehrfacher Einstieg aus App, Statusmenü und globalem Kürzel, auch über einer Vollbild-App bzw. mit Stage Manager; Desktop bleibt an derselben Position und Größe, nur die vorgesehene Abdunklung erscheint. Anschließend freie Auswahl, Enter und Escape prüfen. Mehrdisplay-Hardware bleibt separat offen.

## Verbleibende manuelle Abnahme

| Fall | Stand |
| --- | --- |
| Gemeinsame Auswahl, Fensterklick, freie Auswahl über fremder Titelleiste | Im laufenden Standbild-Build geprüft |
| Freien Standbild-Ausschnitt im Editor öffnen und sichern | 200 × 138 Pixel, auch nach Neustart in der Bibliothek |
| Escape nach erneuter Auswahl | Im abschließenden Build geprüft, kein weiteres Projekt |
| Alle acht Griffe / Rahmenverschieben | Handler- und Geometrietests; frühere UI-Abnahme vor der Standbildänderung |
| Unveränderten vollständigen Fensterrahmen bestätigen | Derselbe Standbild-Crop-Pfad; separate UI-Abnahme offen |
| Ganzer Bildschirm / mehrere Displays / macOS 26 | Auswahl- und Koordinatentests; reale Hardware offen |
| Sichtbare Cursorform | Zuordnung getestet; manueller visueller Test offen |
| Countdown-Abbruch / Rechteentzug | Manueller Test offen |
| Physische globale Kürzel / Statusmenü | Nutzer testet Kürzel später; Statusmenü separat offen |

## Xcode und Signierung

Start aus Xcode, Scheme SnagForge, My Mac. Das Buildskript verwendet den normalen DerivedData-Ordner und erzwingt keine ad-hoc-Signatur. Bundle-ID com.snagforge.app, Team 24C8L59PV7 und bestehende lokale Bibliothek bleiben erhalten. Details: XCODE-START.md.


## Snagit-Referenz und Überarbeitung (13. Oktober 2026)

Das bereitgestellte 18,7-Sekunden-Video wurde lokal in Einzelbildern ausgewertet. Sichtbar sind die helle Zielfläche, eine kräftige Abdunklung außerhalb, der kontrastreiche orangefarbene Kreuzcursor und die weiter bestehende Abdunklung nach dem Fensterklick. Diese Beobachtung erklärt nicht die technische Ursache des in Snaprivo gemeldeten Hintergrundfensterfehlers.

Umgesetzt:

- Breite ScreenCaptureKit-Fensterenumeration, anschließend Einschränkung auf die aktuelle Window-Server-Liste. Window-Server-Geometrie ersetzt möglicherweise ältere ScreenCaptureKit-Geometrie. Sichtbare Teile von Hintergrundfenstern bleiben Kandidaten; minimierte Fenster und andere Spaces aus der breiten Enumeration erscheinen dadurch nicht als zusätzliche Ziele.
- Gleichbleibend 42 % schwarze Abdunklung außerhalb der Zielfläche beim Darüberfahren, Zeichnen und Prüfen; die ausgewählten Pixel bleiben unverändert hell. Displays ohne Auswahl werden während der Prüfung ebenfalls abgedunkelt.
- Größerer dreifach konturierter orangefarbener Kreuzcursor mit Zielring und präzisem Mittelpunkt. Die bestehenden Cursor für Rahmenkante, Griffe und Bestätigungsleiste bleiben erhalten.
- Die eingefrorenen Bildpixel bleiben deckend und unbewegt. Eine separate, nicht hit-testbare Zeichenebene blendet Abdunklung, Rahmen und Hinweise mit 160 ms Ease-out ein/aus; bei reduzierter Bewegung 100 ms. Die Bestätigungsleiste blendet beim Abschluss mit aus. Kein Zoom und keine Fenster-Alpha-Animation. Der erste akzeptierte Abschluss sperrt weitere Eingaben; die Fortsetzung läuft erst nach dem Schließen der Panels weiter. Displaygeometrieänderungen schließen sofort.

Nachweise: `./scripts/test-capture.sh` und regulärer signierter `./scripts/build.sh` erfolgreich. Die synthetischen AppKit-Tests prüfen Hintergrund-/Vordergrundreihenfolge, sichtbaren Hintergrundbereich, Überdeckung, aktuelle Geometrie, eigene/nicht aufnehmbare/unsichtbare Fenster, hellen Ausschnitt, gleiche Abdunklung vor/nach Klick, unveränderte Standbildpixel bei ausgeblendeten Auswahlhilfen, Cursorgröße/Hotspot und Eingabesperre beim Abschluss. Die bestehenden Crop-, Klick-/Drag-, Griff-, Enter- und Abbruchprüfungen bestehen weiter.

Offen für die Nutzerprüfung: Der konkrete Hintergrundfensterfall mit echten Apps, die visuelle Cursorwirkung und das Gefühl der Übergänge, auch bei schnellem Enter/Escape und mit Stage Manager. Die Testdaten prüfen die Auswahlregeln; sie sind kein Nachweis, dass macOS im gemeldeten Fall alle benötigten Fenster liefert. Es wurden keine Nutzeraufnahmen in das Repository übernommen und keine Aufnahmeberechtigungen verändert. Die Prüfung der laufenden Oberfläche bleibt auf Wunsch beim Nutzer.

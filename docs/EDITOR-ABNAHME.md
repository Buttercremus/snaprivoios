# Editor-Abnahme

## Ergänzung: Eigenschaftenbereich und Übergabeaktionen (14. Oktober 2026)

Der feste Eigenschaftenbereich ist von 224 auf 260 pt verbreitert. Ein senkrechter Trenner nach PNG speichern gruppiert Teilen und Öffnen mit. Öffnen mit verwendet einen regulären Toolbar-Button mit Symbol über Text; die App-Auswahl bleibt ein natives NSMenu und wird bei jedem Öffnen aktualisiert. Build und 82 Domain-Tests bestanden. Die tatsächlichen Eigenschaften- und Toolbar-Komponenten wurden isoliert gerendert; persönliche Bedienprüfung durch den Nutzer bleibt separat. [Übergabeaktionen](TEILEN-ABNAHME.md).

## Aktuell: einheitliche Auswahlgriffe (14. Oktober 2026)

Aufnahmeauswahl, Formen, Callout-Rahmen und Zuschneiden verwenden dieselben runden Eckgriffe und länglichen Seitengriffe mit größeren Trefferflächen. Die Darstellung bleibt bei Zoom und freiem Bildseitenverhältnis unverzerrt. Native Pixel-/Interaktionsprüfungen und Exportregressionen bestehen. [Regeln und Nachweise](AUSWAHLGRIFFE-ABNAHME.md).

## Vorheriger Schritt: Schrift und Callout-Ziel (E05)

[Regeln und Nachweise](TEXT-CALLOUT-ABNAHME.md).

## Vorheriger Schritt: Duplikate und Ebenen (E04)

Siehe [Objekt-Abnahme](OBJEKTE-ABNAHME.md).

## Vorheriger Schritt: Bildauflösung ändern (E03)

Am 13. Oktober 2026 umgesetzt: Pixelmaße, Seitenverhältnissperre, gemeinsame Skalierung von Bild und bearbeitbaren Objekten, Undo/Redo, Autosave und PNG-/Clipboard-/Thumbnail-Ausgabe. 53 Domain-Tests sowie native Resize- und bisherige Canvas-/Renderer-/Autosave-Prüfungen erfolgreich. Im signierten Build Dialog, gekoppelte/freie Maße, Abbruch, Undo/Redo, PNG und Wiederöffnen nach Neustart geprüft. [Vollständige Regeln und Nachweise](BILDAUFLOESUNG-ABNAHME.md).


## Aktuelle Ergänzung: größere Werkzeuge und Einstellungen

Vor E03 ist U01 umgesetzt: zentrale Palette mit drei gespeicherten Größen, damalige Vorgabe Groß (24-pt-Symbole, 64-pt-Werkzeughöhe; seit 14.10.2026 Standard bei neuer Installation), native Einstellungsbereiche und konfigurierbare Aufnahmekürzel. Werkzeugwechsel behalten je eingestellter Größe dieselbe Canvas-Geometrie. Im laufenden signierten Build alle Größen gewählt; nach Neustart die gespeicherte Wahl und die große Palette am synthetischen Zuschnittprojekt geprüft. [Vollständige Einstellungsabnahme und offene Hardwarefälle](EINSTELLUNGEN-ABNAHME.md). Die folgenden älteren Protokolle beschreiben die damaligen Größen.

## Vorheriger Schritt: Zuschneiden

E02 ist am 12. Oktober 2026 umgesetzt. Nicht destruktiver Zuschnitt mit Live-Rahmen, acht Griffen, Verschieben und ganzzahligen Pixelwerten; Bestätigen ergibt einen Undo-Schritt, Abbrechen lässt den Dokumentstand unverändert. Original und Objektkoordinaten bleiben erhalten. Projektformat 2 liest Version 1. 47 Domain-Tests sowie native Canvas-/Renderer-/Autosave-Prüfungen einschließlich PNG-/Clipboard-Vergleich bestehen. Im signierten Build: synthetisches 4K-Bild auf 2000 × 1200 zugeschnitten, Pfeil/Text ergänzt, Original wiederhergestellt, Undo/Redo, Export und Wiederöffnen nach App-Neustart geprüft. Regeln, Ergebnisse und offene Releasefälle: [Zuschnitt-Abnahme](ZUSCHNITT-ABNAHME.md).

## Vorheriger Schritt: Zoom, Schwenken und 100 %

E01 ist am 12. Oktober 2026 umgesetzt und am synthetischen 4K-Bild geprüft. Sichtbare Zoomstufen, 100 % unter Berücksichtigung der Retina-Skalierung, Anpassen, Scrollen und Leertaste/Ziehen verwenden eine gemeinsame Projektion. Ansichtsänderungen erzeugen keine Dokumentrevision und keine Undo-Schritte; PNG bleibt in Originalauflösung. 40 Domain-Tests und die nativen Canvas-/Zoom-Prüfungen bestehen. Bedienprüfung im signierten Build: Texteingabe nach Zoom/Scrollen, Wortauswahl und ⌘Z, Formgriffe, Pfeilspitze, PNG und Wiederöffnen. Einzelheiten und offene Hardwareprüfungen: [Zoom-Abnahme](ZOOM-ABNAHME.md).

## Vorheriger Schritt: Größenänderungsgriffe und Umschalttaste

- Formen und Callouts zeigen acht sichtbare, 7 pt große Griffe mit 16 pt Trefferfläche und nativen Resize-Cursorn. Griffe werden vor Objektverschiebung und Texteingabe erkannt, auch direkt außerhalb der Bildkante. Die gegenüberliegende Ecke/Kante bleibt verankert; der Zeigerversatz beim Anfassen wird erhalten. Minimum verhindert umgekehrte Geometrie. Escape verwirft die Vorschau; Klicken ohne Änderung erzeugt keinen Undo-Schritt.
- Umschalt während des Aufziehens: gleiche Breite/Höhe für Formen. Beim Resize: Quadrat/Kreis, bei anderen Formen und Callouts ursprüngliche Proportionen, sofern der Text Platz findet. Bei Pfeilen werden neue Geometrie und bestehende Endpunkte auf 45°-Schritte gesetzt. flagsChanged aktualisiert die Vorschau auch bei stehender Maus. Loslassen gibt die freie Bewegung wieder frei. Ein abgeschlossener Drag ist ein Undo-Schritt.
- Callout-Resize ändert Textbreite und optionale Mindesthöhe, mit unveränderter Schrift und Inhalt. TextKit bricht neu um; der Rahmen wird nie kleiner als sein Text. Beim oberen Griff bleibt die untere Kante auch bei zusätzlichem Umbruch fest. `textHeight` ist optional in Format 1, wird validiert, gespeichert und vom gemeinsamen Renderer für Canvas, PNG, Clipboard und Thumbnail verwendet.
- Regulär signierter Xcode-Build erfolgreich, 34 Domain-Tests bestanden. Neue reine Geometrieprüfungen: vier Ziehrichtungen, Winkel/Länge, alle acht Anker, Minimum ohne Inversion, proportionales Verkleinern und Nullbewegung. Projekt-Roundtrip enthält Callout-Breite/-Höhe, Legacy-Dokumente ohne Höhe und Ablehnung ungültiger Höhen.
- Canvas-Prüfungen mit echten NSEvents auf synthetischem Bild: alle acht Griffe an rückwärts gezeichneten Formen, Vorschau vor mouseUp, Versatz ohne Sprung, Escape/Nullbewegung, Shift-Drücken/-Loslassen ohne neue Mausbewegung, Kreise/Quadrate in vier Richtungen, Pfeilerstellung und Anfangsgriff mit Winkelraster. Form- und Callout-Resize: Undo/Redo, neue Store-Instanz und tatsächliche PNG-Pixel geprüft; Callout mit engem Umbruch bleibt im Rahmen und am gegenüberliegenden Anker. Renderer-Prüfungen decken explizite Höhe, Textüberlauf und Thumbnail ab. Bestehende Autosave-, Inline-Text- und Exportprüfungen bestehen.
- Im laufenden App-Sandbox-Build am synthetischen Projekt „Werkzeugtest“: acht Griffe sichtbar, abgerundetes Rechteck am rechten unteren Griff verändert, ⌘Z und ⇧⌘Z geprüft. Callout direkt angelegt, über linken Griff verbreitert (zwei Zeilen werden eine), über unteren Griff verkürzt; Schriftgröße bleibt 14. Teständerungen anschließend zurückgenommen und gesichert; Bibliothek bestätigt wieder drei ursprüngliche Markierungen. Ursprüngliches Nutzerprojekt wieder geöffnet, keine Nutzeraufnahme bearbeitet.
- Offen: vollständige VoiceOver-/Tastaturbedienung der Griffe, reale Umschalttasten-Geste im laufenden Fenster (automatisiert über NSEvents geprüft), Mindestfenstergröße und Mehrdisplaybetrieb. Zoom und Zuschneiden sind inzwischen umgesetzt (siehe oben); Änderung der Bildauflösung folgt im Arbeitsplan. Callout-Zeiger ist weiterhin fest.

## Vorheriger Schritt: Formauswahl, Stilvorlagen und Rand

- „Formen“ in der oberen Leiste öffnet sechs sichtbare Varianten im festen Inspektor: Rechteck, abgerundetes Rechteck, Ellipse, Dreieck, Raute und Stern. Auswahl wandelt bestehende Formen mit unveränderter ID, Position, Größe und Farben um. Neue Formen übernehmen die gewählten Vorgaben.
- Sechs feste Stilvorlagen setzen Randfarbe, Stärke, durchgezogenen Rand und Füllung gemeinsam als einen Undo-Schritt. Acht direkte Farbfelder ergänzen den nativen Farbdialog für Rand/Füllung sowie Pfeil/Text. Rand und Füllung sind unabhängig abschaltbar. Linienmuster: Voll, Strich und Punkt; Breite weiterhin per Schieberegler und Zahlenfeld. Der Eigenschaftenbereich scrollt; die Bildfläche bleibt unverändert.
- Regulär signierter Xcode-Build erfolgreich; 29 Domain-Tests bestanden. Persistenz-Roundtrip enthält neue Formtypen, alle Randmuster und abgeschalteten Rand. Legacy-Projekte ohne `stroke` behalten ihren durchgezogenen Rand, unbekannte Linienmuster werden abgelehnt. Produktionsrenderer prüft tatsächliche PNG-Pixel: Linien und Lücken, getrennte Füllung, kein Rest bei abgeschaltetem Rand/Füllung, Dreieck/Raute/Stern, umgekehrte Ziehrichtung und Thumbnails. Canvas prüft die neuen Formen schon vor mouseUp und ein Undo pro Geste. Autosave prüft Formumwandlung, Stilvorlage als einen Undo-Schritt und gespeicherte Geometrie/Randeigenschaften nach neuem Store.
- Im laufenden App-Sandbox-Build am synthetischen Projekt „Werkzeugtest“: Dreieck mit gelber Markierung gezeichnet, Rand auf Strich und 2 px gestellt, in Stern umgewandelt, Rand per Farbfeld weiß und gepunktet gesetzt. Rand abgeschaltet: Füllung bleibt sichtbar. Blaue Stilvorlage angewandt; ein Rückgängig-Schritt stellt den kompletten vorherigen Zustand wieder her, Wiederholen die Vorlage. Alle acht Teständerungen anschließend mit ⌘Z zurückgenommen und mit ⌘S gesichert; die drei ursprünglichen Testmarkierungen bleiben erhalten. Keine Nutzeraufnahme verändert.
- Offen: eigene gespeicherte Stilvorlagen, Schatten, frei editierbare Polygonpunkte; Größenänderungsgriffe sind inzwischen ergänzt (siehe oben). Vollständige VoiceOver-/Tastaturabnahme, nativer Farbdialog und Mindestfenstergröße bleiben separat abzunehmen. Der PNG-Export verwendet geprüfte gemeinsame Zeichenfunktionen; der native Save-Dialog wurde in diesem Schritt nicht erneut getestet.

Stand: 12. Oktober 2026. Sandboxed lokaler Debug-Build, synthetische Bilder.

## Vorheriger Schritt: Pfeil-Endpunkte und zentrierte Werkzeuge

- Normale Autosave-Meldungen entfallen vollständig. Nur Speicherfehler zeigen Meldung, Wiederholung und Sichern als Kopie. Autosave und die Sicherung beim Beenden bleiben aktiv.
- Die Werkzeugpalette steht mittig über der Canvas-Spalte; der rechte Inspektor wird bei der Zentrierung nicht mitgerechnet. Die Palette bleibt kompakt und kann bei knapper Breite horizontal scrollen.
- Runde, weiß gefüllte Griffe markieren Anfang und Spitze eines ausgewählten Pfeils. Ziehen ändert nur diesen Endpunkt, ohne beim Greifen neben der Griffmitte zu springen. Auch ein unselektierter Endpunkt ist direkt greifbar. Ziehen am Schaft verschiebt weiterhin das ganze Objekt. Die Geometrie wird bei jeder Mausbewegung angezeigt; Loslassen ergibt einen Undo-Schritt, Escape verwirft die Geste.
- Regulär signierter Xcode-Build und 28 Domain-Tests erfolgreich. `test-canvas.sh` prüft den Produktions-Canvas: Live-Pixel beim Drehen, unveränderter Gegenpunkt, versetztes Greifen, direkte Auswahl, Schaftverschiebung, Abbruch, Klick ohne Bewegung, Undo/Redo, Save/Reload und tatsächliche PNG-Pixel an neuer und alter Pfeilposition. Bestehende Prüfungen für Formen, Füllung und native Textauswahl/Undo bestehen ebenfalls.
- Im laufenden App-Sandbox-Build am synthetischen Projekt „Werkzeugtest“: Pfeil von (850,1250) nach (1450,1250) gezeichnet (2×-Screenshotkoordinaten), Spitze nach (1580,1120) gezogen; Anfang bleibt bei (850,1250). Ein Rückgängig-Schritt stellt den horizontalen Pfeil her, Wiederholen die gedrehte Fassung. Anschließend den unselektierten Anfang nach (1000,1320) gezogen; Spitze bleibt stehen. Schaftverschiebung verschiebt beide Endpunkte gleich; ⌘Z nimmt sie zurück. Palette sichtbar mittig über der Bildfläche, keine Speicherstatuszeile. Alle vier Testgesten zurückgenommen und mit ⌘S gesichert; die drei vorherigen Markierungen des Testprojekts bleiben erhalten. Nutzeraufnahmen wurden nicht bearbeitet.
- Offen bleiben Tastatur-/VoiceOver-Bedienung der Endpunkte; Winkelraster und Formgriffe sind inzwischen ergänzt (siehe oben). Mindestfensterbreite und Mehrdisplaybetrieb sind noch separat abzunehmen.

Stand: 12. Oktober 2026. Sandboxed lokaler Debug-Build, synthetische Bilder.

## Vorheriger Schritt: Schieberegler, Füllungen und abgerundete Rechtecke

- Die kompakte Werkzeugleiste bleibt oben sichtbar. Die bisherige 36-pt-Eigenschaftszeile ist durch einen festen 224-pt-Eigenschaftenbereich rechts ersetzt. Werkzeug- und Auswahlwechsel verändern die Größe/Position des Canvas nicht; der Inspektor scrollt bei geringer Fensterhöhe vertikal.
- Pfeil-/Linienstärke, Schriftgröße und Unschärferadius: native Slider plus direkt eingebbare, begrenzte Zahlenwerte. Rechteck/Ellipse/Callout: Füllung an/aus, getrennte Füllfarbe und Deckkraft; Rechteck zusätzlich Eckenradius. Der Callout-Zeiger ist Teil einer gemeinsamen Kontur, damit halbtransparente Füllungen keine Naht oder doppelte Deckkraft am Übergang erzeugen.
- Slider aktualisieren echte Objekte und Autosave während der Bewegung, fassen den gesamten Drag aber als einen Undo-Schritt zusammen. Bei laufender Texteingabe bleiben Stiländerungen Teil der Textsitzung. `fill` und `cornerRadius` sind optionale Ergänzungen von Format 1; alte Rechtecke/Ellipsen bleiben ungefüllt, alte Callouts weiß.
- Regulär signierter Xcode-Build erfolgreich; 28 Domain-Tests bestanden. Zusätzliche Prüfungen: vollständiger Stil-Roundtrip, Legacy-Dokumente ohne neue Felder, ungültige Farb-/Deckkraft-/Radiuswerte, Autosave während eines Slider-Drags, ein Undo für mehrere Zwischenwerte, Redo, Neustart und erneute Bearbeitung, Stiländerung während Inline-Text. Canvas-Prüfung bestätigt Füllung und Rundung bereits vor mouseUp sowie laufende Deckkraftänderung und Undo. Renderer prüft tatsächliche PNG-Samples einschließlich halbtransparenter Füllung, unveränderter Konturdeckkraft, deaktivierter Füllung, Rundung, Callout-Zeiger und Thumbnail.
- Im laufenden App-Sandbox-Build eigenes synthetisches Projekt „Werkzeugtest“ importiert: weiß gefülltes Rechteck mit Radius 16 px gezeichnet, Fülldeckkraft per Maus von 100 auf 48 % verändert, mit einem Undo auf 100 % und mit Redo auf 48 % gesetzt. Gefüllte Ellipse ergänzt. Text direkt im Bild eingegeben; Schriftgröße per Zahlenfeld 16 px, per Slider 33 px, ein Undo wieder 16 px. Die Bildkanten blieben beim Wechsel zwischen Form/Text/Auswahl unverändert (Oberkante 422, Unterkante 1405 bei 2×).
- Kopieren meldet „Bild kopiert“. Nativer Save-Dialog schreibt `build/RendererTests/Werkzeugtest-Export.png`; Datei geprüft: 240 × 160 px, halbtransparente gefüllte Formen, Rundung, Text, keine Auswahlgriffe. App regulär beendet und denselben Xcode-Build gestartet: Bibliotheksprojekt mit drei Markierungen wieder geöffnet. Rechteck bleibt auswählbar, Füllung aktiv, Deckkraft 48 %, Radius 16 px. Bestehende Nutzerprojekte wurden nicht bearbeitet.
- Noch offen: vollständige VoiceOver-/Tastaturabnahme aller Regler, Mindestfenstergröße, ColorPicker-Farbpanel (im UI-Automationstest nicht sichtbar erreicht), Einsetzen des PNG in Drittanbieter-Apps und Performance bei großen Dokumenten. Farbwerte, Komposition und Speicherung sind im Produktionsmodell/Renderer geprüft; das ersetzt keinen vollständigen Farbdialog-Test.

Stand: 12. Oktober 2026. Sandboxed lokaler Debug-Build, synthetische Bilder.

## Vorheriger Schritt: Kompakte Leiste, ruhiger Canvas und Textauswahl

- Werkzeugbuttons sind kompakter (54 × 42 pt, Symbole 16 pt). Die Glasfläche endet hinter den Werkzeugen. Die Eigenschaften belegen in jedem Zustand genau 36 pt, auch bei Auswahl ohne Objekt. Der Bedienhinweis behält ebenfalls seine Höhe. Bei knapper Breite scrollen Eigenschaften horizontal, statt die Bildfläche nach unten zu verschieben.
- Im laufenden signierten Build am synthetischen Projekt „fixture“: Auswahl → Callout → Text gewechselt. Die Bildkanten blieben an derselben Position (Screenshot-Oberkante 502, Unterkante 1405 bei 2×-Darstellung). Textfeld aufgezogen, „Hallo Welt“ direkt eingegeben und „Hallo“ per Doppelklick markiert. Ersetzen und Text-Undo über das Menü beobachtet. Alle Teständerungen anschließend als eine Dokumentsitzung rückgängig gemacht; ursprüngliches Rechteck erhalten.
- Textwerkzeug auf bestehendem Text bearbeitet dasselbe Objekt am Klickpunkt. Auswahl wählt zunächst das Objekt; Doppelklick bzw. erneuter Klick innen bearbeitet Text. Native NSTextView unterstützt Zeichen-/Wortauswahl, ⌘A, Ausschneiden/Kopieren/Einsetzen und eine eigene Undo-Historie je Sitzung. Nach Abschluss greift wieder die Dokumenthistorie. Escape beendet die Sitzung und behält die Eingabe.
- Klicken erzeugt mitwachsenden Text, Aufziehen eine feste Breite mit automatischem Umbruch. Zwei seitliche Griffe ändern die Breite mit Live-Vorschau und einem Undo-Schritt; der Rand dient zum Verschieben. TextKit arbeitet für Eingabe und PNG in denselben Bildpixeln, der Eingabe-View wird skaliert. Die Einfügemarke bleibt dünn. `textWidth` wird optional im bestehenden Format gespeichert; Projekte ohne das Feld bleiben lesbar.
- Xcode-Build erfolgreich, 23 Domain-Tests bestanden. Canvas-Prüfung: native Wortauswahl, Ersetzen, Text-Undo/Redo über Tastaturereignisse, keine Duplikate beim Bearbeiten, Escape erhält Inhalt, gezogene/umgebrochene Textbox, Live-Breitenänderung, Undo/Redo und Save/Reload. Renderer prüft zusätzlich mehrzeiligen PNG-Text innerhalb der gewählten Breite. Autosave-Prüfungen bestanden.
- Nach Entsperren App regulär beendet und denselben aktuellen Xcode-Build neu gestartet. Im synthetischen Projekt Textfeld aufgezogen und „Hallo Welt“ eingegeben; die dünne Einfügemarke ist sichtbar. Doppelklick markierte „Hallo“, Ersetzen ergab „Guten Welt“, ⌘Z stellte „Hallo Welt“ wieder her, ⇧⌘Z wiederholte „Guten Welt“. Ziehen markierte „uten“, ⌘A den gesamten Inhalt. Escape beendete die Eingabe; Dokument-⌘Z entfernte die komplette Sitzung in einem Schritt, Redo stellte sie wieder her. Abschließend zurückgenommen und mit ⌘S gesichert, ursprüngliches Rechteck unverändert. Der frühere erfolglose Tastaturversuch war die physische US-Tastenbezeichnung der UI-Automation: Auf dem aktiven deutschen Layout erzeugt deren `super+y` das logische ⌘Z, `super+shift+y` das logische ⇧⌘Z. Der Produktionscode verarbeitet die tatsächlichen Zeichen des Ereignisses. Kein weiterer Code-Fix erforderlich. IME, bidirektionale Texte, sehr lange Inhalte, Mindestbreite und VoiceOver bleiben separat abzunehmen. Keine Rich-Text-Formatierung einzelner Wörter; Farbe und Schriftgröße gelten für das ganze Textobjekt.

Stand: 12. Oktober 2026. Sandboxed lokaler Debug-Build, synthetisches Testbild.

## Vorheriger Schritt: Live-Zeichnen und Inline-Text

- Vektoren werden direkt im AppKit-Canvas bei jedem Mausereignis gezeichnet. Kein abbrechbarer Hintergrund-Renderauftrag für Pfeile, Formen oder Verschiebungen. Der bisherige 20-ms-Debounce entfällt. Nur Unschärfe nutzt einen einzelnen Hintergrundauftrag, dessen abgeschlossene Bilder angezeigt und anschließend mit der neuesten Geometrie aktualisiert werden. Der aktuelle Unschärferahmen folgt der Maus unmittelbar.
- Text und Callout werden am angeklickten Bildpunkt durch eine native NSTextView bearbeitet. Eingabe erscheint unmittelbar im Bild; Farbe und Schriftgröße passen sich an. Enter: neue Zeile, ⌘Enter: fertig. Escape beendet inzwischen mit Beibehaltung des Texts (siehe aktueller Schritt). Doppelklick auf bestehenden Text öffnet ihn an Ort und Stelle. Das Eingabefeld und Auswahlrahmen werden nicht exportiert.
- Textentwürfe sind während der Sitzung echte Dokumentobjekte und werden per Autosave gesichert. Eine History-Transaktion fasst die abgeschlossene Texteingabe als einen Dokument-Undo-Schritt zusammen. Beim normalen Beenden und Projektwechsel wird sie beendet. Das bisherige Projektformat bleibt unverändert.
- 22 Domain-Tests erfolgreich, einschließlich Klick-/Drag-Schwelle und Texttransaktionen. Produktionsrenderer und Autosave-Prüfungen erfolgreich. Neuer `scripts/test-canvas.sh` prüft mit einem unsichtbaren synthetischen AppKit-Fenster die tatsächlichen Bildpixel vor mouseUp: Pfeil, Rechteck, Unschärfe. Außerdem Inline-Text am angeklickten Punkt, Draft-Save/Reload und gruppiertes Undo/Redo.
- Im laufenden App-Sandbox-Build: Textfeld im synthetischen Projekt „fixture“ platziert, „Live“ unmittelbar im Bild eingegeben, mit ⌘Enter abgeschlossen und mit einer Rückgängig-Aktion entfernt. Eingabe und fertige Darstellung lagen an derselben Position. Keine Änderung an Nutzeraufnahmen.
- Noch offen: Eingabemethoden/IME, extrem lange Texte, Performance auf großen Bildern und vollständiger VoiceOver-Durchgang. Breitenänderung und automatischer Zeilenumbruch wurden im aktuellen Schritt ergänzt.

Stand: 12. Oktober 2026. Sandboxed lokaler Debug-Build, synthetisches Testbild.

## Nachgewiesen

- Xcode-Build erfolgreich, 19 Domain-Tests bestanden.
- `scripts/test-renderer.sh` prüft den tatsächlichen Produktionsrenderer: native Pixelgröße, Bildorientierung, Transparenz sowie Pfeil- und Textkomposition.
- Im laufenden Editor: synthetisches PNG importiert, Pfeil gezeichnet, Text eingefügt, beide Objekte ausgewählt und verschoben.
- Undo/Redo über Schaltflächen geprüft: eine vollständige Textverschiebung zurückgenommen und wiederhergestellt. Undo-Tastenkürzel ebenfalls geprüft (UI-Automation benötigt beim deutschen Tastaturlayout die entsprechende physische Taste).
- Kopieren meldet erfolgreiches Schreiben des PNG in die Zwischenablage.
- Nativer Speicherdialog schreibt PNG unter Sandbox. Exportdatei anschließend geöffnet: korrekte Orientierung, Pfeil und Text, keine Auswahlgriffe, unveränderte 240 × 160 Pixel.
- Lokale Testdateien liegen ausschließlich im ignorierten Buildordner `build/RendererTests`.

## Noch offen / Grenzen

- Einfügen der Zwischenablage in verschiedene Drittanbieter-Apps und macOS-26-Abnahme.
- 4K-Bilder mit 50 Objekten, längere mehrzeilige Texte, Farbprofile und Performance auf Referenzhardware.
- VoiceOver-Objektliste und vollständige Tastaturbearbeitung des Canvas fehlen noch.
- Keine Mehrfachauswahl; Zoomsteuerung, Form-/Callout-Griffe und Pfeil-Endpunkte sind inzwischen implementiert. Der Callout-Zeiger ist fest angeordnet.
- PNG-Ausgabe ist SDR/sRGB; Transparenz bleibt erhalten. Die Projektoriginale sind ebenfalls SDR/sRGB normalisiert.
- Aufnahmeberechtigungen und echte Screenshot-Aufnahme bleiben separat in `SCREENSHOT-ABNAHME.md` dokumentiert.

## Erweiterung: Eigenschaften und Formen

- Farbe, Linien-/Pfeilstärke, Schriftgröße und Unschärferadius sind am ausgewählten Objekt oder als Vorgabe einstellbar; Änderungen durchlaufen dieselbe Undo-Historie.
- Rechtecke, Ellipsen und Unschärfebereiche werden aufgezogen; Callouts per Klick und Texteingabe erstellt, per Doppelklick bearbeitet.
- Produktionsrenderer automatisiert geprüft: Farbänderung, Pfeilstärke, Textgröße, Rechteck, Ellipse, Callout-Hintergrund und auf den gewählten Bereich begrenzte Unschärfe. Der Grafiktest benötigt Zugriff auf die macOS-Grafikdienste; die zusätzliche Shell-Sandbox verhindert Core-Image-Rendering, der App-Sandbox-Build funktioniert.
- Im laufenden App-Sandbox-Build Unschärfebereich über einer synthetischen Farbkante aufgezogen: Filter und Auswahlrahmen korrekt sichtbar.
- Vorschau berechnet die Komposition asynchron; veraltete Resultate werden verworfen. Unschärfe filtert das Original unter den Annotationen. Bei einem Filterfehler wird die Region schwarz statt ungefiltert ausgegeben.
- Breite UI-Abnahme aller Eigenschaften, Farbpanel, langer Texte und große Bilder bleibt offen.

## Erweiterung: Projekte, Autosave und Bibliothek

- `ProjectStoreTests` prüfen Speichern/Laden sämtlicher Objekttypen und Stile, unveränderte Originaldaten, Wiederherstellung einer beschädigten letzten Revision, atomaren Schreibfehler mit Wiederholung, Versionsprüfung, Größenlimits und konkurrierende Store-Instanzen. Fehlerhafte Einzelprojekte verdecken keine lesbaren Projekte.
- `scripts/test-autosave.sh` verwendet den echten EditorModel und Produktionsrenderer: automatisches Sichern ohne Speicherklick, neuer Store plus neuer Editor, Stiländerung/Undo/Redo nach Laden, gleichzeitige Sicherungsaufrufe, Schreibfehler und Wiederholung sowie Speichern eines Konflikts als Kopie.
- Im laufenden App-Sandbox-Build synthetisches PNG importiert, Rechteck eingefügt, Bibliothekskarte mit Vorschau geprüft, App mit ⌘Q beendet und neu gestartet. Projekt wieder aus Bibliothek geöffnet; Rechteck bleibt auswählbar und verschiebbar, Undo wird nach der Änderung aktiv. Nochmals beendet und gestartet: Auch die neue Position bleibt erhalten. Die Testaufnahme „fixture“ verbleibt als Beispiel in der lokalen Bibliothek.
- Original und Objekte werden gespeichert; Undo-Historie und Werkzeugvorgaben bleiben sitzungsbezogen. Details: `PROJEKTFORMAT.md`.
- Noch offen: erzwungener Prozessabbruch während eines realen Schreibvorgangs, tatsächlich voller Datenträger, große Bibliotheken, Backup/Restore, Papierkorb und Migration eines künftig geänderten Schemas. Automatisierte Fehlerprüfung ist kein Nachweis gegen Stromausfall.

## Erweiterung: Sichtbare Werkzeugleiste

- Das bisherige Werkzeugmenü ist durch sieben direkt sichtbare Schaltflächen oben über dem Bild ersetzt: Auswahl, Pfeil, Text, Callout, Rechteck, Ellipse und Unschärfe. Symbole, Beschriftungen, Hover-Feedback, Hilfetexte und ausgewählter Zustand sind vorhanden; die Accessibility-Struktur meldet das aktive Werkzeug als ausgewählt.
- Eigenschaften stehen unmittelbar unter der Leiste. Ohne Werkzeug oder ausgewähltes Objekt zeigt die Auswahl einen Bedienhinweis. Das ursprüngliche adaptive Raster ist inzwischen durch eine feste, horizontal scrollbar bleibende Zeile ersetzt, um Bildsprünge zu vermeiden. Die Werkzeugleiste bleibt ohne Untermenü sichtbar. Zwei isolierte SwiftUI-Previews decken breite und schmale Palette ab; eine Vorschau-Ausführung wurde nicht separat beobachtet.
- Signierter Xcode-Debugbuild erfolgreich. Im laufenden App-Sandbox-Build am synthetischen Projekt „fixture“ alle sieben beschrifteten Werkzeuge sichtbar. Callout, Pfeil und Unschärfe per direktem Klick ausgewählt; aktive Hervorhebung und passende Eigenschaften geprüft.
- Pfeil über die neue Leiste aktiviert, im Bild gezeichnet, Rückgängig und Wiederholen bedient und abschließend wieder zurückgenommen. Das Testbild behält seine ursprünglichen Objekte. Bei dieser damaligen Abnahme folgte die Leiste dem automatischen Wechsel zur Auswahl nach dem Zeichnen; dieser Rücksprung entfällt seit der unten dokumentierten Änderung vom 13. Oktober. Klick auf ein Werkzeug gibt den Tastaturfokus an den Canvas zurück.
- Kein neues Dokumentformat oder Renderer. Die UI-Anordnung verändert weder Undo-Historie noch PNG-Komposition. Eine neue automatisierte Testserie für die rein visuelle Änderung wurde nicht hinzugefügt.
- Noch offen: echte Fensterabnahme bei Mindestbreite, VoiceOver-Durchgang und Systemeinstellungen für Kontrast/Transparenz. Der automatisierte Versuch, das Fenster per Ziehen zu verkleinern, änderte die beobachtete Breite nicht.


## Aktives Zeichenwerkzeug beibehalten (13. Oktober 2026)

Pfeil, Formen, Ellipse, Unschärfe und Abdecken bleiben nach der Mausgeste aktiv. Text und Callout behalten das gewählte Werkzeug nach Escape oder ⌘Enter. War die Texteingabe über Auswahl geöffnet, bleibt auch danach Auswahl aktiv. Das zuletzt angelegte Objekt bleibt für Eigenschaftenänderungen ausgewählt; die nächste Zeichengeste erzeugt ein neues Objekt. Zum Verschieben und Greifen vorhandener Objekte wird ausdrücklich Auswahl gewählt. Ein Wechsel zwischen Formvarianten wird auch für weitere Zeichengesten übernommen.

`./scripts/test-canvas.sh` ist erfolgreich, einschließlich `Tests/RepeatedToolCanvasChecks.swift`: elf Werkzeug-/Formfälle mit jeweils zwei aufeinanderfolgenden Objekten ohne erneute Werkzeugwahl, unterschiedliche IDs und unverändertes erstes Objekt, Text-/Callout-Abschluss per Escape und ⌘Enter, bewusste Auswahl zur Textbearbeitung, unabhängiges Undo/Redo, Variantenwechsel und Speicherung beider Objekte. Die vorhandenen Tests für Griffbearbeitung wählen Auswahl jetzt ausdrücklich; Zoom-, Zuschnitt-, Live-Vorschau- und native Textprüfungen bestehen weiter. `./scripts/build.sh` ist ebenfalls erfolgreich.

Die laufende Oberfläche wird auf Wunsch vom Nutzer geprüft; die automatisierten Nachweise verwenden ausschließlich synthetische Bilder und AppKit-Ereignisse für isolierte Test-Views.

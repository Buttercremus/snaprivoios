# Snaprivo Entwicklungsplan

Stand: 15. Oktober 2026 · Version 7 · Produktname Snaprivo

SnagForge wird eine native macOS-App zum Aufnehmen, Bearbeiten und Organisieren von Screenshots und kurzen Bildschirmvideos. Bereich oder Fenster auswählen, aufnehmen, verständlich markieren und weitergeben: Dieser Ablauf hat Vorrang. Die App soll sich wie eine moderne Mac-Anwendung anfühlen und von Beginn an für den Mac App Store gebaut werden.

Dieser Plan ersetzt die Empfehlungen der ursprünglichen Entwicklungsstrategie vom 11. Oktober 2026. Er ist eine Produktspezifikation, keine Aussage über bereits implementierte Funktionen. Der tatsächliche Stand steht in der README. Zeiträume bleiben Schätzungen; Plattformverhalten muss mit signierten, sandboxed Builds auf echten Macs geprüft werden.

Die operative Reihenfolge, Checkboxen, Abhängigkeiten und Abnahmekriterien stehen im zentralen [ARBEITSPLAN.md](ARBEITSPLAN.md). Die kommerzielle Bewertung steht in [PRODUCT-BRIEF.md](PRODUCT-BRIEF.md); Preise und Free-/Pro-Grenzen sind weiterhin Vorschläge.

## 1 Verbindliche Entscheidungen

| Thema | Entscheidung |
| --- | --- |
| Produkt | Snaprivo als festgelegter Produktname; Namens- und Markenprüfung vor Veröffentlichung |
| Plattform | macOS 26.0 oder neuer; native Swift-App |
| Sprachen | Deutsch und Englisch; native macOS-App-Sprache, Englisch als Rückfallsprache |
| Design | Apple Human Interface Guidelines, native Liquid-Glass-Komponenten, SwiftUI und gezieltes AppKit |
| Vertrieb | Mac App Store von Anfang an; App Sandbox ab dem ersten Build |
| Daten | Lokale Verarbeitung und Speicherung; kein Konto und keine Cloud für Kernfunktionen |
| Aufnahme | ScreenCaptureKit; keine privaten APIs oder Umgehung von Berechtigungen |
| Editor | Bearbeitbare Objekte; gemeinsame Komposition für Vorschau und Bildexport |
| Kaufmodell | Einmalkauf oder einmalige StoreKit-Vollfreischaltung nach Pilotfeedback |
| Updates | Für den Store-Build ausschließlich über den Mac App Store |
| Architektur | Modularer Monolith; Pakete nur bei tatsächlichem Nutzen |

Kein eigener Lizenzserver, keine Gerätebindung und kein Sparkle im Store-Build. Das frühere Modell mit zwei Macs und zwölf Monaten Updateberechtigung entfällt. Ein späterer Direktvertrieb ist ein eigenes Vorhaben und darf die Store-Architektur nicht voraussetzen oder aufweichen.

## 2 Kernabläufe

### Screenshot eines Fensters

Der Nutzer startet die Aufnahme per Menüleiste, App oder konfigurierbarem globalem Tastenkürzel. „Neue Aufnahme“ blendet eigene Fenster aus, erfasst die Displays mit ScreenCaptureKit als Standbild und startet darauf eine gemeinsame Fenster- und Bereichsauswahl ohne vorgeschaltete Quellwahl. Die Auswahloberfläche ist deckend und fängt Eingaben ab, auch innerhalb eines markierten Fensters. Beim Bewegen der Maus wird das darunterliegende aufnehmbare Fenster hervorgehoben, einschließlich sichtbarer Teile von Hintergrundfenstern. Am Mauspunkt hat das vorderste Fenster Vorrang; vollständig verdeckte Inhalte werden nicht hervorgeholt. Der Ausschnitt bleibt hell, die Umgebung beim Darüberfahren und nach dem Klick gleich stark abgedunkelt. Ein großer kontrastreicher Kreuzcursor markiert den präzisen Auswahlpunkt. Kurze reine Deckkraftübergänge der Auswahlhilfen begleiten Einstieg und Abschluss; das Standbild wird dabei weder bewegt, skaliert noch ausgeblendet. Reduzierte Bewegung wird berücksichtigt. Ein Klick markiert das Fenster; Ziehen markiert stattdessen einen freien Bereich. Danach bleibt ein korrigierbarer Rahmen mit einer kompakten Bestätigungsleiste stehen. „Aufnehmen“ oder Enter schneidet die unveränderten Standbild-Pixel aus und öffnet sie im Editor; Escape bricht ab. Die Fensterwahl übernimmt den sichtbaren Ausschnitt; verdeckte Teile werden nicht rekonstruiert.

Beim Wechsel des erkannten Fensters gleiten Rahmen und heller Ausschnitt in 180 ms gemeinsam an die neue Position und Größe; die Kurve bremst sanft und überschwingt nicht. Ein weiterer Wechsel richtet den laufenden Übergang vom aktuellen sichtbaren Stand neu aus. Kurze Lücken blenden die Markierung in 100 ms aus/ein. Die tatsächliche Fensterwahl folgt sofort dem Mauspunkt; Klicken und freie Ziehgesten warten nie auf die Animation. „Bewegung reduzieren“ deaktiviert die Orts-/Größenanimation. Standbildpixel und Aufnahmegeometrie werden nicht animiert. [Umsetzung und Nachweise](FENSTERWECHSEL-ABNAHME.md).

„Intelligent erkannt“ bedeutet zunächst geometrische Fenstererkennung über öffentliche Systeminformationen, keine KI. Überlappende Fenster, eigene Fenster, minimierte Fenster, Spaces, mehrere Displays und geschützte Inhalte brauchen festgelegte Regeln. ScreenCaptureKit liefert aufnehmbare Quellen; zuverlässiges Hit-Testing und Z-Reihenfolge werden separat erprobt. Der Systempicker dient als Referenz und möglicher Rückfallpfad. Zusätzliche Berechtigungen werden nicht allein zur Komfortsteigerung vorausgesetzt.

### Screenshot eines Bereichs

Im selben Aufnahmemodus zieht der Nutzer einen Rahmen auf dem Bildschirm. Ein Overlay zeigt Pixelabmessungen. Nach dem Loslassen kann er den Rahmen verschieben, mit acht Griffen ändern, neu auswählen oder abbrechen. Nach Bestätigung verschwinden eigene Bedienelemente aus der Aufnahme. Bildschirmkoordinaten in Punkten werden an der Adaptergrenze in Bildpixel umgerechnet.

Die erste Version begrenzt eine Bereichsaufnahme auf ein Display. Ein Wechsel zwischen Displays mit verschiedenen Skalierungen muss korrekt funktionieren. Eine Auswahl über mehrere Displays ist ein späterer, explizit zu spezifizierender Fall.

### Video eines Bereichs oder Fensters

Die gleiche Quellwahl bietet den Modus Video. Vor dem Start wählt der Nutzer Systemton, optional Mikrofon, Cursor und Countdown. Eine erkennbare laufende Aufnahme mit Stop-Aktion bleibt erreichbar. Erst nach erfolgreicher Finalisierung erscheint das Video in der Bibliothek.

Startziel: SDR, H.264/MP4, bis 1080p bei 30 fps mit erhaltener Seitenproportion; kleine Bereiche werden nicht automatisch hochskaliert. Die gewählte Region bleibt zunächst fest. Fensteraufnahme folgt dem ausgewählten Fenster nur im nachgewiesenen API-Verhalten. Größenänderung und Schließen des Zielfensters brauchen ein definiertes Ergebnis. Pause, 4K, HDR, Kamera und Videoeffekte kommen später.

Bildannotationen und Video-Nachbearbeitung sind unterschiedliche Funktionen. Die erste Video-Nachbearbeitung umfasst Vorschau, nicht destruktives Trimmen und Export. Pfeile, Callouts oder Unschärfe mit Zeitsteuerung und Objektverfolgung im Video sind nicht Bestandteil des ersten Releases.

### Bild bearbeiten und weitergeben

Im Editor: auswählen, verschieben, skalieren, markieren, rückgängig machen, kopieren, exportieren oder das fertige PNG über die native macOS-Freigabe teilen. Ein gespeichertes SnagForge-Projekt bleibt nach Neustart bearbeitbar. PNG/JPEG sind flache Ausgaben, keine bearbeitbaren Projektdateien.

Seit 14. Oktober 2026 ergänzt Teilen neben PNG speichern die Systemfreigabe für AirDrop, Mail und andere verfügbare Erweiterungen. Dieselbe flache PNG-Komposition wird asynchron als Transferable übergeben; Ziele und tatsächlicher Versand bleiben im nativen Systemablauf. Bildstand, Dateityp und Schutz durch Abdeckungen sind automatisiert geprüft; echte Ziel-App-/AirDrop-Abnahme steht separat aus. Zusätzlich bietet Öffnen mit die installierten PNG-Apps (Vorschau zuerst) und eine native App-Auswahl. Eigenständige temporäre PNG-Kopien bewahren bestehende externe Bearbeitungen; Abbrüche/Fehler und das Beenden während einer Übergabe sind geprüft. [Nachweise](TEILEN-ABNAHME.md).

## 3 Umfang und Reihenfolge

| Stufe | Inhalt | Fertig, wenn |
| --- | --- | --- |
| P0 Projektgrundlage | Xcode-App, Sandbox, Bibliotheks- und Editor-Grundfläche, Aufnahmeauswahl, Domain-Paket, Buildskripte | App baut; echte und noch fehlende Funktionen sind erkennbar |
| P1 Aufnahme | Fenstererkennung, gezogener Bereich, Display, Abbruch, Cursor, Timer und Hotkeys | Aufnahmen stimmen auf realen Macs; kein eigenes Overlay im Ergebnis |
| P2 Bildeditor | Pfeil, Text, Callout, Rechteck, Ellipse, Hervorhebung, Schrittnummern, Unschärfe, deckende Abdeckung, Crop, Resize, Undo/Redo | Vorschau und Export stimmen überein; Objekte bleiben bearbeitbar |
| P3 Dokumente | Versioniertes Projekt, Autosave, Wiederherstellung, Bibliothek, lokale OCR, Titel/Tags/Suche | Neustart, Schreibfehler und Migrationen verlieren keine gespeicherten Revisionen |
| P4 Video | Region/Fenster/Display, Mikrofon/Systemton, Stop, Finalisierung, Vorschau und Trimmen | Bild und Ton bleiben synchron; Abbruch und Fehler werden sauber behandelt |
| P5 Anleitungen | Screenshot-Serie sortieren, Bildunterschriften, einfache PDF-Ausgabe, gespeicherte Werkzeugstile | Eine kurze Anleitung lässt sich ohne weitere App erzeugen |
| P6 Store-Release | TestFlight, Käufe, Datenschutz, Accessibility, App-Icon, Metadaten und Releaseabnahme | Releaseprüfungen bestehen; tatsächliche Features stimmen mit Werbung überein |

Technische Versuche für Video und Scroll-Steuerung laufen bereits während P1. Die Ergebnisse bestimmen Aufwand und Zusagen; die vollständige Videooberfläche folgt später. Keine automatische Scroll-Funktion als Releaseversprechen, bevor Sandbox und Qualität nachgewiesen sind.

Die erste vollständige Version soll Bilder und kurze Videos unterstützen. Eine frühere Bild-Beta dient dem Lernen. Falls Video den Zeitplan gefährdet, entscheidet der Produktverantwortliche ausdrücklich über einen kleineren Verkaufsumfang; Video wird nicht stillschweigend gestrichen.

## 4 Editorwerkzeuge

- Auswahl: Hit-Testing, Mehrfachauswahl, Verschieben, Größenänderung und Ebenenreihenfolge.
- Pfeile: Endpunkte, Farbe, Stärke und Pfeilspitze; später zusätzliche Linienformen.
- Text: native Texteingabe, Schrift, Größe, Ausrichtung und Farbe; reproduzierbares Textlayout.
- Callout: Textfläche mit Zeiger; Textbox und Zeigerspitze unabhängig positionierbar.
- Formen: Rechteck, Ellipse, Dreieck, Raute und Stern mit unabhängiger Füllung und Kontur; einstellbarer Eckenradius für Rechtecke. Randfarbe, Linienbreite und Linienmuster; sichtbare Formauswahl und Stilvorlagen.
- Hervorhebung: transparente Markierung mit nachvollziehbarer Komposition.
- Schritte: nummerierte Objekte; Reihenfolge und Umnummerierung definieren.
- Unschärfe: regionaler Bildfilter für optische Unkenntlichmachung, keine Zusage sicherer Geheimhaltung.
- Deckende Abdeckung: Export ersetzt betroffene Pixel vollständig; keine vertraulichen Originale oder Texte in Exportmetadaten.
- Crop und Resize: Dokumentoperationen mit eindeutigen Regeln für Objektkoordinaten und Ausgabeauflösung.

Zeichenwerkzeuge bleiben nach dem Erstellen eines Objekts aktiv; es gibt keinen automatischen Wechsel zur Auswahl. Dies gilt auch nach dem Abschließen von Text und Callout mit Escape oder ⌘Enter. Wiederholtes Zeichnen erzeugt weitere unabhängige Objekte. Der Nutzer wechselt zum Verschieben oder Bearbeiten von Griffen ausdrücklich zur Auswahl; das zuletzt angelegte Objekt bleibt für Eigenschaftenänderungen ausgewählt.

Undo/Redo fasst eine Mausgeste als einen Befehl zusammen. Der Export enthält keine Auswahlgriffe. Das Original bleibt im bearbeitbaren Projekt erhalten; die UI erklärt dies bei vertraulichen Inhalten. Ein späterer bereinigter Projektmodus muss auch Original, Revisionen, OCR und Thumbnails ersetzen. Clipboard-, PNG-, JPEG- und später PDF-Exporte werden gleichermaßen auf Datenreste geprüft.

### Aktueller Werkzeugausbau und sinnvolle nächste Ergänzungen

Implementiert: sichtbare Formauswahl mit sechs Varianten, sechs feste Stilvorlagen, Farbfelder plus nativer Farbdialog, unabhängiger Rand mit Voll-/Strich-/Punktlinie, gemeinsame Leiste für Werkzeuge, Bildgröße, Kopieren und PNG in drei gespeicherten Größen (Vorgabe Standard), fester Eigenschaftenbereich, Größenregler plus Zahlenfelder, getrennte Kontur/Füllfarbe, Fülldeckkraft, abgerundete Rechtecke, Live-Vorschau, gruppiertes Undo und Speicherung aller Eigenschaften. Pfeilspitze und Anfang sind direkt ziehbar; der andere Endpunkt bleibt verankert. Formen und Callouts haben acht Größenänderungsgriffe, Live-Vorschau und einen Undo-Schritt pro Geste. Callouts behalten beim Resize ihre Schriftgröße; Rahmen und Textumbruch passen sich an. Umschalt: Quadrate/Kreise, bei anderen Formen/Callouts Proportionen und bei Pfeilen ein 45°-Raster, auch an bestehenden Endpunkten. Neue Pfeile starten mit fester Stärke 15 Bildpixel. Bereits gespeicherte Pfeile behalten ihre Stärke; vorhandene Symbolgrößen bleiben erhalten. Die Vorgabe für neue Installationen ist seit 14. Oktober 2026 Standard. Callouts können ebenfalls gefüllt oder transparent sein. Autosave läuft ohne normale Statuszeile; Speicherfehler bleiben sichtbar. Seit 15. Oktober 2026 sind eigene Werkzeugstile (P02) im Eigenschaftenbereich verfügbar: acht Werkzeuggruppen, bis zu 100 benannte lokale Vorlagen, Anwenden, Umbenennen und Entfernen. Anwendung übernimmt nur unterstützte Darstellungsmerkmale als einen Undo-Schritt; Inhalte, Freihandpfade und bestehende Schrittnummern bleiben erhalten. Die Stilbibliothek liegt versioniert in den App-Einstellungen; angewendete Eigenschaften sind unabhängig davon im Format-6-Projekt gespeichert. Vorlagen selbst werden noch nicht mit Projekt-/Bibliotheksbackups übertragen. 94 Domain-Tests, native Persistenz-/Undo-/Exportprüfungen und synthetische UI-Bedienprüfung bestanden. [Nachweise](WERKZEUGSTILE-ABNAHME.md).

Zoom, Schwenken und 100-%-Ansicht sind als E01 umgesetzt. Die gemeinsame Projektion berücksichtigt die Retina-Skalierung; Ansichtsänderungen erzeugen keine Dokumentoperation und verändern die Exportauflösung nicht. Seit 14. Oktober 2026 bietet das Zoommenü die gespeicherte, standardmäßig aktive Option „Immer passend verkleinern“; deaktiviert öffnen Bilder bei 100 %. Manuelle Zoomstufen bleiben möglich. Unschärfe-Vorschauen behalten die Originalauflösung, und Größenexporte rasterisieren Text/Vektoren direkt in der Zielauflösung. [Pixelprüfungen und Grenzen](BILDSCHAERFE-ABNAHME.md). Nachweis: [Zoom-Abnahme](ZOOM-ABNAHME.md). E02 ergänzt nicht destruktives Zuschneiden mit acht Griffen, Pixelwerten, gemeinsamem Undo, Autosave und konsistenter PNG-/Clipboard-Ausgabe. Original und Objektkoordinaten bleiben erhalten; das Projektformat 2 liest bestehende Version-1-Projekte. Nachweis: [Zuschnitt-Abnahme](ZUSCHNITT-ABNAHME.md). E03 ist ebenfalls umgesetzt: Pixelmaße mit optionaler Seitenverhältnissperre, gemeinsame Skalierung von Bild und Markierungen, Undo/Redo, Autosave und konsistente PNG-/Clipboard-/Thumbnail-Ausgabe. Original und Objektkoordinaten bleiben erhalten; Format 3 liest Version 1/2. [Regeln und Nachweise](BILDAUFLOESUNG-ABNAHME.md). E04 und E05 sind umgesetzt. E05 ergänzt Schriftwahl, Fett/Kursiv, Ausrichtung für ganze Textobjekte und unabhängig ziehbare Callout-Ziele. Format 4 liest Versionen 1–3. [Nachweise](TEXT-CALLOUT-ABNAHME.md). L01 ist umgesetzt: Umbenennen, Favoriten und gespeicherte Bibliothekssortierung. [Nachweise](BIBLIOTHEK-ABNAHME.md). L02 ist ebenfalls umgesetzt: persistenter Papierkorb, Wiederherstellen und bestätigtes endgültiges Löschen. [Nachweise](PAPIERKORB-ABNAHME.md). L03/L04 ergänzen portable Projektdateien und Bibliothekssicherung einschließlich Papierkorb, S01 deckendes Abdecken, S02 bestätigte globale Kürzelauslösung und S03 Erstaufnahme-/Berechtigungsführung. Format 5 liest Versionen 1–4. [Nachweise](PORTABILITAET-DATENSCHUTZ-ABNAHME.md). T01 ist als manueller Scroll-Prototyp mit Vorschau, Grenzen und Editorübergabe implementiert und wieder im Aufnahmemenü aktiv. Drei Abschnitte, anschließende Markierungen und Wiederöffnen nach echtem App-Neustart sind geprüft; [Nachweise und Grenzen](SCROLL-ABNAHME.md). Breite reale Seitenabnahme und Produktisierung bleiben in P01 offen. T02 ist als Bereichs-Videoablauf mit Start/Stop, MP4/H.264, Dateiexport und lokalen Originalen umgesetzt. Seit 15. Oktober 2026 lassen sich Systemton und das macOS-Standardmikrofon vor dem Start unabhängig einschalten, je Sitzung standardmäßig aus; eigenes App-Audio ist ausgeschlossen. Mikrofonfreigabe wird nur beim ausdrücklichen Start mit gewähltem Mikrofon geprüft/angefragt. Ablehnung erhält die Auswahl und erlaubt den erneuten Start nach Ausschalten des Mikrofons oder Freigabe in den Systemeinstellungen. Vier Tonkonfigurationen, simulierte Berechtigungszustände und synthetische AAC-MP4s sind geprüft. Echte Kurztests auf M1 Pro/macOS 27 messen für Systemton und kombinierten Ton maximal rund 79/73 ms Versatz; bestätigtes Klatschen belegt den Mikrofonbeitrag. Ein reproduzierter Stillstand nach vier Videoframes ist mit acht Oberflächenpuffern und laufender Pufferabnahme korrigiert. Mikrofon allein liefert eine lesbare Spur, seine Synchronität braucht noch ein kalibriertes akustisches Signal; Pegel, macOS 26 und Langzeittests bleiben offen. Weitere Tests erfolgen auf Nutzerwunsch später; [Video-Nachweise und verbleibende Experimente](VIDEO-ABNAHME.md). Die vollständige Ton-/Fehlerabnahme sowie V01/V04 bleiben offen; V02-Speicherung/Bibliothek und V03-Vorschau/Trimmen/Export sind separat umgesetzt. P03 ergänzt Markieren als Rechteck und Freihand sowie direkt gesetzte Schrittmarken mit Zahlen/Buchstaben, vier Formen, Farben und Größe. Nummern bleiben stabil; der nächste Wert folgt dem höchsten vorhandenen Wert je Typ. Format 6 liest Versionen 1–5. Koordinaten, Undo, Speicherung, PNG und Zwischenablage sind mit synthetischen Fixtures geprüft; die persönliche Bedienprüfung erfolgt durch den Nutzer. [Bedienregeln und Nachweise](MARKIEREN-LISTE-ABNAHME.md).

Seit 16. Oktober 2026 ergänzt V01 den Menüpunkt **Video: Fenster aufnehmen …** mit eigenständiger ScreenCaptureKit-Fensterquelle. Die Auswahl behält ihre Fenster-ID; Start prüft genau dieses Fenster erneut und fällt bei fehlender Quelle nicht auf den Bildschirm zurück. Vollständige Fenstergröße und Pixelskalierung bestimmen die gerade, auf 1080p begrenzte SDR-Ausgabe. Ohne festen Crop und mit Skalierung/Seitenverhältnis ist die Quelle für Bewegung und Größenänderung konfiguriert; eine manuelle Änderung des Auswahlrahmens hebt die Fensterbindung ausdrücklich auf. Build, 114 Domain-Tests, native Capture-/Video-/Sprachprüfungen und deutsche Auswahl-/Fehlerbedienung mit synthetischem Fenster bestanden. Der Video-Vorlauf ist anschließend ergänzt: Keine/3/5 Sekunden in der Steuerung, Vorgabe aus den Aufnahme-Einstellungen, Änderung nur für die Sitzung. Die Videoauswahl öffnet sofort; Countdown nach explizitem Start und nötiger Mikrofonfreigabe, mit Abbrechen/Escape/Fensterschließen. Arbeitsdatei und Engine entstehen erst nach Ablauf, die Aufnahmezeit beginnt nach dem Start. 115 Domain-Tests sowie native Countdown-/Abbruch-/Berechtigungsprüfungen bestanden. Echte Fenster-/Displayaufnahme und umfassende Quellen-/Stop-Abnahme bleiben offen; die restlichen Ton-/Synchronitätstests erfolgen weiterhin später. [V01-Teilnachweis und Grenzen](VIDEO-ABNAHME.md#v01-teilschritt-eigenständige-fensterquelle--16-oktober-2026).

Auf Nutzerwunsch vom 17. Oktober 2026 bleibt die Auswahlansicht während der Videoaufnahme über dem Live-Desktop bestehen: außen 42 % schwarze Abdunklung, innen ein klarer bedienbarer Ausschnitt mit rotem Rahmen. Die kompakte Leiste darunter bzw. bei Platzmangel darüber zeigt REC mit pulsierendem rotem Punkt, Laufzeit, Pixelmaßen und Stop. „Bewegung reduzieren“ lässt den Punkt dauerhaft sichtbar. Vorlauf/Start/Fertigstellung verwenden dieselbe Leiste; nur Ton-/Berechtigungskorrekturen oder manuell geöffnete Aufnahmeoptionen benötigen das große Fenster. Abdunklung und Rahmen sind klickdurchlässig; die REC-Leiste nimmt die Stop-/Abbruchaktion entgegen. Fensterquellen erhalten einen mitbewegten Rahmen, unsichtbare Quellen keinen veralteten Rahmen auf dem Desktop. Nach explizitem Stop und bestätigter Finalisierung schließt die Aufnahmesteuerung und öffnet direkt die vorhandene V03-Vorschau mit Trimmen und MP4-Speicherung. Normales App-Beenden finalisiert ohne Editoröffnung. Die erste Videoaufnahme wird nicht von der Einführung überlagert. Native Rahmen-/Lebenszyklusprüfungen, Sandbox-Schnitt-/Unterbrechungsregressionen und die Bedienung mit synthetischen Clips sind geprüft; eine neue echte Aufnahme-/Overlay-Ausschlussabnahme bleibt offen. [Ablauf und Nachweise](VIDEO-ABNAHME.md#aufnahmerahmen-und-direkter-videoeditor--17-oktober-2026).

V02 ergänzt seit 16. Oktober 2026 den Videos-Bereich der Bibliothek mit fertigen Originalen, kleinen versionierten Metadaten, Vorschaubild/Medienfakten, Titelsuche, Sortieren, Umbenennen und Öffnen in der zugeordneten macOS-App. Unterbrochene/fehlgeschlagene Aufnahmen bleiben erkennbar und nicht abspielbar; Altdateien werden vor Übernahme geprüft. Umbenennen schreibt keine große Videokopie. Eine separate Ordnersicherung enthält fertige MP4s samt Metadaten und SHA-256; Wiederherstellung validiert alle Quellen vor Übernahme und erzeugt neue IDs. Die Bildbibliothekssicherung bleibt ausdrücklich auf Bilder beschränkt. 118 Domain-Tests, native Speicher-/Sicherungsprüfungen einschließlich Sandbox und echtem Prozessneustart bestanden. Interne Vorschau/Trimmen sind inzwischen als V03 umgesetzt; die echte Ton-/Hardwareabnahme bleibt offen. [V02-Regeln und Nachweise](VIDEO-BIBLIOTHEK-ABNAHME.md).

V03 ergänzt seit 16. Oktober 2026 die interne AVKit-Vorschau und nicht destruktive Start-/Endgrenzen. Übernehmen/⌘S schreibt den kleinen Arbeitsstand mit Revisionsschutz; Undo/Redo und Rückkehr zum ganzen Original verändern keine MP4-Originaldatei. Videoformat 2 liest Version 1, und Sicherung/Wiederherstellung bewahrt das vollständige Original samt Schnitt. MP4-Ausgabe aus Vorschau und Bibliothek verwendet die gespeicherten Grenzen und die gemeinsame Bild-/Tonzeitspanne. Kodierung und Medienprüfung erfolgen vor atomarer Veröffentlichung; Abbruch und Fehler bewahren das bestehende Ziel. 120 Domain-Tests, native Sandbox-Schnitt-/AAC-Zeitachsen-/Persistenz-/Exportprüfungen und zwei Prozessstarts bestanden. Die deutsche Produktionsoberfläche mit synthetischen Clips ist bedient; dies ersetzt keine echte Aufnahme-/akustische Synchronitätsabnahme. Diese bleibt auf Nutzerwunsch später. [V03-Regeln, Nachweise und Grenzen](VIDEO-TRIMMEN-ABNAHME.md).

V04 ist seit 16. Oktober 2026 ohne Ton teilweise geprüft: echte Fensterquelle mit Größenänderung/Verschieben, kontrolliertem Stop und MP4-Dateiprüfung. Sleep-/Displaymeldungen werden kontrolliert abgeschlossen; unveränderte Display-Snapshots bleiben unbeeinflusst. Eine echte macOS-Speicherunterbrechung deckte die Reihenfolge Dateiende vor konkretem Streamfehler auf; ein kurzer begrenzter Abgleich erhält nun die ursächliche Fehlermeldung. Native stumme Sandbox-Prüfungen bestehen. Der 15-Minuten-Lauf scheiterte an den aktuellen Speicherbedingungen; rund 28 fps im kurzen Änderungsversuch sind kein 30-fps-Abnahmepass. Korrigierte Minimierung/Wiederherstellung samt Stop/MP4-Ausgabe und Fehlerabschluss beim Quellschließen sind nach Entsperren praktisch geprüft; die Minimierung erzeugt eine rund 1,39-s-Bildlücke. Dauerlauf, Bildratenziel, weitere Hardwarefälle sowie Ton/Synchronität bleiben offen. [V04-Teilabnahme](VIDEO-V04-ABNAHME.md).

Der T02-Videoablauf behandelt seit 15. Oktober 2026 injizierte Start-/Stop-/Aufnahmefehler mit derselben Steuerung wie die echte ScreenCaptureKit-Aufnahme. Start/Stop haben jeweils eine 15-Sekunden-Grenze für Plattformrückmeldungen. Start verlangt Stream- und Recording-Bestätigung; Stop darf erst nach erfolgreicher Stream-Rückmeldung und Dateiende zur Dateiprüfung übergehen. Der erste Fehler bleibt maßgeblich, doppelte/verspätete Callbacks und parallele Stops erzeugen keinen zweiten Abschluss. Arbeitsdateien werden erst nach bestätigt beendeter Ausgabe bereinigt; unbestätigte bleiben verborgen und sind keine fertigen Videos. Fehler sperren Speichern/Vorschau; Abbruch und normales Beenden folgen denselben Regeln. Synthetische Fehler-/Berechtigungs-/Speicherprüfungen bestehen; echte Systemunterbrechungen, voller Datenträger, Mikrofon-Synchronität und die 15-Minuten-A/V-Abnahme bleiben offen. [Fehlerprüfmatrix](VIDEO-ABNAHME.md).

Die noch offenen Editor-Ergänzungen werden mit Abnahmekriterien im [Arbeitsplan](ARBEITSPLAN.md) gepflegt: Phase 1 enthält Zoom/Crop/Bildauflösung und direkte Bearbeitung, Phase 3 das inzwischen implementierte deckende Abdecken, Phase 5 eigene Stile und Dokumentationswerkzeuge. Die offenen Checkboxen sind keine Aussage über bereits verfügbare Funktionen.

Die Referenz iScreen Shoter ergänzt den optionalen Ideenbestand im Arbeitsplan (I01–I06): angeheftete Aufnahmen, Pipette/Pixellupe, Schnellaktionen, weitere Einzelbild-Ausgaben, OCR-Übersetzung und eingefügte Bilder. Die direkte Texterkennung gehört zu P04. Diese Kandidaten ändern weder den aktuellen nächsten Schritt noch automatisch den V1-Pflichtumfang oder die Free-/Pro-Grenzen.

## 5 Oberfläche und Liquid Glass

Die App besteht aus Bibliothek, Editor und einer kompakten Aufnahmeoberfläche. Aufnahme und Bereichsauswahl sind eigene Zustände: Während der Auswahl verdeckt kein großes Konfigurationsfenster das Ziel.

Bibliothek: native Seitenleiste, Raster/Listendarstellung, Suche und einklappbarer Inspektor. Doppelklick öffnet den Editor, Leertaste die Vorschau. Bearbeitbare Projekte, Quellformate und Exportformate werden begrifflich getrennt. Keine Team- oder Integrationsnavigation ohne Funktion.

Editor: ruhige Bildfläche, gemeinsame Symbolleiste mit Werkzeugen links und Bildgröße/Kopieren/PNG/Teilen/Öffnen mit rechts im selben Symbol-/Beschriftungsstil sowie ein fester, 260 pt breiter Eigenschaftenbereich rechts mit Schiebereglern plus Zahlenfeldern. Bei vollständig sichtbarer Standardreihenfolge stehen Teilen und Öffnen mit nach einem eigenen senkrechten Trenner; Öffnen mit zeigt wie die anderen Buttons das Symbol über der Beschriftung und öffnet ein natives App-Menü. Die Leiste nutzt die gesamte Editorbreite und bietet wählbare Größen; bei knapper Breite scrollen die Werkzeuge, während die Dokumentaktionen sichtbar bleiben. Projekttitel und Pixelmaße stehen unten im Statusbereich, der Titel bleibt umbenennbar. Die Werkzeugleiste sitzt unmittelbar unter der Fensterleiste. Aufnahmeauswahl, Formen, Callout-Rahmen und Zuschneiden verwenden eine gemeinsame Darstellung weißer runder Eckgriffe und länglicher Seitengriffe mit Akzentkontur, Schatten und größeren Trefferflächen. Im Editor bleiben ihre Größen unabhängig von Zoom und Bildseitenverhältnis konstant; überlappende Trefferflächen wählen den nächsten Griff. Textbreite und runde Pfeil-/Callout-Ziele verwenden denselben Zeichenstil. [Nachweise](AUSWAHLGRIFFE-ABNAHME.md). Anpassen verkleinert bei Platzmangel, vergrößert kleine Bilder aber nicht über 100 %; größere Ansichten bleiben ausdrücklich per Zoom wählbar. Werkzeugwechsel verändern die Bildfläche nicht. Liquid Glass dient Navigation und Bedienelementen, nicht dem Screenshot selbst. Systemkomponenten werden bevorzugt; keine nachgebaute Fensterdekoration, keine flächendeckenden Blur-Effekte.

Einstellungen sind als native Bereiche Allgemein, Symbolleiste, Speicherorte, Aufnahme, Tastenkürzel und Datenschutz umgesetzt. Seit 14. Oktober 2026 lassen sich Werkzeuge und Bildaktionen innerhalb ihrer Gruppen per Ziehen oder Pfeilbuttons umsortieren, gespeichert und mit Rücksetzung auf Standard. Ein Augenschalter blendet einzelne Symbole ein oder aus; die Sichtbarkeit wird getrennt von der Reihenfolge gespeichert. Ausgeblendete Einträge bleiben in der Einstellliste. „Alle einblenden“ stellt die Sichtbarkeit wieder her. Beim Ausblenden des aktiven Werkzeugs wechselt der Editor zur Auswahl; auch eine vollständig ausgeblendete Leiste bietet einen Zugang zum Einblenden. Dieselben Optionen sind per Rechtsklick auf die Editorleiste unter „Symbole anordnen …“ erreichbar. Automatisches Kopieren ist unter Allgemein, Aufnahme, in den Aufnahmeoptionen und im Kontextmenü wählbar; es übernimmt neue Screenshots einschließlich Scroll-Aufnahmen ohne Kopierklick und auch bei einem Speicherfehler im bisherigen Editor. Bildimporte bleiben davon ausgenommen. Darstellung System/Hell/Dunkel, Werkzeuggröße, Standardvorlauf, Mauszeigeraufnahme und optionales Kopieren neuer Screenshots bleiben gespeichert. Speicherorte trennt PNG-Standardordner und Projektbibliothek; ein Bibliothekswechsel übernimmt vorhandene Projekte samt Papierkorb durch überprüftes Kopieren und behält die Quelle. Der native Kürzel-Recorder prüft doppelte/reservierte Belegungen und globale Registrierungskonflikte vor dem Ersetzen; öffentliche HIToolbox-Hotkeys benötigen keine zusätzliche Eingabeüberwachung. Die app-lokale Aufzeichnung ist zeitlich begrenzt. Technische und native Nachweise sowie die noch offene physische globale Abnahme: [Einstellungsabnahme](EINSTELLUNGEN-ABNAHME.md), [Speicherorte und Darstellung](SPEICHERORTE-DARSTELLUNG-ABNAHME.md).

macOS 26 ist die Mindestversion, nicht eine eingefrorene Optik. Die App wird mit dem unterstützten aktuellen Xcode gebaut und auf Mindestversion sowie aktuellem macOS geprüft. Systemeinstellungen für Transparenz, Kontrast, Bewegung, Akzentfarbe sowie Hell/Dunkel werden berücksichtigt.

Apple-konformes Verhalten umfasst außerdem Menübefehle, Tastaturfokus, Shortcuts, Drag-and-drop, native Dateidialoge, Mehrfensterverhalten und VoiceOver. Für den eigenen Canvas ist eine zugängliche Objektliste vorzusehen. Touch-Zielgrößen von iOS werden nicht unreflektiert auf eine Mac-Werkzeugleiste übertragen.

Seit 14. Oktober 2026 ist **Support & Feedback …** im Hilfe-Menü, Menüleistenmenü und unter Einstellungen → Allgemein erreichbar. Der gemeinsame Einstieg öffnet einen E-Mail-Entwurf an die vom Nutzer festgelegte Adresse **support@snaprivo.com** mit App-Version und Buildnummer. Es werden keine Aufnahmen, Projektdateien oder lokalen Pfade angehängt; Versand erfolgt ausdrücklich im Mailclient. Build und URL-Kodierung sind geprüft, die echte Mailclient-/Versandabnahme bleibt offen.

## 6 Architektur

Seit 14. Oktober 2026 unterstützt die App Deutsch und Englisch. Native String-Kataloge decken Oberfläche, Aufnahme-Overlays, Bedienungshilfen, AppKit-Dialoge, Support-Entwurf und Dateityp-Beschreibungen ab. Foundation-Ressourcen im Domain-Paket lokalisieren dessen eigene Fehlermeldungen ohne UI-/Capture-Abhängigkeit. macOS wählt die unterstützte App-Sprache; Änderungen gelten nach App-Neustart. Projektdaten, eingefügte Texte, interne IDs und bestehende Pfade werden nicht übersetzt. Die englischen Produktionsansichten wurden zusätzlich in einer isolierten Prüf-App visuell geprüft. Bibliotheks- und Editorleisten wechseln bei Platzmangel auf mehrere Zeilen; englische Werkzeugbeschriftungen und Zoom bleiben vollständig sichtbar. [Nachweise, visuelle Prüfabdeckung und verbleibende Abnahme](LOKALISIERUNG-ABNAHME.md).

| Baustein | Aufgabe |
| --- | --- |
| AppShell | SwiftUI-Szenen, Menüleiste, Navigation, Einstellungen und Commands |
| CaptureCore | ScreenCaptureKit-Adapter, Quellen, Rechte, Koordinaten, Auswahl-Overlay |
| SnagForgeDomain | UI-unabhängige Dokument-, Werkzeug- und Aufnahmeabsichten |
| EditorUI | AppKit-Canvas, Texteingabe, Hit-Testing und SwiftUI-Eigenschaften |
| Rendering | Core Graphics/Core Image, gemeinsame Bildkomposition und Export |
| LibraryStore | Projektdateien, Revisionen, Index, Thumbnail-Cache und Wiederherstellung |
| TextRecognition | Lokale Vision-OCR und optionale abschaltbare Inhaltssuche mit wiederaufbaubarem SQLite-Cache |
| VideoCore | SCStream/SCRecordingOutput, AVFoundation für Trimmen und Export |
| Store | StoreKit nur bei In-App-Kaufmodell; Wiederherstellen und Offline-Verhalten |

Domain kennt weder SwiftUI noch ScreenCaptureKit. UI-Zustand ist MainActor-isoliert, CPU-intensive Aufnahmeverarbeitung, OCR und Export blockieren die Oberfläche nicht. Ressourcen und parallele Jobs erhalten Grenzen. Kein eigener Metal-Renderer ohne gemessenen Bedarf. Neue Adapter entstehen mit ihrer Funktion, keine Sammlung ungenutzter Service-Stubs.

Bildkoordinaten sind Pixel mit Ursprung oben links. Originalabmessungen, Farbraum und Skalierung werden gespeichert. Display-, AppKit- und Vision-Koordinaten werden nur an klaren Grenzen übersetzt. Vorschau und Export verwenden dieselben Geometrie- und Textlayoutregeln.

## 7 Datenhaltung und Dateizugriff

Projektpaket: versioniertes Manifest, Dokument mit Objekten und Operationen, unveränderliche Assets und ableitbare Vorschaudateien. Das erste Bildprojektformat ist in [PROJEKTFORMAT.md](PROJEKTFORMAT.md) festgehalten und implementiert. Eine unbekannte neuere Version wird nicht überschrieben.

Assets und Dokumentrevisionen werden getrennt geschrieben. Autosave einer Markierung kopiert nicht das gesamte Originalbild oder Video. Eine neue Revision wird vollständig geschrieben und danach atomar als aktuell veröffentlicht; verwaiste temporäre Daten sind bereinigbar. Die letzte intakte Revision bleibt wiederherstellbar.

Die Bibliothek liest Titel, Tags und Sammlungszuordnungen aus den Projektpaketen und durchsucht diese Metadaten direkt außerhalb des MainActor. Seit P05 ergänzt ein optionaler SQLite-Cache die Suche um lokal erkannten sichtbaren Bildtext; er ist aus Original und Dokument wiederaufbaubar. OCR-Indexierung ist zunächst aus, zeigt Fortschritt und lässt sich abbrechen, fortsetzen, neu aufbauen oder samt Cache ausschalten. Medien werden nicht als Datenbank-BLOB gespeichert. Bibliotheksdaten liegen standardmäßig im App-Container. Importe werden nach Bestätigung als Kopie übernommen; Exporte verwenden native Dateidialoge. Der implementierte dauerhafte Zugriff auf den gewählten PNG-Standardordner und eine eigene Bildbibliothek verwendet Security-Scoped Bookmarks. Nicht erreichbare Bibliotheken werden gesperrt, statt still am Standardort weiterzuschreiben; eine erneute Freigabe ist möglich. Der Wechsel kopiert und verifiziert vor dem Umschalten und überschreibt keine vorhandene Zielbibliothek.

Umgesetzt: versionierte Bildprojekte, Autosave, Neustart mit weiterhin bearbeitbaren Objekten, Wiederherstellung der vorherigen Revision, lokale Bibliothek mit Vorschaubildern/Titelsuche, sichtbare Speicherfehler und Schutz vor konkurrierendem Überschreiben. Undo-Historie beginnt beim Öffnen neu. L03/L04 implementieren externe `.snaprivo`-Projektdateien und additive Backup-Wiederherstellung mit ID-Konfliktbehandlung. Native Dateidialoge begrenzen den Zugriff auf gewählte Orte. Tatsächlich voller Datenträger, Prozessabbruch während einer Mehrprojekt-Wiederherstellung, große Bibliotheken und künftige Schema-Migrationen bleiben Releaseprüfungen.

Seit 15. Oktober 2026 ist P04 implementiert: **Text erkennen** im Editor und ⇧⌘T öffnen lokale Vision-OCR für das sichtbare Bild oder einen gewählten Bereich. Ergebnis korrigieren und als Klartext kopieren; automatische oder explizite Sprachwahl, Leer-/Unsicherheits-/Fehlermeldungen, Abbruch und Hintergrundverarbeitung mit einem Job. Zuschnitt, Resize und Abdeckungen fließen über den Export-Renderer ein; große OCR-Eingaben sind auf 4.096 Pixel je Kante und 12 MP begrenzt. Ergebnistext wird nicht im Projekt, Index oder Diagnosebericht gespeichert. Kein Upload, keine neue Berechtigung und keine automatische Schwärzung. Domain, echte Vision-Erkennung, App Sandbox und Produktionsoberfläche sind mit synthetischen Bildern geprüft. P05 ergänzt seit 16. Oktober 2026 die abschaltbare Bibliotheksindexierung und Inhaltssuche. Ergebnistext aus dem P04-Dialog bleibt unabhängig davon flüchtig. [Nachweise und Grenzen](OCR-ABNAHME.md).

P05 speichert seit 16. Oktober 2026 Tags und mehrfache einfache Sammlungszuordnungen im Projektformat 7. Bis zu 32 Tags / 16 Sammlungen je Projekt, Namen mit bis zu 80 Zeichen; Filter wirken zusammen mit Suchwörtern und Favoriten. Laden, Objekt-Undo, Sichern als Kopie, Projekttransfer, Papierkorb, Backup und Bibliothekswechsel erhalten die Metadaten. Der OCR-Suchcache liegt separat im App-Container, wird nicht exportiert und verwendet den sichtbaren Bildstand einschließlich Abdeckungen. Noch ungesicherte Bildänderungen schließen alte Treffer aus; Ausschalten widerruft Jobs und entfernt den Cache. SQLite stammt aus dem öffentlichen macOS-SDK; keine externe Paketabhängigkeit und keine neue Berechtigung. [Nachweise, SQLite-Lizenzprüfung und Grenzen](BIBLIOTHEK-SUCHE-ABNAHME.md).

P06 zeigt ohne Anleitungen einen vollständigen Einstieg mit Neu/Importieren; vorhandene Anleitungen stehen in einer durchgehenden Liste. Die Screenshot-Auswahl verwendet kleine Vorschauen aus dem flachen Cache mit Hintergrunddekodierung. P06 ergänzt seit 16. Oktober 2026 einen eigenen Anleitungsbereich: mehrere flache sichtbare Screenshot-Stände übernehmen, Schritte sortieren, Titel/Einleitung/Bildunterschriften bearbeiten, PDF-Stil Standard/Kompakt gemeinsam anwenden und PDF mit identischer Vorschau oder Markdown samt PNG-Ordner exportieren. Bilder sind auf 2560 Pixel je Kante begrenzt; lange Texte laufen über PDF-Folgeseiten. Arbeitsstände bleiben per Autosave, vorheriger Revision und Konfliktkopie aktualisierbar. Bildaktualisierung ist bewusst, erhält eigene Beschriftungen und übernimmt aktuelle Markierungen/Zuschnitt/Abdeckungen. `.snaprivoguide` überträgt ausschließlich aktuelle flache Bilder und Anleitungstexte/Stil; keine Originale, Editorobjekte, OCR oder lokale Projektverweise. PNG-Metadaten importierter Dateien werden entfernt. Anleitungen liegen unabhängig von der Bildprojekt-Bibliothek im App-Container und benötigen eine separate bearbeitbare Sicherung. [Bedienung, Format, Tests und verbleibende Release-Abnahme](ANLEITUNG-AUSGABE-ABNAHME.md).

Auf Nutzerwunsch vom 16. Oktober 2026 ergänzt I07 eine horizontale Bildvorschauleiste direkt im Editor. Aktive Bildprojekte bleiben in stabiler Erstellungsreihenfolge erreichbar; Klick und optionale ⌥⌘-Pfeilkürzel öffnen den vorhandenen Projektladepfad. Fenster und Werkzeugleisten behalten beim Wechsel ihre Identität; nur die fertig dekodierte Bildfläche und bildbezogene Informationen wechseln. Werkzeug und Zeichenstil bleiben erhalten, das bisherige Bild ist während der Wartezeit sichtbar und gegen Eingaben gesperrt. Offene Änderungen/Exporte werden abgeschlossen, Fehler behalten den bisherigen Editor, unbestätigte Gesten und Zuschnitt sperren den Wechsel. Thumbnails stammen aus der sichtbaren gespeicherten Komposition und werden im Hintergrund dekodiert; keine neuen Originalkopien oder zusätzlichen Rechte. [Bedienung und Nachweise](BILDVORSCHAULEISTE-ABNAHME.md).

## 8 Aufnahmeberechtigungen und Sandbox

Die Sandbox bleibt in Entwicklung, Beta und Release aktiv. Bildschirmzugriff wird erst für die erste entsprechende Aufnahme angefragt, Mikrofonzugriff nur bei gewähltem Mikrofon. Der Videozustand besitzt eine klare Aufnahme- und Stop-Anzeige. Ablehnung, Widerruf und erneuter Versuch sind definierte Zustände.

Der Editor benötigt Lese-/Schreibzugriff auf ausdrücklich über native Dateidialoge ausgewählte Bilddateien für Import und PNG-Export. Benutzergewählte dauerhafte Speicherorte verwenden zusätzlich `com.apple.security.files.bookmarks.app-scope`; deren Zugriff bleibt während der Nutzung aktiv und endet bei Wechsel bzw. Beenden. Audio-Entitlements und Nutzungstexte werden mit der tatsächlichen Aufnahmefunktion ergänzt. Ein erfolgreicher unsandboxed Prototyp gilt nicht als Nachweis für den Store-Build.

Automatisches Scrollen über fremde Apps ist ein eigenständiges Risiko: TCC-Freigabe hebt Sandbox-Grenzen nicht auf. Zuerst wird manuelles Scrollen mit überlappenden Aufnahmen und Stitching geprüft. Sticky Header, virtuelle Listen, Animationen und geringe Match-Sicherheit müssen zu erkennbarem Abbruch statt falschem Ergebnis führen. Höhenlimit, Vorschau und Wiederholung sind Pflicht. Eine Browser-Erweiterung wäre ein separates Vorhaben, kein stiller Ausweg.

## 9 Tests und Freigaben

Automatisierte Tests konzentrieren sich auf Koordinaten, Undo/Redo, Exportkomposition, Schema-Migration, Schreibfehler und Wiederherstellung. Synthetische Bilder ersetzen vertrauliche Screenshots. UI- und Capture-Tests auf realen Macs ergänzen diese Tests.

| Bereich | Nachweis |
| --- | --- |
| Aufnahme | Retina, negative Display-Ursprünge, verschiedene Skalierungen, eigenes Overlay ausgeschlossen, Escape und Rechteentzug |
| Fenstererkennung | Überlappung, Spaces, verdeckte und geschlossene Fenster, Mehrdisplaybetrieb; bekannte Grenzen dokumentiert |
| Editor | 4K-Bild mit 50 Objekten, Zoom/Resize, Texteingabe, undo-fähige Gesten und geometrisch gleicher Export |
| Daten | Prozessabbruch beim Speichern, voller Datenträger, alte/neue Schemas, beschädigtes Einzelprojekt, Indexneuaufbau |
| Export | Farbprofile, Transparenz, Größen, Abdeckung und keine sensiblen Zusatzdaten |
| Video | 15 Minuten SDR/1080p/30 fps, A/V-Versatz unter 100 ms als Ziel; Anfang/Mitte/Ende, Gerätewechsel, Sleep und Finalisierungsfehler |
| Bedienung | Tastatur, VoiceOver, Hell/Dunkel, mehr Kontrast, weniger Transparenz/Bewegung |
| Store | Signierter Sandbox-Build, Käufe falls vorhanden, Restore, Erstinstallation, Update, sauberes Testkonto |

Performance-Ziele werden mit Referenzhardware und OS-Version angegeben. Für Screenshot-Latenz werden Warm- und Kaltstart getrennt erfasst; ein kleiner Versuch mit 20 Aufnahmen ist ein erstes Signal, keine statistisch belastbare p95-Aussage. Video- und Capturequalität sind mit einem Build allein nicht nachgewiesen.

## 10 Abarbeitung und Nachweise

Die zentrale Aufgabenliste ist [ARBEITSPLAN.md](ARBEITSPLAN.md). Sie ersetzt die bisherige separate Liste der nächsten Arbeitspakete in diesem Abschnitt. Der aktuelle nächste Schritt wird ausschließlich dort gepflegt.

Reihenfolge: Editorbasis → Bibliotheksverwaltung/Projektportabilität → deckendes Abdecken und Aufnahmekomfort → frühe Scroll-/Video-Versuche → Pro-Abläufe und vollständiges Video → Kaufmodell/StoreKit → Pilot, reale Abnahmen und Store-Release. Manuelle Capture-Abnahmen und technische Versuche dürfen früh unabhängig stattfinden. Offene Preisentscheidungen blockieren nur die davon abhängige Kaufimplementierung.

Jede Aufgabe enthält ein überprüfbares Fertig-Kriterium und gegebenenfalls Voraussetzungen. Erledigte Aufgaben erhalten einen Nachweis; fehlende Funktionen bleiben offen. Die README beschreibt die tatsächliche Implementierung. Die vorhandenen Capture- und Editor-Abnahmeprotokolle bleiben die Detailnachweise. Reale Berechtigungs-, Mehrdisplay- und Bedienungsabnahmen bleiben erforderlich.

## 11 Zeit und Veröffentlichung

12–16 Wochen bleiben ein vorläufiger Korridor für eine begrenzte Beta bei regelmäßiger Mitarbeit und Mac-Abnahmen. Für den vollständigen Bild-/Videoeditor und den Store-Release wird erst nach den Capture-, Video- und Editorversuchen eine neue Schätzung erstellt. Scroll-Automatik und erweiterte Videoannotation sind darin nicht zugesagt.

Vor Veröffentlichung: App-Icon, Name, Supportadresse, Datenschutzerklärung, App-Privacy-Angaben, Prüfung benötigter Privacy Manifests und Required-Reason-APIs einschließlich Abhängigkeiten, echte Store-Screenshots, Kaufmodell, Wiederherstellung von Käufen falls vorhanden und App-Review-Hinweise. Screenshots und OCR-Inhalte dürfen nicht in Diagnoseberichte gelangen. App-Review-Zulassung wird durch technische Tests nicht garantiert.

## 12 Quellen

Primärquellen für die Planrevision; konkrete API-Verfügbarkeit zusätzlich im verwendeten SDK prüfen.

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) – insbesondere 2.4.5, 2.5.1, 2.5.14 und 3.1.1.
- [Apple App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).
- [Apple Liquid Glass übernehmen](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
- [Apple Human Interface Guidelines Materialien](https://developer.apple.com/design/human-interface-guidelines/materials).
- [Apple AppKit modernisieren](https://developer.apple.com/videos/play/wwdc2026/289/).
- [ScreenCaptureKit Bild Video und Audio](https://developer.apple.com/videos/play/wwdc2024/10088/).
- [Apple Vision Texterkennung](https://developer.apple.com/documentation/vision/recognizing-text-in-images).

## Namensentscheidung – 13. Oktober 2026

Produktname: **Snaprivo**. **snaprivo.com** (Hauptdomain) und **snaprivo.de** sind laut Nutzer gekauft. Die sichtbare Umbenennung der App folgt unter D05. Xcode-Projekt, Bundle-ID und Speicherpfade bleiben vorerst stabil, damit bestehende Projekte und Bildschirmfreigaben erhalten bleiben.

E04 ist am 13. Oktober 2026 umgesetzt: Duplizieren mit eigener Objekt-ID, vier Ebenenaktionen, Undo/Redo und Autosave. Unschärfebereiche bleiben unter den Markierungen. Nachweise: [Objekt-Abnahme](OBJEKTE-ABNAHME.md).


Namensumstellung 13.10.2026: App und Xcode-Projekt/Scheme/Target heißen **Snaprivo**, Hauptdomain **snaprivo.com**, zusätzlich snaprivo.de. Bundle-ID und interne Speicherpfade bleiben stabil; vorhandene Projekte werden nicht umgezogen. Kopieren erhält eine dezente Erfolgsbestätigung direkt am Button, mit Berücksichtigung reduzierter Bewegung.


### Handgezeichnete Markierungen – Ergänzung vom 16. Oktober 2026

Auf Nutzerwunsch erhalten Pfeile und Kreise/Ellipsen einen umschaltbaren Zeichenstil „Präzise / Handgezeichnet“. Referenz ist die gezeigte handmarkierte Anmutung: geschwungener Pfeil mit offener Spitze und leicht unregelmäßiger, offener Kreis. Objekte bleiben geometrisch bearbeitbar; vorhandene Projekte behalten zunächst ihre präzise Darstellung. Stil, Undo, eigene Vorlagen und alle Bildausgaben verwenden denselben gespeicherten Zustand. Keine Schriftänderung, kein Freihand-Eingabewerkzeug und keine Änderung anderer Formen in diesem Umfang. [Umsetzung und Nachweise](HANDGEZEICHNET-ABNAHME.md).

## Autorisierte Komforterweiterung – 16. Oktober 2026

Auf Nutzerwunsch wurden Anheften, Mehrfachauswahl/Gruppen, Bildpipette/Pixellupe, eingefügte Bildobjekte, JPEG/einseitiges Bild-PDF, verbesserte manuelle Scroll-Aufnahme und Ausgabe-Gestaltung umgesetzt. Bedienumfang und Grenzen sind im README und in [KOMFORTFUNKTIONEN-ABNAHME.md](KOMFORTFUNKTIONEN-ABNAHME.md) dokumentiert. Dies legt keine neue Kaufpaket-Zuordnung fest. Scroll-Automatik ergänzt stabile Abschnitte, steuert jedoch nicht das Scrollen fremder Apps. Die breite Website-/Hardwareabnahme P01 und Release-Abnahmen bleiben offen. Dokumentformat 9 erhält Gruppen und separate Bildassets; Domain bleibt frei von AppKit/Capture-Frameworks.

## Einstieg – 16. Oktober 2026

Autorisiert und implementiert: überspringbare dreistufige Einführung mit lokalen Illustrationen für Aufnahme, Annotation und Ausgabe; native Tastaturbedienung und reduzierte Bewegung. Keine automatische Aufnahme oder Berechtigungsanforderung durch Anzeigen/Weiterblättern. Der explizite Abschluss „Erste Aufnahme starten“ verwendet nach Schließen der Einführung den bestehenden CaptureLauncher. Einführung und kontextabhängige Editorhinweise sind über Hilfe erneut erreichbar; Abschluss und quittierte Hinweise werden lokal in App-Einstellungen gespeichert. Bestehende Projekte bleiben unverändert.

## Kompakte Editoraktionen – 16. Oktober 2026

Nutzerentscheidung: vier direkte Bildaktionen (Kopieren, Speichern, Texterkennung, Teilen), weitere in „Mehr“. Pipette und Bild einfügen stehen bei den Werkzeugen. Die einzeilige Leiste reserviert bei schmalen Fenstern weniger direkte Aktionen zugunsten der Werkzeuge. Individuelle Reihenfolge und Sichtbarkeit bleiben einstellbar; alte unberührte Standardreihenfolgen werden auf die neue Reihenfolge überführt.

**Kompakter Editorfuß:** Der kontextabhängige Bedienhinweis steht zwischen Zoom und Verlauf in der unteren Bedienleiste. Bei wenig Platz ersetzt ihn ein Info-Button mit Tooltip und per Klick/Tastatur erreichbarer Erklärung. Darunter stehen Bildname und Pixelmaße mit reduzierten Abständen. Export-/Öffnen-Status und Rückmeldungen erhalten nur bei Bedarf eine eigene sichtbare Zeile; Speichermeldungen und Fehlerdialoge bleiben erhalten.

### Bild/Video-Einstieg und vierstufiges Onboarding

Auswahlleiste mit zwei direkten Buttons „Foto“ und „Video“, ohne Umschalter und ohne zusätzlichen Aufnahmebutton. Foto übernimmt den Ausschnitt direkt; Video startet direkt mit gespeichertem Systemton/Mikrofon aus Einstellungen → Aufnahme und dem eingestellten Vorlauf. Beide Aktionen sind größer und blau. Scroll-Aufnahmen bieten nur die Foto-Aktion. Video-Direktbutton im Hauptfenster. Einführung in vier Schritten: Aufnahmeart und Berechtigungen, Markieren, Ausgabe, optionales Screenshot-Kürzel mit bestehender Konfliktprüfung und globaler Verfügbarkeit. Bereits abgeschlossene Einführungen werden nicht ungefragt erneut angezeigt.

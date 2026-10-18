# Werkzeugleiste, Einstellungen und eigene Aufnahmekürzel

Stand: 12. Oktober 2026. U01 wurde auf Nutzerwunsch vor E03 eingeschoben. macOS 26 bleibt die Mindestversion; der Build verwendet unverändert das Xcode-Projekt, die Sandbox und die bestehende Apple-Development-Identität.

## Bedienung und gespeicherte Vorgaben

**Einstellungen … / ⌘,** öffnet sechs native Einstellungsbereiche mit Symbolen und Beschriftungen.

| Bereich | Tatsächlich verfügbare Funktionen |
| --- | --- |
| Allgemein | Darstellung System/Hell/Dunkel, automatisches Kopieren neuer Screenshots, Information zur lokalen Speicherung und Version |
| Symbolleiste | Symbolgröße Kompakt/Standard/Groß, Reihenfolge von Werkzeugen und Bildaktionen per Ziehen/Pfeilbuttons ändern, per Auge ein-/ausblenden, alle einblenden, Standardreihenfolge wiederherstellen |
| Speicherorte | PNG-Standardordner und Projektbibliothek getrennt wählen; geprüfte Übernahme vorhandener Projekte samt Papierkorb |
| Aufnahme | Standardvorlauf keine/3/5 Sekunden, Mauszeigeraufnahme, zusätzliches automatisches PNG-Kopieren nach Screenshots |
| Tastenkürzel | Vier Aufnahmeaktionen, eigene Belegung aufzeichnen, entfernen, Standard wiederherstellen, globale Auslösung abschalten, fehlgeschlagene Registrierung erneut prüfen |
| Datenschutz | Aktuellen Bildschirmzugriff anzeigen/prüfen, Systemeinstellungen öffnen, Umgang mit lokalen Originalen erklären |

Vorgabe für neue Installationen ist seit 14.10.2026 **Standard**; bereits gespeicherte Größen bleiben erhalten. Werkzeugflächen ohne den zusätzlichen Platz für „Zuschneiden“:

| Größe | Fläche je Werkzeug | Symbol |
| --- | --- | --- |
| Kompakt | 54 × 42 pt | 16 pt |
| Standard | 66 × 52 pt | 20 pt |
| Groß | 78 × 64 pt | 24 pt |

Die gemeinsame Leiste nutzt die gesamte Editorbreite über Canvas und Inspektor. Bei knapper Breite scrollen die Werkzeuge horizontal; Bildaktionen bleiben rechts erreichbar. Eine bewusste Größenänderung gilt sofort; normale Werkzeugwechsel verschieben die Bildfläche weiterhin nicht. Symbolgröße und Reihenfolge sind unter Symbolleiste einstellbar.

Die vier Vorgaben werden separat in den App-Einstellungen gespeichert und beim Start wieder geladen. Direkte Aufnahmen und Aufnahmeoptionen verwenden denselben Standardvorlauf und dieselbe Cursoroption. Der ausdrücklich benannte 3-Sekunden-Befehl überschreibt den Standard nur für seinen Auftrag. Neue Screenshots öffnen weiterhin im Editor und werden als bearbeitbare Projekte gesichert; optional wird zusätzlich PNG kopiert. Bildimporte lösen dieses automatische Kopieren nicht aus. Automatisches Kopieren ist zunächst ausgeschaltet.

Es gibt noch keine Ausgabeformatwahl für JPEG/PDF, konfigurierbaren Fensterhintergrund, automatische PNG-Ablage in einem festen Ordner, Autostart oder Scroll-Parameter. Dafür stehen keine funktionslosen Schalter in den Einstellungen. Diese Funktionen brauchen jeweils einen vollständigen Ablauf; zusätzliche Ausgabeformate stehen unter I04, Scroll-Aufnahmen unter T01/P01.

## Kürzel-Recorder

Die Standardbelegungen sind ⌃⇧2 für Neue Aufnahme, ⌃⇧1 für Bildschirm, ⌃⇧5 für drei Sekunden Vorlauf und ⌃⇧3 als alternatives Kürzel derselben automatischen Auswahl. Die ersten drei Menübefehle folgen ihrer eingestellten Belegung; das frühere zusätzliche app-interne ⇧⌘2 entfällt.

- Auf ein Kürzel klicken und eine Kombination mit ⌘, ⌥ oder ⌃ eingeben. Umschalt allein reicht nicht; einfache Buchstaben bleiben für die Texteingabe frei.
- Während der Aufzeichnung sind die eigenen globalen Kürzel vorübergehend abgemeldet. Die Eingabe löst keine Aufnahme und keinen Editor-/Menübefehl aus.
- Escape bricht ab und behält die bisherige Belegung. Tab beendet die Aufzeichnung und setzt die normale Fokusnavigation fort. Unmodifizierter Rückschritt oder die Entfernen-Schaltfläche löscht die Belegung.
- Wechsel der Registerkarte, Verlust des Fensterschlüsselfokus, Schließen oder Entfernen des Recorders beendet die Aufzeichnung und stellt die Registrierungen wieder her.
- Doppelte Belegungen und geschützte Editor-/Systembefehle werden abgelehnt. Ein globaler Registrierungskonflikt ersetzt das bisherige Kürzel nicht. Bei bereits gespeicherten, inzwischen nicht verfügbaren Kürzeln erscheint ein Hinweis je Aktion samt erneuter Prüfung.
- Belegungen bleiben nach Neustart erhalten. Beschädigte oder nicht unterstützte Einstellungsdaten werden gemeldet; beim Laden erfolgt kein stilles Überschreiben.

Globale Kürzel verwenden ausschließlich öffentliche HIToolbox-Registrierungen mit exklusiver Belegung. Hardware-Tastencodes bleiben gespeichert, die Beschriftung und die geschützten Editorbefehle folgen dem aktuellen Tastaturlayout, einschließlich Z/Y auf deutschen Tastaturen. Der Recorder verwendet nur während der bewussten Aufzeichnung einen app-lokalen Monitor; keine globale Tastenüberwachung und keine zusätzliche TCC-Freigabe. API-Referenzen: [lokaler NSEvent-Monitor](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents%28matching%3Ahandler%3A%29), [UCKeyTranslate](https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate).

## Automatisierte Nachweise

Erfolgreich ausgeführt:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-settings.sh
```

Regulär signierter Build erfolgreich; 47 Domain-Tests erfolgreich. `test-settings.sh` kompiliert und prüft die tatsächlichen App-Typen mit eigenen temporären Defaults und synthetischen Bildern:

- Werkzeug-/Aufnahmevorgaben nach erneutem Laden, gemeinsame Konfiguration für alle Aufnahmeaktionen und ausdrückliche 3-Sekunden-Ausnahme.
- Ungültige Kombinationen, layoutabhängiges ⌘Z/⇧⌘Z, doppelte Belegung, fehlgeschlagene Registrierung ohne Verlust oder Speicherung des alten Kürzels, Entfernen, Zurücksetzen, globale Deaktivierung und erneute Registrierung.
- Gespeicherte und gelöschte Belegungen nach erneutem Laden; beschädigte Einstellungsdaten bleiben unverändert und führen zu einer Meldung.
- Native Recorder-Ereignisse: geschütztes ⌘Q wird konsumiert, Escape/Tab/Rückschritt und Entfernen des Views beenden die Aufzeichnung korrekt. Capture-Callbacks bleiben währenddessen ausgesetzt.
- Echte öffentliche macOS-Registrierung: zwei unabhängige Registrierer konkurrieren um dieselbe seltene Kombination. Der zweite schlägt fehl und kann nach Freigabe durch den ersten erfolgreich registrieren.
- Neue Screenshots werden bei aktivierter Vorgabe tatsächlich als PNG kopiert; Bildimporte und deaktivierte Vorgaben kopieren nicht. Dieser Test verwendet ausschließlich eine eigene private Test-Zwischenablage und temporäre Bibliothek.

## Bedienprüfung im signierten Build

Auf dem vorhandenen Mac mit macOS 27, Xcode 27 und deutschem Tastaturlayout:

- Alle vier nativen Einstellungsbereiche geöffnet; keine abgeschnittenen Einstellungszeilen. Bildschirmfreigabe wurde korrekt als vorhanden angezeigt und erneut geprüft, ohne TCC-Einstellungen zu ändern.
- Alle drei Werkzeuggrößen gewählt, Vorschau verändert sich sofort. Die größere Standardleiste am synthetischen Projekt „SnagForge-Crop-Abnahme“ geprüft: alle acht Werkzeuge sichtbar und zur Bildfläche zentriert.
- Standardgröße, fünf Sekunden Vorlauf, Mauszeiger und zusätzliches Kopieren gewählt; App beendet und aktuellen Build erneut geöffnet. Alle Werte waren erhalten. Danach Größe Groß, kein Vorlauf und ausgeschaltete Cursor-/Kopieroption wiederhergestellt.
- Eigenes ⌃⌥⇧R für Neue Aufnahme aufgezeichnet und nach App-Neustart wieder angezeigt. Das Kürzel startete die eingefrorene gemeinsame Fenster-/Bereichsauswahl. Escape brach ohne neues Projekt ab; Bibliothek blieb bei 24 Projekten.
- Doppelte Belegung ⌃⇧1 sowie ⌘Z abgelehnt. Escape behielt das zuvor gewählte Kürzel. Alternative Belegung entfernt und anschließend alle Standardbelegungen wiederhergestellt.
- Bestehende Nutzeraufnahmen wurden nicht verändert. Der Aufnahmetest wurde abgebrochen, automatisches Kopieren nur in der isolierten Prüfung tatsächlich ausgeführt.

## Noch offene Abnahmen

- Weitere eigene Belegungen auf verschiedenen Geräten physisch prüfen. Die globale Auslösung von „Neue Aufnahme“ aus einer anderen App wurde am 13.10.2026 vom Nutzer bestätigt; ebenfalls bestätigt wurde freies Aufziehen trotz Fenstervorschau. Der gemeldete Cursorwechsel an Menüleiste/Dock wurde anschließend korrigiert und mit simuliertem Cursorreset getestet. Eine erneute physische Prüfung genau dieses Randfalls ist noch offen und bleibt Q01.
- macOS 26, weitere Tastaturlayouts und Konflikte mit tatsächlich laufenden Fremdprogrammen auf anderen Macs.
- VoiceOver, vollständige Tastaturnavigation, Hell/Dunkel, höherer Kontrast und reduzierte Transparenz nach Q03. Vorhandene Accessibility-Labels sind kein Ersatz für diese Abnahme.

E03 Bildauflösung ändern wurde in diesem Schritt nicht begonnen. Die Reihenfolge und Restarbeit stehen im [Arbeitsplan](ARBEITSPLAN.md).


Nachtrag 13.10.2026: S02 abgeschlossen; S03 ergänzt einmalige explizite Berechtigungsabfrage, Rückkehr-/Neustartführung und den dauerhaft gespeicherten Erstaufnahmezustand. [Nachweise und Testgrenzen](PORTABILITAET-DATENSCHUTZ-ABNAHME.md).


Nachtrag 14.10.2026 (U02): Speicherorte und manuelle Darstellung ergänzt. Die obige physische Bedienprüfung dokumentiert den älteren U01-Stand; neue automatisierte Nachweise und noch offene echte Sandbox-Neustartprüfung stehen unter [Speicherorte und Darstellung](SPEICHERORTE-DARSTELLUNG-ABNAHME.md).


Nachtrag 14.10.2026: Automatisches Kopieren und Symbolreihenfolge

- Die gespeicherte Kopieroption ist unter Allgemein und Aufnahme, in den Aufnahmeoptionen sowie per Rechtsklick auf die Editorleiste erreichbar. Neue Screenshots einschließlich Scroll-Aufnahmen werden ohne weiteren Klick als PNG kopiert. Ein Speicherfehler des bisherigen Editors unterdrückt das Kopieren des neuen Bildes nicht. Bildimporte und die ausgeschaltete Vorgabe verändern die Zwischenablage nicht automatisch.
- Unter Symbolleiste und im Editor über Rechtsklick → Symbole anordnen … lassen sich Werkzeuge und Bildaktionen innerhalb ihrer Gruppen per nativem [List-onMove](https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove%28perform%3A%29) oder Pfeilbuttons umsortieren. Die Reihenfolge gilt sofort und bleibt gespeichert. Die Rücksetzung betrifft nur die Reihenfolge. Neue/fehlende Symbole werden beim Laden angehängt; unbekannte und doppelte Einträge werden gefiltert.
- Erneut erfolgreich: regulär signierter `./scripts/build.sh`, alle 87 Domain-Tests mit `./scripts/test.sh` und `./scripts/test-settings.sh`. Zusätzliche Prüfungen decken beide Verschieberichtungen bis an die Grenzen, gespeicherte Reihenfolge nach erneutem Laden, Reparatur unvollständiger/duplizierter Einträge, Rücksetzung und tatsächliche PNG-Pixel in einer privaten Test-Zwischenablage bei einem absichtlich blockierten vorherigen Projekt ab.
- Allgemein und die Sortierliste wurden zusätzlich in einer isolierten nativen NSHostingView-Vorschau mit temporären Einstellungen gerendert und visuell geprüft. Die Bildaktionen stehen zuerst; ihre Beschriftungen und Verschiebepfeile sind sichtbar. Die echte Screenshot-/TCC-Abnahme, physisches Ziehen im signierten Hauptprogramm und die vollständige VoiceOver-/Tastaturabnahme bleiben separat zu prüfen. Es wurden keine Nutzeraufnahmen für die automatisierten Prüfungen verwendet.


Nachtrag 14.10.2026: Sichtbarkeit einzelner Symbole

- Vor jedem Eintrag steht ein Augenschalter mit eigenem Accessibility-Namen und Sichtbarkeitswert. „eye“ zeigt ein eingeblendetes, „eye.slash“ ein ausgeblendetes Symbol an. Titel und Symbol ausgeblendeter Einträge erscheinen sekundär; die Einträge bleiben sortierbar und jederzeit wieder einblendbar.
- Sichtbarkeit und Reihenfolge werden getrennt gespeichert. „Alle einblenden“ verändert die Reihenfolge nicht; „Standardreihenfolge wiederherstellen“ verändert die Sichtbarkeit nicht. Neue Symbole sind standardmäßig sichtbar. Unbekannte und doppelte gespeicherte Werte beeinflussen keine anderen Symbole.
- Ausgeblendete Symbole hinterlassen keine leeren Gruppen oder Trennstriche. Beim Ausblenden des aktiven Werkzeugs wird die Bearbeitung abgeschlossen und zur Auswahl gewechselt. Falls sämtliche Symbole ausgeblendet sind, bleibt „Symbole einblenden …“ erreichbar. Die Menübefehle bleiben verfügbar.
- Erneut erfolgreich: signierter `./scripts/build.sh`, alle 87 Domain-Tests und `./scripts/test-settings.sh`. Letzteres ergänzt Prüfungen für Aus-/Einblenden, Neu-Laden, Umsortieren ausgeblendeter Symbole und Rückkehr an ihre Position, vollständig ausgeblendete Gruppen, unabhängige Rücksetzung und ungültige gespeicherte Werte. Die Augenschalter wurden bei 540 pt Dialogbreite mit eingeblendeten und ausgeblendeten Einträgen in der isolierten nativen Vorschau visuell geprüft. Die echte Bedien-/VoiceOver-Abnahme im signierten Hauptprogramm bleibt separat.


Nachtrag 14.10.2026: Kleinere Startgrößen

- Neue Installationen verwenden Symbolgröße Standard (20-pt-Symbole, 52-pt-Werkzeughöhe). Vorhandene Einstellungen, einschließlich Groß, bleiben erhalten. Die isolierte Einstellungsprüfung prüft sowohl die neue Vorgabe als auch das erneute Laden einer ausdrücklich gewählten Größe Groß.
- Neue Pfeile starten mit fester Stärke 15 Bildpixel. Dies ist auch für kleine Screenshots wie 442 × 444 px die Vorgabe; keine automatische Anpassung an die Bildgröße. Regleränderungen setzen weiterhin den Startwert für weitere Pfeile im geöffneten Editor. Gespeicherte Pfeile werden nicht verändert.

- Erfolgreich geprüft: signierter `./scripts/build.sh`, `./scripts/test-settings.sh`, die bestehenden Canvas-/Pfeil-/Exportprüfungen über `./scripts/test-canvas.sh` und alle 87 Domain-Tests über `./scripts/test.sh`.

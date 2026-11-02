# Aufnahmemenü und Tastenkürzel

Stand: 2. November 2026. Produktname Snaprivo. Die bereitgestellte Snagit-Aufnahme ist Referenz für den gemeinsamen Auswahlablauf; die frühere Shottr-Referenz diente der Menügruppierung.

Menüleisten-Icon und App-Menü **Aufnahme** verwenden denselben Baustein:

| Befehl | Standardkürzel | Verhalten |
| --- | --- | --- |
| Neue Aufnahme | ⌃⇧2 innerhalb der App und global | Direkt zur gemeinsamen Auswahl: Fenster per Klick markieren oder freien Bereich ziehen. |
| Letzten Bereich erneut aufnehmen | ⌃⇧6 | Den zuletzt bestätigten Bereich erneut aufnehmen. Ohne vorherigen Bereich deaktiviert. |
| Sofort aufnehmen (ohne Leiste) | ⌃⇧4 | Dieselbe Auswahl; Loslassen bzw. Fensterklick nimmt direkt auf, ⌥ beim Loslassen zeigt die Leiste (seit 2. November 2026). |
| Text direkt erfassen | ⌃⇧7 | Bereich auswählen und Text erkennen. |
| QR-Code scannen | ⌃⇧8 | Bereich auswählen und QR-Code erkennen. |
| Bildschirm aufnehmen | ⌃⇧1 | Display anklicken, anschließend bestätigen. |
| Aufnahme mit 3 Sekunden Vorlauf | ⌃⇧5 | Drei Sekunden warten, dann dieselbe gemeinsame Auswahl. |
| Scroll-Aufnahme … | zunächst unbelegt | Bereich für eine Scroll-Aufnahme wählen. |
| Video: Bereich aufnehmen … | zunächst unbelegt | Bereich mit Videooptionen und ausdrücklichem REC-Start wählen. |
| Video: Bildschirm aufnehmen … | zunächst unbelegt | Bildschirm mit Videooptionen und ausdrücklichem REC-Start wählen. |
| Video: Fenster aufnehmen … | zunächst unbelegt | Fenster mit Videooptionen und ausdrücklichem REC-Start wählen. |
| Aufnahmeoptionen … | — | Getrennte Optionen für Vorlauf und Mauszeigeraufnahme. Keine Quellwahl zwischen Fenster und Bereich. |

Die Hauptsymbolleiste startet über **Neue Aufnahme** denselben Coordinator. ⌃⇧3 bleibt als alternatives globales Kürzel erhalten und startet ebenfalls die automatische Fenster-/Bereichsauswahl. Es gibt keine doppelte Fenster-/Bereichsbefehlsgruppe im Menü.

Vor der Auswahl wird der Bildschirm mit ScreenCaptureKit als Standbild erfasst. Die deckende Auswahloberfläche verhindert Klicks und Ziehen auf den darunterliegenden echten Fenstern. Nach Klick oder Ziehen bleibt die Auswahl stehen. An der Rahmenkante ziehen verschiebt sie, acht Griffe ändern ihre Größe. Ziehen innerhalb der Fläche startet eine neue freie Auswahl, auch nach einem Fensterklick. Die kleine Leiste zeigt Pixelmaße und bietet **Aufnehmen**, **Neu auswählen** und **Abbrechen**. Enter bestätigt den Ausschnitt, Escape bricht ab. Erst die Bestätigung erzeugt ein Bibliotheksprojekt aus den eingefrorenen Pixeln. Die Fensterwahl verwendet den sichtbaren rechteckigen Ausschnitt dieses Standbilds.

⌃ bedeutet Control, ⇧ bedeutet Umschalt. Die globalen Kürzel verwenden den öffentlichen HIToolbox-Aufruf `RegisterEventHotKey`. Kein Event-Tap und keine zusätzliche Eingabeüberwachungs-/Bedienungshilfenfreigabe. Unter **Einstellungen → Tastenkürzel** sind alle elf Menü-Aufnahmestarts und die alternative Foto-Belegung frei aufzeichnbar, entfernbar und zurücksetzbar. Menü und Einstellungen verwenden dieselbe Aktionsliste. Die bisherigen acht Vorgaben bleiben erhalten; Scrollen und die drei Videoquellen beginnen ohne Belegung. Shortcutformat 5 übernimmt individuelle und entfernte Belegungen aus Versionen 1–4. Doppelte Kürzel, reservierte Editor-/Systembefehle sowie fehlgeschlagene globale Registrierungen werden vor dem Speichern abgelehnt. Die Aufzeichnung pausiert die eigenen globalen Kürzel; Escape, Tab oder Verlassen des Fensters beendet sie. Die globale Auslösung lässt sich separat abschalten. Menübefehle bleiben anklickbar und folgen der gewählten Belegung; das bisherige zusätzliche ⇧⌘2 entfällt. Labels und geschützte Editorbefehle berücksichtigen das aktuelle Tastaturlayout. [Bedienung und Abnahme](EINSTELLUNGEN-ABNAHME.md). macOS' Screenshot-Kürzel ⇧⌘3/4/5 bleiben unverändert.

Bei vorhandener Freigabe öffnet Neue Aufnahme kein Konfigurationsfenster. Fehlende Freigabe führt zur Erklärung und ausdrücklichen Systemanfrage; Fehler öffnen die sichtbare Meldung. Direkte Fotoaktionen verwenden Bildmodus, Videoaktionen Videomodus mit ihrer passenden Quelle. Gespeicherter Standardvorlauf und Cursoroption werden übernommen. Nur der ausdrücklich benannte 3-Sekunden-Befehl setzt für diesen Auftrag drei Sekunden. Vorlauf und Mauszeiger lassen sich in den Aufnahmeoptionen und in Einstellungen → Aufnahme dauerhaft ändern. Während laufender Auswahl oder Projektöffnung sind weitere Starts gesperrt. Die Aufnahmeoptionen sind ausdrücklich getrennt vom sofortigen Start.

## Aktuelle Kürzel-Abnahme

2. November 2026: Build und Einstellungsprüfungen einschließlich Migration 1–4, neuer Video-/Scroll-Aktionen, Konflikten, Neustart und Entfernen bestanden. Native deutsche Kürzelliste und sofortiger Abgleich einer zugewiesenen Video-Kombination mit dem Menü bestätigt. [Nachweise und verbleibende Hardwaregrenzen](BESTOF-ABNAHME.md#vollständige-aufnahmekürzel-und-ausgabeinfo).

## Frühere Kürzel-Abnahme (12. Oktober 2026)

Signierter Build, 47 Domain-Tests und `test-settings.sh` erfolgreich. Im laufenden Build eigenes ⌃⌥⇧R aufgezeichnet, nach Neustart wieder geladen und damit die automatische Aufnahmeauswahl gestartet; Escape brach ohne neues Projekt ab. Doppelte Belegung, reserviertes ⌘Z, Entfernen und Zurücksetzen geprüft. Exklusive Registrierungskonflikte sind zusätzlich über die echte öffentliche macOS-API automatisiert geprüft. Der globale physische Tastaturtest aus einer anderen App bleibt offen.

## Vorherige Capture-Verifikation

Die folgenden Tests stammen aus dem Stand vor konfigurierbaren Kürzeln; dort wurde noch das damalige app-interne ⇧⌘2 verwendet.

- Normaler Xcode-Debugbuild mit Apple-Development-Signatur erfolgreich.
- 26 Domain-Tests einschließlich Verschieben, acht Resize-Griffen, Mindestgröße, Displaybegrenzung und Übergang von Fenster zu Ausschnitt erfolgreich.
- Offscreen-AppKit-Tests: deckende Pixel auch innerhalb der Auswahl, unveränderliche Retina-Ausschnitte, Bildorientierung, Displayvalidierung, Cursorzuordnung, Klick/Drag, fehlendes Zwischenereignis, Hover-Isolation, neue Auswahl innerhalb eines markierten Fensters, Live-Vorschau, Verschieben/Resize und native Schaltflächen erfolgreich.
- Laufender Standbild-Build: Neue Aufnahme zeigt die eingefrorene Desktopansicht. Fensterklick, dann Ziehen über der fremden Titelleiste erzeugt einen freien Bereich. Ein Ausschnitt mit 200 × 138 Pixeln öffnet im Editor und ist nach Neustart in der Bibliothek. Im abschließenden Cursor-Build nochmals ⇧⌘2, Fensterklick, freie Auswahl 280 × 170 Pixel über der Titelleiste und Escape geprüft; Bibliothek danach unverändert mit 14 Projekten.
- App-internes ⇧⌘2 startet ebenfalls die automatische Auswahl. Die separate Statusmenübedienung und physische globale Kürzel bleiben offen. Der Nutzer hatte den globalen Hardwaretest zurückgestellt.
- Die Bestätigung eines freien Standbild-Ausschnitts bis zum Editor ist nachgewiesen. Die separate unabhängige Fensteraufnahme gehört nicht mehr zu diesem Ablauf. Einzelheiten in SCREENSHOT-ABNAHME.md.

## Nächster Schritt: Scroll-Aufnahme

Noch nicht implementiert. Geplant: Bereich wählen, selbst vertikal scrollen, überlappende Abschnitte lokal zusammenfügen, Vorschau prüfen und das lange Bild im Editor öffnen. Unsichere Überlappungen, Sticky Header und Größenlimits brauchen erkennbare Behandlung. Automatisches Scrollen fremder Apps bleibt ein separates Vorhaben mit Sandbox-Prüfung. Kein funktionsloser Scroll-Befehl im aktuellen Menü.

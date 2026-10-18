# Aufnahmemenü und Tastenkürzel

Stand: 12. Oktober 2026. Arbeitsname bleibt SnagForge. Die bereitgestellte Snagit-Aufnahme ist Referenz für den gemeinsamen Auswahlablauf; die frühere Shottr-Referenz diente der Menügruppierung.

Menüleisten-Icon und App-Menü **Aufnahme** verwenden denselben Baustein:

| Befehl | Standardkürzel | Verhalten |
| --- | --- | --- |
| Neue Aufnahme | ⌃⇧2 innerhalb der App und global | Direkt zur gemeinsamen Auswahl: Fenster per Klick markieren oder freien Bereich ziehen. |
| Bildschirm aufnehmen | ⌃⇧1 | Display anklicken, anschließend bestätigen. |
| Aufnahme mit 3 Sekunden Vorlauf | ⌃⇧5 | Drei Sekunden warten, dann dieselbe gemeinsame Auswahl. |
| Aufnahmeoptionen … | — | Getrennte Optionen für Vorlauf und Mauszeigeraufnahme. Keine Quellwahl zwischen Fenster und Bereich. |

Die Hauptsymbolleiste startet über **Neue Aufnahme** denselben Coordinator. ⌃⇧3 bleibt als alternatives globales Kürzel erhalten und startet ebenfalls die automatische Fenster-/Bereichsauswahl. Es gibt keine doppelte Fenster-/Bereichsbefehlsgruppe im Menü.

Vor der Auswahl wird der Bildschirm mit ScreenCaptureKit als Standbild erfasst. Die deckende Auswahloberfläche verhindert Klicks und Ziehen auf den darunterliegenden echten Fenstern. Nach Klick oder Ziehen bleibt die Auswahl stehen. An der Rahmenkante ziehen verschiebt sie, acht Griffe ändern ihre Größe. Ziehen innerhalb der Fläche startet eine neue freie Auswahl, auch nach einem Fensterklick. Die kleine Leiste zeigt Pixelmaße und bietet **Aufnehmen**, **Neu auswählen** und **Abbrechen**. Enter bestätigt den Ausschnitt, Escape bricht ab. Erst die Bestätigung erzeugt ein Bibliotheksprojekt aus den eingefrorenen Pixeln. Die Fensterwahl verwendet den sichtbaren rechteckigen Ausschnitt dieses Standbilds.

⌃ bedeutet Control, ⇧ bedeutet Umschalt. Die vier globalen Kürzel verwenden den öffentlichen HIToolbox-Aufruf `RegisterEventHotKey`. Kein Event-Tap und keine zusätzliche Eingabeüberwachungs-/Bedienungshilfenfreigabe. Unter **Einstellungen → Tastenkürzel** sind alle vier Belegungen frei aufzeichnbar, entfernbar und zurücksetzbar. Doppelte Kürzel, reservierte Editor-/Systembefehle sowie fehlgeschlagene globale Registrierungen werden vor dem Speichern abgelehnt. Die Aufzeichnung pausiert die eigenen globalen Kürzel; Escape, Tab oder Verlassen des Fensters beendet sie. Die globale Auslösung lässt sich separat abschalten. Menübefehle bleiben anklickbar und folgen der gewählten Belegung; das bisherige zusätzliche ⇧⌘2 entfällt. Labels und geschützte Editorbefehle berücksichtigen das aktuelle Tastaturlayout. [Bedienung und Abnahme](EINSTELLUNGEN-ABNAHME.md). macOS' Screenshot-Kürzel ⇧⌘3/4/5 bleiben unverändert.

Bei vorhandener Freigabe öffnet Neue Aufnahme kein Konfigurationsfenster. Fehlende Freigabe führt zur Erklärung und ausdrücklichen Systemanfrage; Fehler öffnen die sichtbare Meldung. Alle direkten Aktionen verwenden Bildmodus, passende Quelle sowie den gespeicherten Standardvorlauf und die Cursoroption. Nur der ausdrücklich benannte 3-Sekunden-Befehl setzt für diesen Auftrag drei Sekunden. Vorlauf und Mauszeiger lassen sich in den Aufnahmeoptionen und in Einstellungen → Aufnahme dauerhaft ändern. Während laufender Auswahl oder Projektöffnung sind weitere Starts gesperrt. Die Aufnahmeoptionen sind ausdrücklich getrennt vom sofortigen Start.

## Aktuelle Kürzel-Abnahme

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

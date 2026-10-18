# P02 – Eigene Werkzeugstile

Stand: 15. Oktober 2026. Eigene Stile sind im Eigenschaftenbereich des Bildeditors implementiert. Die übrigen Ton- und Synchronitätstests bleiben auf Nutzerwunsch für später vorgemerkt; sie sind keine Voraussetzung für diesen unabhängigen Schritt.

## Bedienung

1. Ein Werkzeug oder ein vorhandenes Objekt auswählen und dessen Eigenschaften einstellen.
2. Rechts **Eigene Stile → Aktuellen Stil speichern …** öffnen, Namen eingeben und **Speichern** wählen. Namen haben bis zu 80 Zeichen und sind innerhalb einer Werkzeuggruppe eindeutig; Groß-/Kleinschreibung und Akzente unterscheiden keine zwei Namen. Bis zu 100 eigene Stile insgesamt.
3. **Eigene Stile** zeigt die zum aktuellen Werkzeug bzw. ausgewählten Objekt passenden Vorlagen. Anklicken übernimmt ihre Darstellung. Formen teilen eine Gruppe, die konkrete Form bleibt erhalten; ein Eckenradius wird nur aus einem Rechteckstil übernommen und nur auf Rechtecke angewendet.
4. **Stile verwalten …** zeigt alle eigenen Vorlagen mit Werkzeuggruppe. Umbenennen erhält die Vorlage; Löschen verlangt eine Bestätigung. Bereits gestaltete Objekte bleiben in beiden Fällen erhalten. Ohne ausgewähltes Objekt lassen sich Vorlagen weiterhin verwalten.

Bei Auswahl eines vorhandenen Objekts ist Anwenden ein gemeinsamer Undo-Schritt; bei identischer Darstellung entsteht keine neue Änderung. Während einer laufenden Zeichengeste, eines Zuschnitts oder des Bildgrößendialogs wird kein Stil angewendet. Eine laufende Texteingabe wird vor dem separaten Stil-Schritt abgeschlossen. Ohne Auswahl werden die Vorgaben für neue Objekte aktualisiert, ohne das Dokument zu ändern.

## Übernommene Eigenschaften

| Werkzeuggruppe | Inhalt der Vorlage | Erhalten bleibt |
| --- | --- | --- |
| Pfeil | Farbe, Stärke | Anfang, Ende, Objekt-ID |
| Text | Farbe, Schriftfamilie, Größe, Gewicht, Kursiv, Ausrichtung | Text, Position, Textfeldmaße |
| Formen | Konturfarbe, Linienbreite/-muster, Rand, Füllfarbe/-deckkraft, Rechteck-Eckenradius | Formart, Position, Abmessungen |
| Callout | Farbe, Konturstärke, Schrift, Füllung | Text, Rahmen, unabhängige Zeigerspitze |
| Unschärfe | Radius | Bereich und Bildinhalt |
| Abdecken | Deckfarbe | Bereich und vollständige Deckung |
| Markieren | Farbe, Breite, Deckkraft | Rechteck-/Freihandmodus und alle Pfadpunkte |
| Liste | Farbe, Form, Textfarbe, Größe | Mittelpunkt, Nummerierungsart und bestehender Zahlen-/Buchstabenwert |

Stile speichern keine Bilddaten, Objekttexte, Koordinaten, Freihandpfade oder Schrittnummern. Fehlende Schriftfamilien verwenden den bestehenden nativen Schrift-Rückfall. PNG, Zwischenablage und Projektdateien nutzen die übernommenen Objekte über den bisherigen Renderer; es gibt keine neue Render-Pipeline.

## Speicherung und Fehler

Die kleine, auf 100 Vorlagen begrenzte Stilbibliothek liegt versioniert in den lokalen App-Einstellungen (`editor.savedStyles.v1`). Ihre Namen und Stile werden vor dem Schreiben validiert; ungültige Namen, doppelte Namen oder beschädigte Eigenschaften verändern die bestehende Bibliothek nicht. Zusätzlich begrenzte UTF-8-Namen und Schriftfamilien halten die Datenmenge beschränkt. Beschädigte bzw. unbekannte neuere gespeicherte Daten bleiben unverändert erhalten; eine sichtbare Fehlermeldung verhindert stilles Überschreiben.

Vorlagen sind appweit für Bildprojekte verfügbar. Sie gehören derzeit zu den lokalen Einstellungen und sind nicht Bestandteil von Projektpaketen oder Bibliotheksbackups. Angewendete Eigenschaften dagegen liegen vollständig in den Objekten: Sie überstehen Projekt-Export, Autosave und Wiederöffnen unabhängig von der Vorlage. Keine neue Projektformat-Version; Format 6 bleibt unverändert. Keine neuen Abhängigkeiten oder Berechtigungen.

## Nachweise

- Signierter Debug-Build für macOS 26 mit aktiver Sandbox erfolgreich; aktuelle Testumgebung macOS 27/M1 Pro.
- `./scripts/test.sh`: 94 Domain-Tests bestanden. Sechs neue Prüffälle decken alle Werkzeuggruppen, formübergreifende Anwendung, erhaltene Inhalte/IDs/Geometrie, Freihandpfade, Schrittnummern/Mittelpunkte, Codable-Roundtrip, Namensgrenzen, eindeutige Namen, atomare Änderungen und die Ablehnung neuerer Datenformate ab.
- `./scripts/test-saved-styles.sh`: echte AppPreferences, EditorModel, ProjectStore und Renderer mit isolierten UserDefaults und synthetischem Bild geprüft. Speichern, erneutes Laden in frischer Preferences-Instanz, Umbenennen/Löschen, unabhängige bereits angewendete Objekte, genau ein Undo-Schritt mit Redo, identische Wiederanwendung ohne Revision, falsche Werkzeuggruppe, laufende Geste, Vorgaben für neue Objekte und getrennte Texteingabe-/Stil-Undo-Schritte bestanden.
- Autosave und Laden über eine neue Store-/Editor-Instanz erhalten das Original sowie die gestalteten Objekte. PNG nach Zuschnitt und Größenänderung unterscheidet sich sichtbar vom Ausgangsstil und bleibt nach Laden bytegleich. Keine Abhängigkeit von einer noch vorhandenen Vorlage.
- Beschädigte/neue Stilbibliotheken bleiben beim abgelehnten Schreibversuch bytegleich; keine stillen Rücksetzungen. Die native Oberfläche ist für macOS 26 kompiliert und wurde zusätzlich separat bedient.
- Zusätzlicher echter Prozess-Neustart: Ein Prüfhost speichert eine Vorlage und beendet sich vollständig; ein zweiter Start liest Namen, Werkzeuggruppe, Farbe und Stärke aus demselben isolierten UserDefaults-Bereich. Bestanden ohne erzwungenes Synchronisieren der Einstellungen.
- Echte Bedienung der Produktionsansichten in isolierter englischer Prüfapp mit synthetischem Projekt: blauen Formenstil speichern, rote Vorgaben wählen, gespeicherten Stil anwenden (Farbe und 20-%-Füllung wiederhergestellt), umbenennen und Löschdialog abbrechen; Vorlage blieb erhalten. Der dabei gefundene leere Erst-Speicherdialog wurde durch eine datengetriebene Sheet-Präsentation korrigiert und erneut erfolgreich bedient. Namens- und Verwaltungsdialog waren vollständig lesbar. Prüfapp anschließend regulär beendet; keine echte Bildschirm-/Tonaufnahme ausgelöst.
- `check-localization.py`: 557 App-Texte, drei InfoPlist- und 13 Domain-Texte mit vollständiger deutscher/englischer Compiler-Abdeckung. Bestehende native Bundle-Tests für Deutsch/Englisch und englischen Rückfall bei Französisch bestanden.

Vollständige VoiceOver-/Tastaturlayout- und Mehr-Mac-Abnahme bleibt Q03. Die Persistenzprüfungen verwenden neue Preferences-/Store-Instanzen und zwei getrennte Starts des Prüfhosts; ein vollständiger macOS-Neustart ist damit nicht geprüft. Benutzerdefinierte Stile werden weder veröffentlicht noch zwischen Macs synchronisiert.

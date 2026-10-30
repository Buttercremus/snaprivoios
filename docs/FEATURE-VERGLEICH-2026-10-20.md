# Sinnvolle nächste Ergänzungen für Snaprivo

Stand: 20. Oktober 2026. Vorschläge auf Basis des aktuellen Repositorys und öffentlich dokumentierter Herstellerfunktionen; keine neue Umsetzungszusage oder Änderung der bestätigten Free-/Pro-Grenzen. Konkurrenzprogramme wurden hier nicht selbst bedient. Herstellerangaben belegen angebotene Funktionen, keine vergleichende Qualitäts- oder Geschwindigkeitsmessung.

## Vergleichsrahmen

Die bestehende Produkthypothese aus [PRODUCT-BRIEF.md](PRODUCT-BRIEF.md) bleibt maßgeblich: native Mac-App für Support, Produktteams, Schulung und technische Dokumentation; Screenshots und kurze Videos lokal erstellen, später weiterbearbeiten und weitergeben. Daher sind CleanShot X und Shottr direkte Vergleichspunkte für den Mac-Alltag, Snagit für Dokumentationsabläufe. Screen Studio ist eine benachbarte Referenz für anspruchsvollere Videos, kein Ziel für vollständige Funktionsgleichheit. Priorisiert werden häufige Handgriffe und wiederholbare Dokumentation; ein Cloud-/Teamdienst ist kein Bestandteil dieser Empfehlung.

## Was andere Anbieter dokumentieren

| Anbieter | Relevante Funktionen | Einordnung für Snaprivo |
| --- | --- | --- |
| CleanShot X | Freihandstift mit Glättung, Spotlight, Bildkombinationen, wiederverwendbare Hintergrundvorgaben; Video mit Klick-/Tastenanzeige und Zooms. [Funktionsliste](https://cleanshot.com/features), [Produktübersicht](https://cleanshot.com/) | OCR, Scroll, Anheften, bearbeitbare Projekte und Bildgestaltung sind bei uns bereits vorhanden. Interessant sind die schnellere manuelle Erklärung und wiederholbare Ausgabe. |
| Shottr | Freihand, Spotlight, Pixelmaß-Lineal, Objekte/Text entfernen, halbtransparente Bildüberlagerungen und Vorher-/Nachher-Animationen. [Produkt und Versionshistorie](https://shottr.cc/), [FAQ zu Spotlight und Bildüberlagerungen](https://www.shottr.cc/kb/faq) | Besonders passende Referenz für kleine Werkzeuge, die wenige Handgriffe sparen. Seine FAQ unterscheidet Originalbild und eingefügte Objekte bei Rasteroperationen; solche Grenzen sollten bei uns ausdrücklich erkennbar bleiben. |
| Snagit | Smart Redact, Smart Move, vereinfachte UI-Grafiken, Vorlagen, Stapelverarbeitung und aus Klicks erzeugte Anleitungen. [Funktionsübersicht](https://www.techsmith.com/snagit/features/), [Smart Redact](https://www.techsmith.com/snagit/features/smart-redact/), [Smart Move](https://support.techsmith.com/hc/en-us/articles/39980449934093-What-is-Smart-Move) | Referenz für wiederholte Dokumentationsarbeit. Eine manuell überprüfbare lokale Schwärzungshilfe und Stapelausgabe sind näher an unserem jetzigen Stand als ein vollständiger intelligenter UI-Editor. |
| Screen Studio | Automatische/manuelle Videozooms, nachträglich anpassbarer Cursor, Kameralayouts und GIF-Ausgabe. [Produktübersicht](https://screen.studio/), [Auto-Zoom-Anleitung](https://screen.studio/guide/auto-zoom), [Cursor-Anleitung](https://screen.studio/guide/cursor) | Orientierung für spätere Videoverbesserungen. Bereits Klickanzeige und ein kurzer GIF-Export könnten für Supportvideos viel bewirken; automatische Kamerafahrten sind ein größeres eigenes Vorhaben. |

## Empfohlene Reihenfolge

Diese Priorisierung ist eine Produktbewertung, kein gemessener Nachfragebeleg. Relative Aufwände sind technische Ersteinschätzungen, keine Terminzusagen.

| Priorität | Ergänzung | Konkreter Nutzen und Abgrenzung zum vorhandenen Stand | Relativer Aufwand |
| --- | --- | --- | --- |
| 1 | Echter Freihandstift | Deckende, geglättete Striche und Unterstreichungen, weiterhin editierbar. Der vorhandene Freihand-Textmarker und Handstile für Formen ersetzen keinen frei gezeichneten Stift. | Klein–mittel |
| 2 | Spotlight/Fokusbereich | Bereich hell lassen und Umgebung abdunkeln; mehrere Fokusbereiche, einstellbare Intensität, live aufziehbar und rückgängig machbar. Ergänzt die bereits vorhandene Lupe. | Mittel |
| 3 | Ausrichten und Einrasten | Hilfslinien, Kanten-/Mittelpunktfang, gleiche Abstände, gemeinsam skalierbare Gruppen. Verbessert die vorhandene Mehrfachauswahl, statt nur neue Formen hinzuzufügen. | Mittel |
| 4 | Stapelausgabe mit benannten Vorgaben | Mehrere Bilder aus der Bibliothek mit derselben Größe, Gestaltung, Qualität und Dateinamenvorgabe ausgeben. Derzeit werden Ausgabeoptionen gemerkt; eine benannte Vorgabenbibliothek und diese Stapelaktion fehlen. | Mittel |
| 5 | Vergleich und automatische Bildanordnung | Zwei Bilder nebeneinander/untereinander, Vorher-/Nachher-Regler oder Differenzansicht; automatische Abstände und Beschriftungen. Eingefügte Bilder und mitwachsende Zeichenfläche existieren bereits, die komfortable Anordnung und Vergleichsansicht fehlen. | Mittel |
| 6 | Lokale Schwärzungsvorschläge | OCR-Fundstellen wie E-Mail-Adressen und Telefonnummern markieren und nach Prüfung in vorhandene deckende Abdeckungen umwandeln. Die vorhandene manuelle Abdeckung bleibt Grundlage; Erkennung ersetzt keine Kontrolle. | Mittel–groß |
| 7 | Kurze Erklärvideos gezielt verbessern | GIF-Ausgabe, sichtbare Klicks und optionale Tastenkürzelanzeige. Automatische Zooms und nachträglich veränderbare Cursor später gesondert entwickeln. Die noch offene reale Video-/Tonabnahme bleibt Voraussetzung für belastbare Zusagen. | Mittel–groß |
| 8 | Schnellere Anleitungserstellung | Bestehende Anleitungen durch einen Aufnahmeablauf mit Tastendruck pro Schritt, automatischer Nummerierung und direkt bearbeitbarer Bildunterschrift ergänzen. Ein globaler automatischer Klickrekorder wäre ein separates technisches Vorhaben. | Mittel / automatischer Rekorder groß |

Für den nächsten kleinen Ausbau empfehlen sich **Freihandstift, Spotlight und Ausrichten/Einrasten**. Für regelmäßige Dokumentationsarbeit folgen **Stapelvorgaben und Bildvergleich**. Die bereits dokumentierte Aufnahme-/Scroll-/Videoabnahme sollte parallel abgeschlossen werden. Ein eigener Cloudbetrieb und ein umfassender KI-Bildeditor haben für diese lokale Produktpositionierung zunächst geringere Priorität.

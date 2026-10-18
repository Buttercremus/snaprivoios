# Duplikate und Ebenen – E04

Stand: 13. Oktober 2026. Implementiert und geprüft im signierten Entwicklungsbuild.

## Bedienung und Regeln

- Objekt auswählen, rechts **Duplizieren** oder **⌘D** im Bearbeiten-Menü verwenden. Die Kopie erhält eine eigene ID und übernimmt Text, Form und alle Stile als unabhängige Werte.
- Kopien werden normalerweise um 16 Ausgabepixel versetzt. Zuschnitt und Zielauflösung werden berücksichtigt; an Bildrändern wird der Versatz angepasst. Übergroße Objekte bleiben auf der betroffenen Achse unverändert.
- **Nach vorne**, **Nach hinten**, **Ganz vorne**, **Ganz hinten** stehen im Inspector und Bearbeiten-Menü bereit. Grenzen deaktivieren die jeweilige Aktion.
- Jede abgeschlossene Aktion ergibt einen Undo-Schritt. Wirkungsloses Anordnen erzeugt keine Revision und verwirft keinen Redo-Schritt. Laufende Text-/Stiländerungen werden vorher abgeschlossen.
- Unschärfe bearbeitet weiterhin das Originalbild unter den Markierungen. Unschärfebereiche können untereinander, Markierungen untereinander angeordnet werden. Trefferprüfung und Renderer verwenden dieselbe Gruppierung/Reihenfolge.
- Autosave speichert nach 450 ms Ruhe; erneutes Öffnen stellt Reihenfolge und unabhängige Kopien wieder her. Die Undo-Historie beginnt wie bisher beim Öffnen neu. Format 3 bleibt kompatibel.

## Nachweise

- `./scripts/build.sh`: erfolgreich.
- `./scripts/test.sh`: 57 Domain-Tests erfolgreich, einschließlich Kopien sämtlicher Objektarten, Randversatz, Ebenengrenzen und History.
- `./scripts/test-layers.sh`: erfolgreich. Native Tests prüfen überlagerte Farben in Canvas/PNG, Trefferprüfung über Unschärfe, ⌘D, unabhängige Stile, Texttransaktionen, Undo/Redo, Interaktionssperren, Objektgrenze, tatsächliches verzögertes Autosave und Wiederöffnen, Projektkopie sowie PNG-/Thumbnail-/Zwischenablagenübereinstimmung mit Zuschnitt und Skalierung.
- Bestehende Canvas-, Renderer-, Resize- und Einstellungsprüfungen erfolgreich.
- Im laufenden Build am synthetischen Zuschnittprojekt: Pfeil mit ⌘D kopiert, Kopie unabhängig blau gefärbt, ganz nach hinten verschoben, sichtbare Überlagerung und Undo/Redo geprüft. Inspector-Schaltflächen sind sichtbar und passen in die Seitenleiste. Anschließend Teständerungen rückgängig gemacht und ursprüngliche zwei Markierungen gesichert; Bibliothek bestätigt zwei Markierungen.

Nicht separat manuell geprüft: VoiceOver, macOS 26 und Neustart mit neuen Ebenenaktionen. Persistenz/Wiederöffnen ist durch den nativen Integrationstest geprüft. Übergreifende Releasefälle bleiben im Arbeitsplan Q01–Q04.

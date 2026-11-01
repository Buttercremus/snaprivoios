# Nachweise zum Ausbau aus beiden App-Vergleichen

Stand: 1. November 2026. Operative Aufgaben und Reihenfolge stehen ausschließlich im [Arbeitsplan](ARBEITSPLAN.md). Der Ausgangsstand wurde als `24a1bb2` lokal gesichert. Keine Veröffentlichung.

## A01 Icon-Wechsel

Die Auswahlfeder liegt jetzt nur auf der Markierung im Button-Hintergrund. Symbol und Beschriftung behalten ihr Schriftgewicht, die bereits reservierten Buttonbreiten bleiben bestehen. Der Videoeditor verwendet für Play/Pause einen nativen SF-Symbol-Replace-Übergang; die Aktion animiert nur im vorhandenen Mausereignis und ohne reduzierte Bewegung. Es gibt keine neue Animation auf der Bild-/Video-Geometrie und keinen neuen Glass-Seitenleistenstil.

- `./scripts/build.sh -derivedDataPath build/BestOfApps/Xcode`: bestanden.
- `./scripts/test-editor-toolbar.sh`: native Größen-/Überlauf-/Exaktbreitenprüfung in Deutsch und Englisch bestanden. Die erzeugte deutsche Testdarstellung wurde visuell gesichtet.
- `./scripts/test-video-editing.sh`: Wiedergabe, Schnitt, Undo/Redo, Ausgabe, Abbruch, Schutz der Originale und Prozessneustart bestanden.
- `git diff --check`: bestanden.

Logs: `/tmp/Snaprivo-bestof-{build,toolbar,video}.log`. Der Screenshot des nativen Testfensters prüft die Darstellung, keine zeitliche Animationskurve. Persönliches Bewegungsgefühl mit schneller Mausbedienung und vollständige VoiceOver-Abnahme bleiben manuell.

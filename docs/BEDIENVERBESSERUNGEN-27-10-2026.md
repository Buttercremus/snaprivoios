# Inhaltssuche, Schrittaktionen und Tastaturbedienung

Stand: 27. Oktober 2026. Vom Nutzer autorisierte Punkte 1–4. Keine neue Abhängigkeit, Berechtigung oder Formatmigration.

## Anleitungen durchsuchen

Die Suche berücksichtigt Anleitungstitel, Einleitung, Schrittüberschriften und Beschreibungen. Mehrere Suchwörter müssen gemeinsam im Kopf einer Anleitung oder in Titel/Beschreibung desselben Schritts vorkommen. Groß-/Kleinschreibung und diakritische Zeichen werden mit der nativen Foundation-Suche behandelt. Treffer zeigen Anleitung, Schrittnummer und einen kurzen Textausschnitt. Eingabe im Suchfeld öffnet den ersten fertigen Treffer; ein noch laufender Suchauftrag öffnet keinen veralteten Treffer.

Ein Schritttreffer wählt und zeigt die passende Karte. Deren Titel erhält Tastatur- und angeforderten Accessibility-Fokus. Wiederholtes Öffnen desselben Treffers ist möglich. Die feste Schrittübersicht hält die Auswahl horizontal sichtbar. Ein Treffer im Anleitungskopf springt zum Titel. Lokale, noch ungespeicherte Änderungen ersetzen den älteren gespeicherten Suchstand der geöffneten Anleitung.

Der Store sucht in lokalen Manifesten ohne PNG-Assets zu laden oder den Bildcache zu ersetzen. Legacy-Dateien mit eingebetteten Bildern bleiben lesbar; sie werden beim nächsten Sichern regulär migriert. Papierkorb und beschädigte Papierkorbmarker werden ausgeschlossen. Es entsteht kein zusätzlicher persistenter Textindex; PNG-Inhalte und lokale Quellverweise werden nicht durchsucht.

## Schritte duplizieren und gezielt einfügen

Im Schrittmenü und im Kontextmenü der Übersicht stehen „Schritt duplizieren“, „Schritt davor hinzufügen …“ und „Schritt danach hinzufügen …“. Duplikate erhalten eine neue Schritt-ID und behalten Bild, Texte und lokale Quellverknüpfung. Sie werden direkt hinter dem Ausgangsschritt ausgewählt. Die Bilderauswahl übernimmt ihre nummerierte Reihenfolge an der gewählten Position.

Einfügen validiert den vollständigen zukünftigen Stand vor der Änderung. Fehlende Ziel-IDs führen nicht zum unbeabsichtigten Anhängen. Höchstens 100 Schritte, bestehende Bild-/Dateigrenzen und Pro-Regeln gelten weiter. Neue Aktionen sind als ganzer Vorgang rückgängig machbar und werden automatisch gespeichert. Der Fokus auf einen neu eingefügten Schritt wird erst nach Abschluss der Verarbeitung gesetzt, wenn seine Felder wieder aktiviert sind.

## Schnellvorschau mit Tastatur

- **Pfeiltasten:** vorherige/nächste Miniatur wählen; die Auswahl bleibt im sichtbaren Bereich. An Anfang/Ende kein unbeabsichtigter Rundlauf.
- **Eingabe:** gewählte Aufnahme im Editor öffnen.
- **Rückschritt:** gewählte Miniatur schließen.
- **Escape:** Stapel ausblenden. „Letzte Schnellvorschau anzeigen“ aktiviert das Panel und seinen Tastaturfokus ausdrücklich.

Neu eintreffende Hintergrundaufnahmen aktivieren die App weiterhin nicht. Schließen betrifft ausschließlich die Miniatur; gespeicherte Aufnahmen bleiben in der Bibliothek. Auf erneuten Nutzerwunsch wurde die Rückgängig-Einblendung samt Wiederherstellung geschlossener Miniaturen vollständig entfernt. Nach Schließen der letzten Miniatur verschwindet das Panel sofort. Ein leerer Stapel lässt sich nicht als leeres Fenster wieder öffnen. Der Stapel bleibt auf fünf sichtbare Aufnahmen begrenzt.

## Fokus und Darstellung

Schrittübersicht, Titel, Beschreibungen und Aktionsmenüs erhalten eindeutige Beschriftungen mit Schrittnummern. Die native Bilderauswahl enthält ihren Fokus; Suchtreffer führen zum passenden Titel, Einfügen wartet auf das Ende des deaktivierten Verarbeitungszustands. Die Schnellvorschau bietet native fokussierbare Bildbuttons mit Handlungshinweis. Das ausgeblendete X bleibt im Accessibility-Baum vorhanden.

Bei erhöhtem Kontrast werden Auswahlrahmen deutlicher. Die individuell gezeichneten Aufnahmebuttons erhalten klarere Konturen und dunklere farbige Flächen; die rote Stop-Bedeutung bleibt erhalten. Vorschauaktionen verwenden bei reduzierter Transparenz deckende Systemflächen. Animationen berücksichtigen weiterhin „Bewegung reduzieren“.

## Prüfungen und Grenzen

- 173 Domain-Tests bestanden, einschließlich Unicode-/Mehrwortsuche, stabiler Sprungziele nach Umsortieren, Einfügegrenzen/Atomarität, unabhängiger Schritt-IDs und Suche ohne verfügbare PNG-Assets sowie Papierkorbausschluss.
- `scripts/test-guides.sh --sandbox`: Duplizieren, Einfügen davor/danach, Quell-/Bildstand, History, Speichern/Wiederöffnen, ungültiges Einfügeziel, Pro-Sperre, ungespeicherte Suchtexte und wiederholter Suchsprung; bestehende PDF-/Markdown-/Datenschutzprüfungen bestanden.
- `scripts/test-quick-capture-integration.sh`: Auswahlgrenzen, Nachbarauswahl nach Schließen, verbleibender Stapel und unmittelbares Ausblenden nach der letzten Miniatur ohne Hinweisfenster. Ein leerer Stapel bleibt auch bei erneutem Anzeigen unsichtbar; gespeicherte Projekte bleiben erhalten. Bestehende Hintergrund-/Fenster-/OCR-/Clipboard-Prüfungen bleiben enthalten.
- `scripts/test-release-workflows.sh --sandbox`: bestehende Sicherung/Wiederherstellung, Papierkorb, Editor-Rückweg und Kaufregeln bestanden.
- Native Aufnahme-/Fokus-/Menü-/Reduced-Motion-Prüfung mit `scripts/test-capture.sh` bestanden. Regulärer App-Build und Signaturprüfung erfolgreich; native Deutsch-/Englisch-Prüfung bestanden. Katalog-/Compilerprüfung: 1242 App-, 7 InfoPlist- und 18 Domain-Texte vollständig in Deutsch/Englisch.

Tatsächlich bedient wurde ausschließlich eine isolierte Prüfapp mit synthetischen Bildern: Pfeiltastenauswahl, Rückschritt und Eingabe zum richtigen Editor (die damals ebenfalls geprüfte ⌘Z-Wiederherstellung wurde anschließend auf Nutzerwunsch entfernt); Inhaltssuche nach einem ausschließlich in Schritt 3 vorkommenden Beschreibungswort, Eingabe mit sichtbarem Titelfokus, Duplizieren eines einzelnen Schritts und Einfügen vor diesem Schritt. Die dunkle Ansicht wurde in einer nativen kleinen Fensteranordnung bei 800 Punkten Breite geprüft. Kontrast erhöhen und Transparenz reduzieren wurden in den Systemeinstellungen für die Sichtprüfung aktiviert und anschließend nachweislich auf ihren ursprünglichen Aus-Zustand zurückgesetzt. Die helle Vorschau wurde ebenfalls bedient. Nach der letzten Fokuskorrektur wurde in der hellen Anleitungsansicht ein Bild nach Schritt 1 eingefügt: Es steht als Schritt 2 an der richtigen Position, sein Titel erhält nach Abschluss der Verarbeitung den sichtbaren Textfokus und die horizontale Übersicht zeigt seine Auswahl.

VoiceOver wurde für einen kurzen Prüflauf über die Systemeinstellungen aktiviert und anschließend auf den ursprünglichen Aus-Zustand zurückgesetzt. Die Fernsteuerung liefert keinen zuverlässig prüfbaren Sprach- oder VoiceOver-Cursorverlauf. Beschriftungen, Rollen und Tastaturfokus sind nativ überprüft; eine vollständige gesprochene VoiceOver-Abnahme wird deshalb nicht behauptet. Weitere Hardware-/Mindestversionsfälle bleiben die bestehenden Releaseprüfungen.

Lokale Prüfprotokolle: `/tmp/snaprivo-workflow-four-{build,domain,guides,quick,release,capture,localization,language}.log`. Reproduzierbare UI-Prüfapps: `scripts/build-guide-workflow-ui.sh` (dunkle Variante mit `--dark`) und `scripts/build-quick-preview-ui.sh`. Sie verwenden temporäre Bibliotheken und synthetische Bilddaten. Die laufende Nutzer-App wurde nicht beendet oder ihre Bibliothek verändert.

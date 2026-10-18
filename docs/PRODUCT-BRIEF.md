# Snaprivo: kommerzielle Bewertung

Stand: 12. Oktober 2026. Empfehlung zur Entscheidung, kein bereits beschlossenes Preismodell und keine Aussage über implementierte Pro-Funktionen.

Die operative Abarbeitung und der aktuelle nächste Schritt stehen in [ARBEITSPLAN.md](ARBEITSPLAN.md). Die Reihenfolge in dieser Bewertung erklärt die Empfehlung; gepflegt wird der Arbeitsfortschritt ausschließlich im Arbeitsplan.

Methodik: ECC **product-lens** (Produktdiagnose und relative Feature-Priorisierung) sowie **market-research** (Primärquellen, Gegenargumente, Trennung von Fakten und Empfehlungen). Abgleich mit README, Entwicklungsplan, Bibliotheks-/Einstellungsoberfläche und vorhandenem Code. Keine erneute vollständige Code-, Hardware- oder App-Store-Abnahme. Wettbewerberfunktionen wurden anhand ihrer Herstellerseiten verglichen, nicht selbst vollständig getestet.

## Entscheidung in einem Absatz

**GO für die Weiterentwicklung eines kommerziellen Produkts; noch NO-GO für den Verkauf des aktuellen Entwicklungsstands.** Empfehlung: kostenlose brauchbare Basis, einmalige Pro-Freischaltung über StoreKit, vorerst kein Abo. Preisexperiment: **39,99 € regulär, 29,99 € Einführung** für das beschriebene Bild-/Video-Paket. Das sind zu prüfende Preisannahmen, keine ermittelte Zahlungsbereitschaft. Der Kaufgrund soll der schnelle, verlässliche Ablauf von der Aufnahme zur wiederverwendbaren Erklärung sein. Liquid Glass trägt zur Bedienqualität bei, ist allein aber kein belastbarer Wettbewerbsvorteil.

## 1. Für wen und wofür?

**Startzielgruppe als Hypothese:** Mac-Nutzer in Support, Produktteams, Schulung und technischer Dokumentation, die regelmäßig Abläufe erklären und ihre Aufnahmen später aktualisieren müssen. Eine Eingrenzung auf diesen Arbeitsablauf ist sinnvoller als gleichzeitig Designer, Videoproduzenten und Unternehmen mit komplexer Benutzerverwaltung anzusprechen.

**Problem:** Eine Aufnahme erstellen, verständlich markieren, sensible Stellen abdecken, eine kurze Erklärung weitergeben und sie beim nächsten Produktupdate wieder bearbeiten. Der Nutzen entsteht durch gesparte Arbeit bei Wiederholung und Aktualisierung. Wie häufig dieser Bedarf auftritt und wie viel Zeit er kostet, muss mit externen Nutzern gemessen werden.

**Positionierung zum Testen:** „Screenshots und kurze Erklärvideos für deinen Mac – schnell erstellt, lokal gespeichert und später weiterbearbeitbar. Einmal kaufen.“ Das ist eine Zielbeschreibung. Aktuell ist Video als noch unvollständiger Prototyp vorhanden; dieser Satz ist noch keine veröffentlichungsfähige Produktwerbung.

**Warum jetzt?** Die vorhandene native Oberfläche, Standbild-Aufnahme und bearbeitbare Bibliothek bilden eine brauchbare technische Basis. Die Mindestversion macOS 26 passt zur Designentscheidung, begrenzt aber die erreichbare Zielgruppe. Es liegen keine Daten zum Anteil kompatibler Geräte unserer potenziellen Kunden vor.

**Langfristige Idealversion:** Eine Bildschirmhandlung wird mit wenigen Aufnahmen oder einem kurzen Video zu einer verständlichen, aktualisierbaren Anleitung. Einheitliche Stile, nummerierte Schritte und gezielte Wiederverwendung helfen dabei. Daraus folgt kein Auftrag, jetzt eine automatische KI-Anleitung oder einen vollständigen Videoschnittplatz zu bauen.

## 2. Konkurrenz und Gegenargumente

Herstellerangaben, Abruf am 12. Oktober 2026. USD-Preise werden nicht in Euro umgerechnet; regionale Preise und Steuern können abweichen.

| Produkt | Beobachtetes Angebot | Bedeutung für SnagForge |
| --- | --- | --- |
| [Shottr](https://shottr.cc/purchase.html) | Basic 12 USD, Friends Club 30 USD, jeweils Einmalkauf. Kostenlose Nutzung mit späteren Kaufhinweisen; kommerzielle Nutzung erfordert laut Hersteller eine Lizenz. | Ein günstiger, umfangreicher Screenshot-Editor ist bereits erhältlich. „Einmalkauf“ allein schafft keine Alleinstellung. |
| [CleanShot X](https://cleanshot.com/pricing) | Basic 35 USD einmalig, ein Jahr Updates; optionale Updateverlängerung 19 USD/Jahr. Pro 10 USD je Nutzer/Monat bei Jahreszahlung, mit erweitertem Cloud-/Teamangebot. | Lokale App und laufende Dienste lassen sich wirtschaftlich unterschiedlich behandeln. Das Direktvertriebsmodell mit Updateverlängerung ist nicht unsere Store-Architektur. |
| [Snagit](https://support.techsmith.com/hc/en-us/articles/27009223314701-TechSmith-Transition-to-Annual-Subscription-Pricing-Model-in-2025) | TechSmith verkauft neue Snagit-Versionen seit 2025 im Jahresabonnement. | Eine dauerhaft freigeschaltete lokale Alternative ist eine plausible Positionierung, aber noch kein Nachweis für Wechselbereitschaft. |
| [Screen Studio](https://screen.studio/) | Spezialisierter Recorder mit ausgearbeiteten Zoom-, Bewegungs- und Präsentationsfunktionen. Ein aktueller Preis war im lesbaren Abruf nicht belastbar auswertbar. | Ein vollständiger Creator-Videoeditor wäre ein erheblicher zusätzlicher Produktumfang. |
| [iScreen Shoter](https://apps.apple.com/de/app/iscreen-shoter-screenshot-app/id1596559494?mt=12) | Kostenlos mit In-App-Käufen; nennt OCR, Übersetzung, Anheften, Pipette und mehrere Ausgabeformate. | Zusätzliche Alltagshilfen als Referenz; daraus folgen keine belegten Umsätze oder eine neue Preisentscheidung. |

[Shottr](https://shottr.cc/) bietet bereits Scroll-Aufnahmen, OCR, kombinierte Screenshots und Annotationen. [CleanShot](https://cleanshot.com/features) bietet ebenfalls OCR, Scroll-Aufnahmen und bearbeitbare Projekte; lokale Texterkennung ist dort bereits Teil des Angebots. Die Herstellerseite zur [Videoaufnahme](https://cleanshot.com/screen-recording) zeigt zudem Aufnahme und Nachbearbeitung. Auch [macOS selbst](https://support.apple.com/en-ie/guide/mac-help/mh26782/27/mac/27) enthält Screenshot- und Bildschirmaufnahme-Werkzeuge.

**Schlussfolgerung:** OCR, Scroll-Aufnahme, Datenschutz und eine native Oberfläche sind nützlich, aber einzeln keine einzigartige Verkaufsstory. Der zu validierende Unterschied liegt in einer besonders reibungslosen, wiederverwendbaren Dokumentationsarbeit. Weitere Formen ohne bessere Gesamtbedienung lösen dieses Problem kaum.

## 3. Kaufmodell

| Modell | Vorteil | Nachteil | Bewertung |
| --- | --- | --- | --- |
| Bezahlter Download | Einfachstes Kaufmodell, keine eigene Feature-Freischaltung nötig | Nutzer müssen vor dem Test zahlen; höhere Kaufhürde für eine unbekannte App | Gute Alternative, wenn wir die schnellste technische Veröffentlichung priorisieren |
| Kostenloser Download + einmalig Pro | Aufnahmequalität lässt sich vor dem Kauf erleben; klare dauerhafte Freischaltung | StoreKit, Wiederherstellung, Kaufzustände und Free-/Pro-Grenzen müssen entwickelt und geprüft werden | **Empfehlung** |
| Monats-/Jahresabo für die lokale App | Wiederkehrender Erlös kann Wartung und Entwicklung finanzieren | Muss dauerhaft spürbaren Wert liefern; zusätzlicher Wettbewerb um Abo-Budget | Zum Start nicht empfohlen |
| Einmalkauf lokal + optionales Dienste-Abo später | Wiederkehrende Kosten werden durch wiederkehrende Umsätze abgedeckt | Cloud bringt Betrieb, Datenschutz, Support und weitere Abhängigkeiten mit | Erst nach belegtem Bedarf |

Apple beschreibt einen [nicht verbrauchbaren In-App-Kauf](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/) als einmaligen Kauf ohne Ablauf. Für unsere Pro-Freischaltung passt dieser Produkttyp. Die [App Review Guidelines 3.1.1 und 3.1.2](https://developer.apple.com/app-store/review/guidelines/) behandeln Funktionsfreischaltung über In-App-Käufe sowie den fortlaufenden Wert von Abonnements. Ein Abo ist auch für substantielle laufende App-Updates möglich; Cloud ist keine Voraussetzung. Meine Ablehnung eines Start-Abos ist eine Produktentscheidung, keine behauptete Apple-Sperre.

Eine freiwillige **14-Tage-Pro-Testphase** wäre sinnvoll, damit insbesondere Scroll-Aufnahme und Video vor dem Kauf ausprobiert werden können. Apple erlaubt für Apps ohne Abo einen entsprechend bezeichneten kostenlosen nicht verbrauchbaren Testkauf; Dauer, Einschränkungen danach und Vollpreis müssen verständlich sein. Die Testphase ist ein eigenes StoreKit-Arbeitspaket, kein einfacher lokaler Countdown. Nach Ablauf sollten bestehende Projekte lesbar und als flaches Ergebnis exportierbar bleiben.

**Verständliches Kaufversprechen:** Dauerhafte Freischaltung der enthaltenen Pro-Funktionen. Keine erneute Zahlung für bereits gekaufte Funktionen. Kein pauschales Versprechen, dass jedes künftig erfundene Erweiterungspaket für immer enthalten ist. Spätere neue Pakete müssten optional, klar abgegrenzt und separat kommuniziert werden. Ein eigener Lizenzserver und jährlich wechselnde lokale Lizenzdateien gehören nicht in diesen Store-Plan.

**Wirtschaftliche Grenze:** Ein Einmalkauf braucht dauerhaft neue Kunden oder sinnvolle neue Zusatzangebote. Er beseitigt Wartungs- und Supportkosten nicht. Für qualifizierte, aufgenommene Entwickler sieht Apples [Small Business Program](https://developer.apple.com/app-store/small-business-program/) 15 % Provision auf bezahlte Apps und In-App-Käufe vor; Teilnahme ist nicht automatisch gegeben. Verkaufspreis ist nicht Nettoerlös: Steuern, Gebühren, Erstattungen, Support und Entwicklungszeit müssen in die Kalkulation. Keine Absatz- oder Umsatzprognose ohne belastbare Nutzerdaten.

## 4. Was ist Basis, was rechtfertigt Pro?

Vorschlag zur Erprobung, noch keine implementierte Bezahlschranke:

| Bereich | Kostenlose Basis | Pro, einmalig |
| --- | --- | --- |
| Aufnehmen und weitergeben | Fenster/Bereich/Bildschirm, Hotkeys, PNG, Zwischenablage | Scroll-Aufnahme und zusätzliche Dokumentationsabläufe |
| Einfach erklären | Pfeil, Text, Zuschneiden/Zoom; verlässliches Speichern | Voller Formen-/Callout-Editor, Schrittnummern, Textmarker, eigene Stile, zusätzliche Schriftoptionen |
| Daten und Vertrauen | Autosave, Wiederöffnen, Umbenennen, Papierkorb, Export/Backup der eigenen Daten; manuell deckend abdecken | OCR-Suche, Tags und Projekte/Sammlungen für größere Arbeitsbestände |
| Wiederholte Arbeit | Einzelaufnahme bearbeiten | Mehrere Bilder zu Anleitungen zusammenstellen, PDF/Markdown, gemeinsame Stile und Exportvorgaben |
| Video | Keine künstlich verkürzten oder mit Wasserzeichen versehenen kostenlosen Testaufnahmen erforderlich | Bereich/Fenster/Display, Systemton/Mikrofon, Trimmen und MP4; später gezielte weitere Video-Werkzeuge |

**Stärkste Pro-Kandidaten:**

1. **Scroll-Aufnahme:** Lange Webseiten, Tickets und Dokumente in einer Aufnahme erklären. Eine gute Vorschau und verlässliches Stitching sind wichtiger als sofortige Scroll-Automatik.
2. **Kurze Erklärvideos:** Eine Handlung zeigen, statt viele Einzelbilder zu bauen. Aufnahme plus Trimmen und Export als kompletter Ablauf.
3. **Anleitungen aus mehreren Screenshots:** Schritte nummerieren, beschriften, sortieren, aktualisieren und als PDF/Markdown ausgeben. Das ist die stärkste zu prüfende Produktdifferenzierung.
4. **Eigene Werkzeugstile und Exportvorgaben:** Wiederkehrende Farben, Schrift und Größen reduzieren Nacharbeit.
5. **Lokale OCR und durchsuchbare Bibliothek:** Text übernehmen und alte Aufnahmen anhand ihres Inhalts wiederfinden. Wichtig für Vielnutzer, als einzelne OCR-Funktion jedoch schon breit verfügbar.

Sicherung und zuverlässiger Zugriff auf eigene Daten sind Basisqualität. Auch deckendes manuelles Abdecken sollte nicht erst nach einem Kauf verfügbar sein. Ein ausgefeilteres automatisches Erkennen vertraulicher Stellen könnte später ein Zusatznutzen sein. Weder Unschärfe noch OCR-Erkennung garantieren sichere Schwärzung. Ein bearbeitbares Projekt enthält weiterhin sein Original; ein flacher bereinigter Export muss diese Informationen tatsächlich ausschließen.

## 5. Was fehlt im aktuellen Projekt?

**Vorhanden:** Screenshot-Standbildauswahl über ScreenCaptureKit, direkte Bildbearbeitung, Pfeile/Text/Formen/Callouts/Unschärfe, Eigenschaften und Stile, Größenänderungsgriffe, Undo/Redo, PNG/Clipboard, lokale bearbeitbare Projekte mit Autosave und eine Bibliothek mit Titelsuche. Die bestehenden Nachweise stehen in README und den Abnahmeprotokollen.

**Für eine verlässlich verkaufbare Basis noch erforderlich:**

- E01–E03 sind umgesetzt: Zoom/Schwenken, nicht destruktives Zuschneiden und Bildauflösung mit gemeinsamer Skalierung der Markierungen, Undo/Redo, Autosave und konsistenter PNG-/Clipboard-Ausgabe. Die noch offenen Hardware-/Releasefälle stehen in den Abnahmeprotokollen: [Zoom](ZOOM-ABNAHME.md), [Zuschnitt](ZUSCHNITT-ABNAHME.md), [Bildauflösung](BILDAUFLOESUNG-ABNAHME.md).
- E04/E05 sind umgesetzt: Duplizieren, Ebenen nach vorn/hinten, Schriftwahl, Fett/Kursiv, Textausrichtung und frei platzierbarer Callout-Zeiger. [Abnahme](TEXT-CALLOUT-ABNAHME.md).
- L01–L04 sind umgesetzt: Umbenennen, Favoriten, Sortierung, Papierkorb, portable Projekte und additive Bibliothekswiederherstellung. P05 ergänzt Tags, Sammlungen und optionale lokale OCR-Inhaltssuche seit 16.10.2026. [Nachweise](BIBLIOTHEK-SUCHE-ABNAHME.md).
- I07 ergänzt auf Nutzerwunsch vom 16.10.2026 eine horizontale Bildvorschauleiste im Editor: schneller direkter Wechsel, stabile Reihenfolge und Erhalt offener Änderungen. [Nachweise](BILDVORSCHAULEISTE-ABNAHME.md).
- S01 ist umgesetzt: deckendes Abdecken mit geprüfter PNG-/Clipboard-Ausgabe. Projekte und Sicherungen behalten ausdrücklich das Original. [Nachweise](PORTABILITAET-DATENSCHUTZ-ABNAHME.md).
- S02/S03 sind umgesetzt: frei belegbare Hotkeys samt Nutzerbestätigung der globalen Auslösung sowie Erstaufnahme-/Berechtigungsführung. Weitere macOS-/Tastaturlayout-/TCC-Fälle bleiben Q01. [Nachweis](EINSTELLUNGEN-ABNAHME.md).
- StoreKit bei Pro-Modell: Kauf, Abbruch, ausstehender Kauf, Wiederherstellung, Neustart/Offline-Verhalten und Rückerstattung; Preise aus dem Store statt fest im UI.
- Tests auf Mindestversion macOS 26, realen Mehrdisplay-/Retina-Konfigurationen, mit Rechteentzug, großen Bildern und größeren Bibliotheken. Datenverlustfälle wie voller Datenträger und Prozessabbruch ergänzen.
- VoiceOver-/Tastaturbedienung des Canvas, Hell/Dunkel, Kontrast und reduzierte Transparenz; Name, finales Icon, Support, Datenschutzerklärung und echte Store-Metadaten. Die Vorbereitungen dafür sind teilweise vorhanden, die vollständige Freigabe fehlt.

**Noch offen sind insbesondere** die vollständige Ton-/Hardwareabnahme der Videoaufnahme sowie die breite Produktabnahme der Scroll-Aufnahme. P02–P06 sind umgesetzt: eigene Werkzeugstile, Schrittnummern/Markieren, lokale OCR, Tags/Sammlungen/Inhaltssuche und aktualisierbare Screenshot-Anleitungen als PDF/Markdown. Die Anleitungsausgabe wurde einschließlich eigener Arbeitsstände, Portabilität und Datenschutz geprüft. [P06-Nachweise](ANLEITUNG-AUSGABE-ABNAHME.md). Ein erster echter Video-Prototyp erfasst jetzt Bereiche, startet/stoppt, finalisiert MP4 und exportiert im Sandbox-Build; Wiedergabe und lokale Originale nach Neustart sind geprüft. V01 ergänzt seit 16.10.2026 eine eigenständige Fensterquelle; Auswahl, Geometrie, Konfiguration und Fehleranzeige sind synthetisch geprüft. Der Video-Vorlauf ist mit Keine/3/5 Sekunden nach ausdrücklichem Start umgesetzt und einschließlich Abbruch/Berechtigungsreihenfolge synthetisch geprüft. Echte Fenster-/Displayaufnahme und vollständige Quellen-/Stop-Abnahme bleiben offen. [Stand und Grenzen](VIDEO-ABNAHME.md). V02 ergänzt die Videobibliothek mit persistenten Metadaten, Öffnen nach Neustart, Fehlerständen sowie eigener geprüfter Sicherung/Wiederherstellung. Umbenennen kopiert keine großen Videodateien. [V02-Nachweise](VIDEO-BIBLIOTHEK-ABNAHME.md). V03 ergänzt interne Vorschau, gespeicherte nicht destruktive Schnittgrenzen mit Undo/Redo und MP4-Ausgabe des Ausschnitts samt vorhandener Tonspur. Originale bleiben erhalten; Schnitt-/Dateizeitachsen, Exportfehler und Neustart sind mit synthetischen Clips im Sandbox-Host geprüft. [V03-Nachweise](VIDEO-TRIMMEN-ABNAHME.md). V04 ist ohne Ton teilweise geprüft: echte Fensteränderung und Dateiablauf, native Unterbrechungs-/Speicherfehlerregression; ein tatsächlicher Speicherabbruch und rund 28 fps im kurzen Versuch lassen Dauerlauf/30-fps-Abnahme weiter offen. [V04-Nachweise](VIDEO-V04-ABNAHME.md). StoreKit fehlt weiterhin. Die restlichen Ton- und Synchronitätstests sind auf Nutzerwunsch verschoben; dies ändert keine Releasekriterien.

## 6. Video: ja, begrenzt und vollständig

Der bestehende Entwicklungsplan sieht Bilder **und kurze Videos** für die erste vollständige Version vor. Diese Empfehlung streicht Video nicht. Eine bildbasierte TestFlight-Beta kann vorher starten; ein kommerzieller Release ohne Video wäre eine bewusst separat zu entscheidende Umfangsänderung.

**Ziel für Video V1:** Region, Fenster oder Display wählen; optional Systemton und Mikrofon; Countdown; sichtbarer Aufnahmezustand; Stop; zuverlässige Dateifinalisierung; Bibliothek; Vorschau; Anfang/Ende trimmen; MP4/H.264 exportieren. Zunächst das bestehende Ziel SDR/1080p/30 fps. Fensteränderung, Sleep, Rechteentzug, Gerätewechsel, wenig Speicherplatz und Abbruch brauchen definierte Ergebnisse.

**Später:** 4K/60 fps bei nachgewiesener Qualität, Cursor-/Klickdarstellung, Kamera, Untertitel und einfachere Zoom-Effekte. Noch später zeitgesteuerte Annotationen oder Objektverfolgung. Für den ersten Verkauf keine Mehrspur-Timeline, kein Versprechen automatischer KI-Videoaufbereitung und keine vollständige Konkurrenz zu Screen Studio/Camtasia.

## 7. Priorisierung und nächste Arbeit

Relative ICE-Bewertung: Wirkung × Zuversicht ÷ Aufwand, jeweils 1–5. Einschätzungen für dieses Projekt, keine gemessenen Marktwerte; Aufwandspunkte sind keine Wochenangaben. Sicherheits-, Daten- und Store-Voraussetzungen bleiben harte Freigabebedingungen unabhängig vom Score.

| Paket | Wirkung | Zuversicht | Aufwand | Score |
| --- | ---: | ---: | ---: | ---: |
| Zuschneiden/Zoom | 5 | 5 | 2 | 12,5 |
| Bibliotheks-Grundverwaltung | 5 | 5 | 2 | 12,5 |
| Schrittnummern und eigene Stile | 4 | 4 | 2 | 8,0 |
| Deckendes Abdecken mit Exportprüfung | 4 | 4 | 2 | 8,0 |
| StoreKit-Freischaltung | 5 | 5 | 3 | 8,3 |
| OCR mit Suche | 4 | 4 | 3 | 5,3 |
| Anleitungsausgabe PDF/Markdown | 4 | 3 | 3 | 4,0 |
| Scroll-Stitching | 5 | 3 | 5 | 3,0 |
| Videoaufnahme bis MP4/Trimmen | 5 | 3 | 5 | 3,0 |

**Empfohlene Ausführungsfolge:**

1. Editorbasis schließen: nach Zoom/Zuschneiden/Auflösung nun Objektaktionen und Text/Callouts vervollständigen; danach Bibliotheksverwaltung/Projektportabilität und deckendes Abdecken. Die einzelnen Abnahmekriterien stehen im Arbeitsplan.
2. Eigenes Arbeitsthema für Scroll-Stitching und einen kleinen Video-Versuch: Sandbox, Qualität und Fehlerfälle früh belegen. Ein niedriger ICE-Wert rechtfertigt kein Aufschieben dieser technischen Unbekannten bis kurz vor dem geplanten Release.
3. Schrittnummern/eigene Stile und lokale OCR; mit einem vollständigen Support-/Anleitungsablauf erproben.
4. Videoaufnahme produktisieren und StoreKit-Freischaltung samt optionaler Testphase integrieren, sobald Paketgrenzen und Preise pilotiert sind.
5. TestFlight, Kauf-/Restore-Prüfungen, reale Abnahmen und erst dann Store-Veröffentlichung.

Kein belastbarer neuer Veröffentlichungstermin aus diesem Review. Der bisherige Zeitkorridor im Entwicklungsplan ist eine vorläufige Schätzung, kein kommerzieller Liefertermin.

## 8. Wie prüfen wir, ob jemand dafür zahlt?

Es liegen noch keine belastbaren Daten zu externen aktiven Nutzern, Wiederkehr, Zahlungsbereitschaft oder Umsatz vor. Deswegen keine erfundene Product-Market-Fit-Bewertung.

Vorschlag für einen ersten Pilot mit 10–15 Personen aus der Zielgruppe, als kleine qualitative Stichprobe:

- Eine eigene reale Aufgabe vom Aufnehmen bis zum versendbaren Ergebnis erledigen lassen; Zeit, Abbrüche und Nacharbeit beobachten.
- Nach einer Woche prüfen, ob SnagForge freiwillig erneut verwendet wurde und welches bisherige Werkzeug dadurch ersetzt wurde.
- Nicht nur fragen, ob das Design gefällt: den tatsächlichen letzten Anwendungsfall und fehlende Schritte ermitteln.
- 29,99/39,99/49,99 € als unterschiedliche Preisannahmen prüfen. Bei dieser Stichprobe lassen sich Gründe verstehen, aber keine belastbaren Conversion-Raten vergleichen.
- Vor einem Verkauf die vollständige, tatsächlich lieferbare Funktionsliste zeigen. TestFlight nicht gegen Bezahlung bereitstellen und daraus keine Zahlungssignale erfinden.

Messgrößen: erster erfolgreicher Ablauf, freiwillige Wiederverwendung, Häufigkeit relevanter Pro-Aufgaben, Zahl verlorener/fehlerhafter Aufnahmen, später echte Store-Käufe/Erstattungen und Supportaufwand. Instrumentierung zunächst über freiwilliges Feedback und synthetische Tests; keine Screenshots oder OCR-Inhalte für Nutzungsanalyse versenden.

**Konkrete nächste Produktentscheidung:** Kostenlose Basis plus einmalig Pro als Testmodell bestätigen und den Support-/Anleitungsablauf als Startziel priorisieren. T01 manuelles Scroll-Stitching ist als erster Prototyp implementiert, wieder im Menü aktiv und automatisiert sowie am echten Mac bis Editor/Autosave/App-Neustart geprüft. Die breite Seitenabnahme bleibt P01; T02 bietet Bereichsvideo/Start/Stop/MP4 mit optionalem Systemton und Mikrofon. Der V01-Fensterpfad ist implementiert und synthetisch geprüft; seine echte Quellenabnahme bleibt offen. P02–P06 sind umgesetzt; weitere Ton-/Synchronitäts- und Hardwaretests bleiben auf Nutzerwunsch für später vorgemerkt (Stand 16. Oktober 2026). Diese Analyse ändert weder die App-Bezahlung noch veröffentlichte Zusagen.

## Ergänzung: Referenz iScreen Shoter

Nach dem Nutzerbild vom 12. Oktober 2026 sind Anheften, Farbpipette/Pixellupe und direkte OCR-Aktionen sinnvolle Komfortkandidaten. Mehrere Einzelbild-Ausgabeformate und eine kompakte Aktionsgruppierung können die Weitergabe erleichtern; OCR-Übersetzung und eingefügte Bilder sind spätere Optionen. Die Aufgaben mit Abnahme und Voraussetzungen stehen ausschließlich unter I01–I06/P04 im [Arbeitsplan](ARBEITSPLAN.md). Die Preisannahmen bleiben unverändert und unvalidiert. Es wurden keine neuen App-Funktionen oder Bezahlschranken implementiert.

## Namensentscheidung – 13. Oktober 2026

Produktname: **Snaprivo**. **snaprivo.com** (Hauptdomain) und **snaprivo.de** sind laut Nutzer gekauft. Die sichtbare Umbenennung der App folgt unter D05. Xcode-Projekt, Bundle-ID und Speicherpfade bleiben vorerst stabil, damit bestehende Projekte und Bildschirmfreigaben erhalten bleiben.

E04 ist am 13. Oktober 2026 umgesetzt: Duplizieren mit eigener Objekt-ID, vier Ebenenaktionen, Undo/Redo und Autosave. Unschärfebereiche bleiben unter den Markierungen. Nachweise: [Objekt-Abnahme](OBJEKTE-ABNAHME.md).

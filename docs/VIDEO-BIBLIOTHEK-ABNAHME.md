# V02 – Videospeicherung und Bibliothek

Stand: 16. Oktober 2026. V02 ergänzt die lokale Videobibliothek; die echte Quellen-/Ton-/Hardwareabnahme aus V01/V04 bleibt getrennt offen. Die restlichen Ton- und Synchronitätstests bleiben auf Nutzerwunsch für später vorgemerkt.

## Bedienung und Umfang

Unter **Bibliothek** zwischen **Bilder** und **Videos** wechseln. Videos zeigen Titel, Datum, Vorschaubild, Dauer, Pixelmaße und vorhandenen Ton. Titelsuche, neueste zuerst oder Namen-Reihenfolge, Umbenennen und Videoaktionen sind verfügbar. **Video ansehen** öffnet seit V03 die interne Vorschau; **Original extern öffnen** bleibt für die zugeordnete macOS-App verfügbar. **MP4 speichern …** exportiert den gesicherten Ausschnitt über den nativen Speicherdialog; **Im Finder zeigen** zeigt das Original. Nach Schließen einer Videoaufnahmesitzung mit angelegtem Arbeitsstand wird die Videobibliothek aktualisiert und ausgewählt. Abbrechen vor der Dateivorbereitung bewahrt die bisherige Ansicht.

Laufende, unterbrochene oder fehlgeschlagene Aufnahmen bleiben als solche erkennbar. Sie haben keine Wiedergabe-/Exportaktion. Eine verweigerte Mikrofonfreigabe oder ein abgebrochener Countdown legt weiterhin keinen Aufnahmeeintrag an. Nach dem Start angelegte Arbeitsstände hinterlassen bei Fehler/Abbruch einen kleinen Statusdatensatz. Unbestätigte Arbeitsdateien bleiben verborgen; es gibt keine automatische Reparatur oder Veröffentlichung unvollständiger Videos.

Interne Vorschau und nicht destruktives Trimmen sind inzwischen in [V03](VIDEO-TRIMMEN-ABNAHME.md) ergänzt. Video-Papierkorb, Tags/OCR für Videos und ein gemeinsamer Bild-/Video-Sicherungscontainer sind nicht implementiert. Videooriginale werden in dieser Oberfläche nicht gelöscht.

## Speicher- und Wiederanlaufregeln

- Bestehender separater Ort im App-Container: `Snaprivo/VideoRecordings`. Die konfigurierbare Bildbibliothek und deren Ordnerwechsel betreffen weiterhin Bilder. Tests verwenden eigene temporäre Ordner.
- Pro Video ein versionierter kleiner JSON-Datensatz in `.library`, dazu ein wiederaufbaubares JPEG-Vorschaubild. Die MP4 wird nach erfolgreicher Finalisierung unverändert behalten. Umbenennen schreibt ausschließlich den Datensatz, keine Videokopie.
- Vor Streamstart wird der Arbeitsstand als laufend journalisiert. Finalisierung verlangt weiterhin erfolgreiche Plattformabschlüsse, lesbare Videofakten und einen dekodierbaren Frame, bei gewähltem Ton außerdem eine dekodierbare Audiospur. Das prüft keine akustische Qualität oder echte A/V-Synchronität.
- Vor dem Umbenennen der Arbeitsdatei wird ihr Zielname journalisiert. Erst nach Veröffentlichung der Datei wird der Datensatz fertig. Ein Prozessabbruch dazwischen ergibt einen bekannten unterbrochenen Stand; er darf nicht als alte fertige Datei übernommen werden. Fehler beim abschließenden Schreiben versuchen, Datei und Datensatz auf den Arbeitsstand zurückzuführen.
- Laufende Datensätze ohne aktive Sitzung werden nach Neustart als unterbrochen markiert. Fehlende Dateien, beschädigte/neue Metadaten und ungültige Altdateien erscheinen als Fehler bzw. Ladehinweis. Unbekannte Schema-Versionen werden nicht überschrieben.
- Frühere sichtbare MP4s ohne Metadaten werden vor Übernahme mit AVFoundation geprüft. Die Videodatei wird dabei nicht umkopiert. Ungültige Dateien erhalten einen nicht abspielbaren Fehlerstand. Verborgene Arbeitsdateien werden nicht übernommen.
- UI-Zustand bleibt MainActor-isoliert; Dateiarbeit, SHA-256, Medienprüfung und Vorschaubilder laufen außerhalb des MainActor. Domain-Typen enthalten keine UI-/Capture-/AVFoundation-Typen.

## Sicherung und Wiederherstellung

**Videos sichern …** ist in der Videobibliothek und unter **Ablage** verfügbar. Im gewählten Zielordner entsteht ein neuer Ordner mit fertigen MP4-Originalen und einem versionierten `manifest.json` mit Titel/Medienfakten, seit V03 dem gesicherten Schnitt und SHA-256 je Datei. Es werden keine laufenden, fehlgeschlagenen oder verborgenen Arbeitsdateien gesichert. Kopieren erfolgt nur bei ausdrücklicher Sicherung, Wiederherstellung oder MP4-Ausgabe. Für SHA-256 wird das öffentliche Apple-Framework CryptoKit verwendet; keine neue externe Produktabhängigkeit.

Der Sicherungsordner wird zunächst verborgen zusammengestellt, die Kopien werden mit begrenzten Lesepuffern geprüft und erst danach als Ganzes veröffentlicht. Vorhandene Ziele werden nicht ersetzt. **Videosicherung wiederherstellen …** validiert Version, IDs, Dateinamen, Größen-/Dauer-/Tonfakten, dekodierbare Frames und Prüfsummen aller Quellen vor einer Änderung der Bibliothek. Symlink-Dateien und Pfadüberschreitungen werden abgelehnt. Kopien werden erneut geprüft, erhalten neue IDs und überschreiben kein vorhandenes Video. Ein wiederholter Import erzeugt weitere unabhängige Kopien.

Bei einem normalen Fehler während der Übernahme werden die in diesem Auftrag veröffentlichten Dateien und Datensätze zurückgenommen. Ein harter Prozess-/Stromabbruch während der abschließenden Veröffentlichung kann eine vollständige Teilmenge hinterlassen, wie bei der Bildbibliothekswiederherstellung aus L04; diese Hardware-/Stromausfallabnahme bleibt offen. Nicht fertig veröffentlichte Staging-Verzeichnisse bleiben verborgen und werden nicht als Bibliotheksinhalt angeboten. Sicherungs-/Exportoperationen werden beim normalen App-Beenden abgewartet.

Die bestehende `.snaprivobackup` sichert weiterhin ausschließlich Bildprojekte einschließlich ihres Papierkorbs. Sie wird im Menü ausdrücklich **Bildbibliothek sichern …** genannt. Anleitungen und Videos haben separate Sicherungswege; die Videobibliothek erklärt diese Trennung sichtbar. Sandbox-Zugriff erfolgt über native Ordner-/Dateidialoge mit Security-Scoped-Zugriff für die Dauer der Operation.

## Nachweise

- 118 Domain-Tests: Video-Schema/Roundtrip, benötigte Fakten für fertige Videos, Pfadgrenzen, unbekannte Versionen, ungültige Größen/Dauern, doppelte Sicherungseinträge, Prüfsummenformat und Ausschluss unvollständiger Einträge.
- `./scripts/test-video-library.sh`: fertige Medien samt Thumbnail/Dauer/Maßen; Umbenennen ohne Veränderung von Bytes, Dateinummer und Änderungsdatum; neue Store-/Modellinstanz; fehlgeschlagene/unterbrochene Arbeitsstände; Altdateien; Schutz neuer Metadaten; Sicherung, Prüfsummen, neue Kopien, wiederholter Import und beschädigte zweite Quelldatei ohne Teilimport. Öffnen wird an der öffentlichen Ziel-App-Grenze injiziert. Gleichzeitige Listenabfragen erzeugen keine doppelten Altdatei-Einträge; ein Abbruch zwischen Datei-Umbenennung und Finalisierung bleibt unterbrochen.
- `./scripts/test-video-library.sh --sandbox`: dieselben Regeln im isolierten App-Sandbox-Host. Zusätzlich zwei echte Prozessstarts: fertiges synthetisches Video samt geändertem Titel und Vorschaubild wiederfinden; verbliebener laufender Stand wird unterbrochen.
- `./scripts/test-video.sh`: bestehende Start-/Stop-/Finalisierungs-/Berechtigungs-/Countdown-/Speicherfehler einschließlich verborgen bleibender unbestätigter Arbeitsdateien. Synthetische Mediendateien ersetzen keine echte Tonaufnahme.

- Signierter Build und Signaturprüfung bestanden; 731 App-Texte, vier InfoPlist-Texte und 13 Domain-Texte vollständig Deutsch/Englisch, Compiler-Abdeckung und native Sprachprüfungen bestanden. Bestehende Bildbibliotheks-/OCR-/Bildwechselprüfungen bestanden.
- Tatsächliche deutsche Produktionsoberfläche mit synthetischer Bibliothek bedient: leere Ansicht, fertig/fehlgeschlagen/unterbrochen, Vorschaubild/Medienangaben, Titelsuche und Umbenennen. Das fertige synthetische Original wurde über die Bibliotheksaktion tatsächlich in QuickTime geöffnet und anschließend geschlossen. Leere und gefüllte Ansicht zusätzlich bei 800 Pixeln Fensterbreite geprüft; Header oben und Fehlerkarten mit regulär lesbarem Text. Eine Sicherung über den tatsächlichen Ordnerdialog nach `/private/tmp` erzeugt; das Manifest enthält nur das fertige Video. Über denselben nativen Dialog wiederhergestellt, Erfolgsmeldung und vier statt drei Einträge mit zwei unterschiedlichen fertigen IDs beobachtet. Die normale Nutzer-App wurde nicht beendet oder neu gestartet.

Die synthetischen Videos werden aus Code erzeugt. Keine Nutzeraufnahme, OCR-Inhalte oder Schlüssel werden als Fixture eingecheckt. Echte Fenster-/Displayaufnahme, Mikrofonpegel/Synchronität, 15-Minuten-Laufzeit, macOS 26 und breite Hardwareabnahme bleiben offen.

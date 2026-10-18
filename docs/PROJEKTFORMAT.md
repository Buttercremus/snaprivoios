# Bearbeitbare Projekte und Autosave

Stand: 16. Oktober 2026 · Dokumentformat 9, internes Paketmanifest 1, portables Projekt-/Backupformat 1 · implementierter Stand. Bestehende Dokumente der Versionen 1–8 bleiben lesbar.

## Nutzerablauf

Jede Aufnahme und jeder Bildimport legt zunächst ein Projekt an. Erst nach erfolgreicher Anlage öffnet der Editor. Kann das bisherige Projekt nicht gesichert werden, bleibt es im Editor; das neue Bild ist dennoch in der Bibliothek gespeichert. Die Bibliothek zeigt lokal gespeicherte Projekte mit Titel, Änderungsdatum, Markierungsanzahl und Vorschau; die Suche umfasst Titel, Tags, Sammlungen und optional lokal erkannten sichtbaren Bildtext. Ein Klick öffnet Original und bearbeitbare Objekte.

Änderungen an Objekten und bestätigte Zuschnitte und Größenänderungen einschließlich Undo/Redo lösen nach 450 ms ohne weitere Änderung Autosave aus. ⌘S sichert sofort. Der normale Speicherstatus wird nicht als eigene Zeile angezeigt. Bei Schreibfehlern erscheint eine Fehlermeldung; die Änderungen bleiben im Editor und können erneut oder als neues Projekt gesichert werden. Das normale Beenden wartet auf laufende Anlage-/Speichervorgänge und wird bei ungesicherten Änderungen mit Speicherfehler abgebrochen. Inline-Text wird bereits während der Eingabe als Objekt gesichert. Eine Schiebereglerbewegung sichert ebenfalls bereits laufende Änderungen und bildet einen Dokument-Undo-Schritt. Die abgeschlossene Texteingabe bildet einen Dokument-Undo-Schritt; Escape beendet sie und behält den Text. Beim Ziehen von Pfeilspitze oder Anfang wird die fertige Geometrie beim Loslassen als ein Undo-Schritt übernommen und automatisch gesichert; das Format verwendet dafür die vorhandenen Start-/Endkoordinaten.

Ein Neustart erhält alle Objekte mit IDs, Typ, Positionen, Text, Textfeldbreite, Farbe, Linien-/Schriftgröße, Unschärferadius, Füllung und Eckenradius. `textWidth` ist eine optionale Erweiterung von Version 1: fehlende Breite in bestehenden Projekten bedeutet automatisch mitwachsender Text, vorhandene positive Breite aktiviert Zeilenumbruch. `fill` und `cornerRadius` sind ebenfalls optionale Erweiterungen: Ohne `fill` bleiben Rechtecke/Ellipsen ungefüllt und Callouts weiß gefüllt. Eine explizite Füllung speichert Aktivierung, sRGB-Farbe und Deckkraft von 0 bis 1; so bleibt auch ein transparent eingestellter Callout transparent. Ohne `cornerRadius` ist ein Rechteck scharfkantig. Der gespeicherte Radius wird beim Zeichnen auf die halbe kurze Kante begrenzt. Neue Felder werden einschließlich endlicher Zahlenwerte beim Laden validiert. Alte Projekte bleiben lesbar. Undo-Historie, Auswahl und Werkzeugvorgaben werden nicht gespeichert. PNG-Export und Zwischenablage enthalten das flach gerenderte Bild; die bearbeitbare Fassung bleibt in der Bibliothek.

`textHeight` ist eine weitere optionale Ergänzung von Format 1: Sie speichert die positive, endliche Mindesthöhe der Textfläche eines in der Größe geänderten Callouts, ohne die 12/10 Pixel Innenabstände und ohne Zeiger. Fehlende Höhe erhält das bisherige mitwachsende Layout. Der Text wird bei Breitenänderungen neu umbrochen; ist er höher als die Mindesthöhe, wächst der Rahmen mit. Die Schriftgröße bleibt beim Resize erhalten. Form-Resize schreibt die normierte Geometrie in `start`/`end`; IDs, Stile und Füllungen bleiben erhalten. Umschalt speichert die resultierende Geometrie, keinen zusätzlichen Modus.

Formen umfassen außerdem `triangle`, `diamond` und `star`; ihre Geometrie folgt denselben Start-/Endkoordinaten und funktioniert in beiden Ziehrichtungen. Das optionale Feld `stroke` speichert Rand an/aus und `solid`, `dashed` oder `dotted`. Ohne das Feld bleibt der bisherige durchgezogene Rand aktiv. Farbe und Stärke verwenden weiterhin `color` und `lineWidth`; Füllung ist davon unabhängig. Formwechsel erhalten Objekt-ID, Geometrie und Farben. Die sechs eingebauten Stilvorlagen sind Bedienvorgaben; ihre resultierenden Objekteigenschaften werden gespeichert. Bestehende Projekte bleiben lesbar. Ältere Entwicklungsbuilds kennen die neuen Formtypen nicht; ein Rückwechsel auf alte Builds ist für solche Projekte nicht unterstützt.

## Tags und Sammlungen in Format 7

Optionale String-Arrays `tags` und `collections` speichern die Organisation direkt im Projekt. Fehlende oder leere Felder bedeuten keine Zuordnung. Bis zu 32 Tags und 16 Sammlungen je Projekt; Namen sind außen beschnitten, Unicode-normalisiert, höchstens 80 Zeichen / 320 UTF-8-Bytes lang und frei von Steuerzeichen. Doppelte Namen nach Groß-/Kleinschreibungs-, Akzent- und Breitennormalisierung werden beim Bearbeiten zusammengefasst; gespeicherte ungültige oder doppelte Daten werden beim Laden abgelehnt. Sammlungen gruppieren gleiche Namen und benötigen keine externen IDs oder Katalogdateien.

Versionen 1–6 werden nur im Speicher migriert; gültige Format-6-Hervorhebungen und Schrittnummern bleiben erhalten. Erst ein Schreibvorgang sichert Format 7. Ältere Builds lehnen Version 7 ab, damit sie Tags nicht still verlieren. Metadatenänderungen bleiben außerhalb der Objekt-Undo-Historie und verwenden dieselbe Revision-/Konfliktprüfung wie bisher. Autosave, Kopie, Archiv und Backup behalten beide Arrays.

OCR-Suchergebnisse liegen separat in einem vollständig ableitbaren SQLite-Cache im App-Container, nicht im Projekt oder Backup. Der Cache-Schlüssel beschreibt sichtbare Bildparameter; geänderte Abdeckungen, Zuschnitt, Größenänderung oder Objekte machen alte Ergebnisse ungültig. Abschalten entfernt den Cache. [Bedienung, Datenschutz und Tests](BIBLIOTHEK-SUCHE-ABNAHME.md).

## Zuschnitt, Größenänderung und Migration auf Format 3

`pixelSize` beschreibt weiterhin das unveränderte Original. Das optionale `crop` enthält ein ganzzahliges Rechteck in Originalpixeln mit Ursprung oben links: mindestens 1 × 1 Pixel, vollständig innerhalb von `pixelSize`. Fehlend bzw. `null` bedeutet das ganze Original. Objektkoordinaten und Schrift-/Liniengrößen bleiben unverändert. Außerhalb liegende Markierungen werden nur ausgeblendet, nicht gelöscht. `outputRect` wird daraus abgeleitet und nicht zusätzlich gespeichert. PNG, Zwischenablage und Thumbnail zeigen den bestätigten Ausschnitt in der gewählten Zielauflösung. Die gespeicherte Originaldatei wird nicht resampelt.

Die Vorschau im Zuschneidewerkzeug gehört nicht zum Dokument. Erst Übernehmen erzeugt eine Revision und einen gemeinsamen Undo-Schritt. Abbruch, Werkzeugwechsel oder normales Beenden ohne Übernehmen bewahren den bisherigen Zuschnitt. „Ganzes Original“ bzw. „Zuschnitt aufheben“ behält alle Objekte. Nach Neustart ist der gespeicherte Zuschnitt weiter veränderbar, die Sitzungshistorie beginnt wie bisher leer.

Das optionale Feld `resizedSize` speichert die positive ganzzahlige Zielbreite/-höhe des bestätigten Ausschnitts. Fehlend bzw. `null` bedeutet dessen ursprüngliche Pixelmaße. `outputPixelSize` wird daraus abgeleitet. Bild und alle Markierungen werden gemeinsam skaliert, einschließlich Schrift-/Linienbreiten und Unschärfe; bei freiem Seitenverhältnis auch unterschiedlich pro Achse. Objektwerte im Inspektor bleiben Originalpixelwerte. Die Auswahlgriffe behalten ihre Größe in Ansichtspunkten, und native Texteingabe verwendet dieselbe zweiachsige Projektion. Der Export komponiert zuerst das Original samt Markierungen und Zuschnitt und skaliert anschließend einmal auf die Zielmaße. Wiederholte Änderungen verwenden immer das Original, nie eine zuvor verkleinerte Ausgabe.

Ein späterer Zuschnitt berechnet aus den bisherigen ganzzahligen Ausgangs-/Zielmaßen die X/Y-Faktoren und rundet neue Zielmaße auf ganze Pixel (mindestens eins). Die Kombination wird zusammen als ein Undo-Schritt gespeichert. Würde der neue Ausschnitt die Zielgrenze überschreiten, bleibt der Entwurf unverändert zur Korrektur offen. „Originalauflösung“ setzt nur die Skalierung zurück; „Zuschnitt aufheben“ erweitert den Ausschnitt mit der bisher gewählten Skalierung. Das vollständige Original und ausgeblendete Objekte bleiben im Paket.

Dokumente der Versionen 1/2 werden nur im Speicher nach Version 3 migriert; ID, Objekte, Datum, Revision und vorhandener Zuschnitt bleiben unverändert. Erst die nächste tatsächliche Dokumentänderung schreibt Version 3. Ältere Builds lehnen Version 3 ab, statt die Zielauflösung zu ignorieren. Unbekannte zukünftige Versionen bleiben gesperrt. Das Paketmanifest bleibt Version 1. Nachweise: [Zuschnitt-Abnahme](ZUSCHNITT-ABNAHME.md), [Skalierungsabnahme](BILDAUFLOESUNG-ABNAHME.md).

## Ablage

Zoom und Schwenkposition gehören ausschließlich zur Editoransicht und werden nicht gespeichert. Beim Wiederöffnen startet das Projekt mit „Anpassen“. Die Projektion berücksichtigt die Bildschirm-Skalierung, ändert aber weder Bildpixelkoordinaten noch Schrift-/Liniengrößen, Dokumentrevision oder Undo-Historie. Die Ausgabe verwendet unabhängig vom Zoom die gespeicherte Zielauflösung; ohne Größenänderung sind es die Pixelmaße des bestätigten Ausschnitts oder des Originals. Zoom erfordert keine Formatänderung.

Standardmäßig verwendet die App `Application Support/SnagForge/Projects` innerhalb ihres Sandbox-Containers. Bei der derzeitigen Bundle-ID liegt dieser Ordner üblicherweise unter `~/Library/Containers/com.snagforge.app/Data/Library/Application Support/SnagForge/Projects`. Eine Änderung der Bundle-ID benötigt eine bewusste Datenmigration.

Seit 14.10.2026 lässt sich unter Einstellungen → Speicherorte ein eigener Bibliotheksordner wählen. Snaprivo verwendet darin `Snaprivo-Bibliothek`; ein direkt gewählter Ordner dieses Namens wird selbst verwendet. Der Wechsel wartet auf ausstehende Editorarbeit, kopiert aktive Projektpakete und `.Trash` unter der Bibliotheks-Dateisperre in einen temporären Zielordner und vergleicht alle Dateien byteweise. Erst nach erfolgreicher Prüfung wird der Zielordner atomar veröffentlicht und der neue Sandbox-Bookmark gespeichert. Bestehende Ziele, verschachtelte Quell-/Zielorte, Symlinks und unvollständige Projekte werden abgelehnt. Originale, Revisionen, Thumbnails und Papierkorb bleiben vollständig; der Quellordner wird nicht gelöscht. Der offene Editor behält Undo, Auswahl und Ansicht, schreibt aber künftig in die neue Bibliothek. Bei fehlendem dauerhaften Zugriff wird die Bibliothek gesperrt und eine erneute Ordnerfreigabe angeboten, ohne auf den Standardort auszuweichen. PNG-Standardordner und Videoablage sind davon getrennt. [Nachweise und reale Abnahme](SPEICHERORTE-DARSTELLUNG-ABNAHME.md).

```text
Projects/
  .library-lock
  <UUID>.snagforge/
    manifest.json
    original.png
    thumbnail.png
    Revisions/
      <aktuelle Revision>.json
      <vorherige lesbare Revision>.json
```

- `manifest.json`: Manifestformat 1, Projekt-ID, aktuelle und vorherige Generation.
- `original.png`: einmalige, unveränderte Projektquelle; aus Import/Aufnahme in SDR/sRGB-PNG normalisiert, mit Transparenz. Die importierte Benutzerdatei wird nicht verändert.
- Dokumentrevision: Dokumentformat 6, ID, Titel, Zeitstempel, Revision, Originalpixelgröße, optionaler Zuschnitt, optionale Zielauflösung und geordnete bearbeitbare Objekte in Originalpixeln mit Ursprung oben links.
- `thumbnail.png`: ableitbarer Cache, höchstens 420 Pixel an der längeren Kante, mit derselben Komposition wie der Export. Ein Thumbnail-Fehler verhindert keine erfolgreiche Objektsicherung.

## Schreiben und Wiederherstellung

`ProjectStore` serialisiert Zugriffe als Actor außerhalb des UI-Actors. Eine lokale Dateisperre verhindert konkurrierendes Schreiben durch mehrere Prozesse desselben Containers. Neue Projekte entstehen vollständig in einem temporären Paket und werden anschließend an den endgültigen Ort verschoben.

Autosave schreibt zuerst die vollständige neue Dokumentrevision atomar, danach das Manifest atomar. Erst nach dieser Veröffentlichung werden ältere Revisionen bereinigt; aktuelle und vorherige lesbare Revision bleiben erhalten. Das Original wird bei Markierungs-, Zuschnitt- oder Größenänderungen nicht erneut kopiert. Erwartete Ausgangsgenerationen verhindern, dass ein veralteter Editor Änderungen eines anderen Prozesses überschreibt. „Als Kopie sichern“ bewahrt in diesem Fall die lokalen Änderungen einschließlich Zuschnitt und Zielauflösung unter einer neuen Projekt-ID.

Ist die aktuelle Dokumentrevision unlesbar, wird die vorherige lesbare Revision geöffnet und der Rückfall angezeigt. Die nächste Sicherung behält diese lesbare Revision als Rückfall. Ein beschädigtes Manifest oder fehlendes Original wird als Bibliotheksproblem angezeigt. Andere Projekte bleiben zugänglich. Unbekannte neuere Formatversionen werden ausdrücklich abgelehnt und nicht überschrieben. Schema, IDs, Dimensionen, Objekte und endliche Zahlenwerte werden beim Laden validiert. Das gleiche Limit von 32 MB für Dokument-JSON gilt beim Schreiben und Lesen, damit ein erfolgreich gesichertes Dokument wieder geöffnet werden kann.

## Grenzen und weitere Arbeit

Autosave ist kein Backup: Bei erzwungenem Beenden können die letzten noch nicht bestätigten bzw. geschriebenen Änderungen fehlen. Atomare Dateiersetzung ist keine Garantie gegen Stromausfall oder defekte Datenträger. Vollständiges Original, frühere Revision und Vorschau bleiben im Projekt; Unschärfe entfernt keine vertraulichen Quelldaten.

Noch nicht implementiert: Tags/OCR, persistierte Undo-Historie und Migrationen für zukünftige Formate. Bei großer Bibliothek ersetzt später ein wiederaufbaubarer Index das Einlesen aller Revisionen. Leistungs- und Prozessabbruchtests sowie reale Speicherplatzfehler bleiben Teil der Releaseabnahme.

## Icon und Arbeitsname

Der generierte Icon-Entwurf 2 ist in `Assets.xcassets/AppIcon.appiconset` eingebunden; Quelle und vollständiger Prompt stehen in [design/app-icon/README.md](../design/app-icon/README.md). Er bleibt ein Entwurf; Icon-Composer-Ebenen und Erscheinungsvarianten sind ein späterer Designschritt.

SnapForge ist als endgültiger Name ungeeignet: Bereits am Recherchetag wird im Chrome Web Store ein [SnapForge – Screenshot Editor and Design Tool](https://chromewebstore.google.com/detail/snapforge-screenshot-edit/jddlbdehkgmdcgmmjinaplmfdaogelin?hl=en) von AcroQube LLC angeboten. Funktionsumfang und Zielgebiet überschneiden sich direkt. Der Produktname wurde inzwischen als Snaprivo festgelegt; snaprivo.com und snaprivo.de sind laut Nutzer gekauft. Die interne Identität bleibt vorerst SnagForge. Eine endgültige Markenprüfung ist damit nicht erfolgt.

## E04: Duplikate und Ebenen

Die bestehende Objektliste speichert die Reihenfolge von hinten nach vorne innerhalb ihrer Gruppe: Unschärfefilter, darüber Markierungen. Duplikate erhalten neue UUIDs und unabhängige Geometrie-/Stilwerte. E04 benötigte keine Änderung am damaligen Format 3. Undo/Redo und Autosave übernehmen die gesamte Objektliste einschließlich Reihenfolge.

## Schrift und Callout-Ziel: Format 4

`textStyle` speichert optional Schriftfamilie, Gewicht (`regular`, `semibold`, `bold`), Kursiv und Ausrichtung (`left`, `center`, `right`). Ohne das Feld gelten die bisherigen Systemschrift-Semibold-/Linksbündig-Vorgaben. Die Formatierung gilt für das gesamte Objekt; einzelne Zeichen haben keine abweichenden Stile. Familiennamen müssen nicht leer und maximal 256 UTF-8-Bytes lang sein. Fehlende Fonts verwenden einen verfügbaren Ersatz, Dateien werden nicht eingebettet.

`calloutTip` enthält optional das absolute Ziel in Originalpixeln. Ohne Ziel wird der bisherige Zeiger unten links berechnet. Koordinaten müssen endlich und betragsmäßig höchstens 1.000.000 sein. Beim Verschieben/Duplizieren wird das Ziel mitversetzt; beim Rahmen-Resize wird das bisher berechnete Ziel gegebenenfalls explizit gespeichert und festgehalten. Liegt das Ziel im Rahmen, zeichnet der Renderer keinen herausstehenden Zeiger.

Version 4 migriert Dokumente 1–3 beim Lesen im Speicher; Version 3 behält insbesondere `resizedSize`. Das Original wird unverändert übernommen. Erst eine gespeicherte Änderung schreibt das neue Format. Alte Builds weisen Version 4 zurück, statt die neuen Eigenschaften unbemerkt zu verwerfen. Die oben beschriebenen Format-3-Regeln bleiben Teil der Entwicklungshistorie; aktuelle Schreibversion ist inzwischen 9.

## Bibliotheksmetadaten (L01)

`title` enthält den Projektnamen. `favorite` ist eine optionale boolesche Erweiterung von Format 4; fehlend bedeutet kein Favorit. Metadatenänderungen schreiben eine neue Revision und aktualisieren `modifiedAt`, ohne Original/Objekte zu ersetzen. Geschlossene Projekte werden unter derselben prozessübergreifenden Sperre wie Editor-Saves aktualisiert, ohne das Originalbild einzulesen. Geöffnete Projekte ändern ihren aktuellen Editorzustand und flushen ihn, sodass ausstehende Autosaves den Namen oder Favoritenstatus nicht zurücksetzen. Die Objekthistorie enthält diese organisatorischen Werte nicht.

Sortierung und Favoritenfilter stehen in UserDefaults unter `library.sort` und `library.favoritesOnly`; Suchtext wird nicht dauerhaft gespeichert. Konfliktsicherung als Projektkopie übernimmt den Favoritenstatus. Projekt-IDs und Paketpfade bleiben beim Umbenennen identisch.

## Papierkorb (L02)

Vollständige Pakete werden unter der Bibliothekssperre atomar von `<UUID>.snagforge` nach `.Trash/<UUID>.snagforge` verschoben. Wiederherstellen führt die inverse Operation aus; vorhandene IDs werden niemals überschrieben. Original, Revisionen und Vorschau bleiben zusammen, Format 4 bleibt unverändert. Autosave darf ein verschobenes Projekt nicht neu anlegen.

Endgültiges Löschen ist ausschließlich für Pakete im App-Papierkorb möglich. Nach Bestätigung markiert die atomare Umbenennung auf `<UUID>.deleting` die Löschabsicht; danach wird der Paketordner entfernt. Beim nächsten Laden werden unterbrochene `.deleting`-Operationen fortgesetzt. Normale Papierkorbprojekte werden nie automatisch gelöscht. Fehler erscheinen als Bibliothekshinweis. Eine beschädigte Revision wird wie in der aktiven Bibliothek behandelt; unlesbare Pakete haben noch keine eigene Reparatur-/Löschoberfläche.


## Deckende Abdeckung: Format 5 (S01)

`EditorObject.Kind.redact` verwendet `start`/`end` für ein Rechteck und `color` für die vollständig deckende sRGB-Farbe. Füllungsdeckkraft, Rand und Eckenradius beeinflussen diesen Typ nicht. Reihenfolge: Unschärfefilter, normale Markierungen, deckende Abdeckungen. Innerhalb der jeweiligen Gruppe bleibt die gespeicherte Reihenfolge wirksam. Eine Abdeckung kann nicht hinter normale Markierungen gelegt werden.

Der Renderer rundet die abgedeckte Fläche nach außen auf Ausgabepixel, zeichnet ohne Kantenglättung mit Alpha 1 und ersetzt die betroffenen Pixel. Nach Crop/Resize werden Abdeckungen nochmals in den Zielpixeln gezeichnet. PNG erhält keine Text-/Objektdaten oder Originaldatei. Die Zwischenablage bekommt dasselbe PNG; macOS kann daraus TIFF anbieten. Projekt, Backup und historische Revisionen behalten dagegen ihr Original und ihre editierbaren Inhalte. Dies ist kein bereinigtes Projektformat.

Versionen 1–4 werden im Speicher nach 5 migriert. Erst eine Änderung schreibt Format 5. Ältere Builds lehnen es ab, damit Abdeckungen nicht unbemerkt verloren gehen. Die Undo-Historie bleibt sitzungsbezogen.

## Markieren und Liste: Format 6 (P03)

`EditorObject.Kind.highlight` speichert `highlightStyle` mit `mode` (`rectangle` oder `freehand`), `opacity` (endlich, 0–1) und `points`. Rechteckmarkierungen verwenden `start`/`end` und eine leere Punktliste. Freihand verwendet 1–10.000 Punkte in Originalpixelkoordinaten; auch ein einzelner Punkt ist ein sichtbarer Strich. `color` enthält die Markerfarbe, `lineWidth` die Freihandbreite. Zeichnen verwendet Multiplizieren mit runden Strichenden; Zuschnitt blendet außerhalb liegende Teile aus. Verschieben/Duplizieren versetzt alle Punkte. Rechtecke unterstützen die vorhandenen Größenänderungsgriffe.

`EditorObject.Kind.step` speichert `stepStyle` mit `index` (1–10.000), `numbering` (`numbers` oder `letters`), `shape` (`circle`, `roundedRectangle`, `diamond`, `pointer`) und `textColor`. `start`/`end` beschreiben die positive Markenfläche; `color` ist ihre Füllfarbe. Der Renderer leitet den Text aus Typ und Wert ab, mit A–Z, AA usw. bei Buchstaben. Schrift passt in die Form. Neue Marken und ihre Canvas-Größenänderungen bleiben quadratisch.

Ein separater Zähler wird nicht gespeichert. Die nächste Marke verwendet den höchsten vorhandenen Wert desselben Typs plus eins. Löschen und Ebenenänderungen nummerieren nichts um; Löschen des höchsten Werts gibt diesen nächsten Wert wieder frei. Ein Duplikat erhält den nächsten Wert und eine neue Objekt-ID. Undo/Redo und Wiederöffnen leiten die Folge aus dem wiederhergestellten Dokument ab. Typ/Form/Farben/Wert einer vorhandenen Marke sind bearbeitbar; gleiche Werte nach manuellen Änderungen sind erlaubt. Bei 10.000 endet die jeweilige Folge mit einem Hinweis.

Format 6 verlangt passende Metadaten für beide neuen Objekttypen und validiert Zahlen, Farben, Punkte und Grenzen. Versionen 1–5 werden nur im Speicher nach 6 migriert; erst eine Änderung schreibt 6. Neue Typen oder ihre Metadaten in fälschlich älter bezeichneten Dokumenten werden abgelehnt. Ältere Builds weisen Version 6 zurück. Die vorangehenden Migrationsabschnitte dokumentieren die jeweiligen historischen Schritte; Paketmanifest und portable Container bleiben Version 1. [Bedienregeln und Nachweise](MARKIEREN-LISTE-ABNAHME.md).

## Portables Projekt (L03)

Eine `.snaprivo`-Datei ist eine binäre Property List mit:

- `format`: `com.snaprivo.project`, `version`: 1.
- `document`: JSON des aktuellen lesbaren Projektstands einschließlich Titel, Favorit, Zeitstempeln, Crop, Zielauflösung und aller Objekte.
- `original`: unveränderte PNG-Quelle.
- `digest`: SHA-256 der Originalbytes zur Integritätsprüfung; keine digitale Signatur.

Nicht enthalten: frühere Revisionen, Undo-Historie, Thumbnails, App-Einstellungen, Zugriffstoken oder absolute Quellpfade. Die App regeneriert Thumbnails. Einzelimport erzeugt immer eine neue UUID und Revision 0; die ursprüngliche ID überschreibt weder aktive noch gelöschte Projekte. Doppelte Titel sind erlaubt.

Grenzen: 550 MB pro Datei, 512 MB Originaldaten und 32 MB Dokument-JSON (dezimal), zusätzlich vorhandene Pixel-/Objektlimits. Vor Import werden Schema, SHA-256, PNG-Kopf und Dimensionen geprüft; die App dekodiert das Bild vollständig mit ImageIO und vergleicht seine Pixelgröße. Symlinks, nicht reguläre Dateien und unbekannte Versionen werden abgewiesen. Fehler werden angezeigt; vorhandene Daten bleiben erhalten.

Native Öffnen-/Sichern-Dialoge erteilen nur Zugriff auf den gewählten Ort. Security-Scoped-Zugriff gilt für die laufende Operation und wird danach beendet. Kein zusätzlicher dauerhafter Verzeichniszugriff, keine neue TCC-Freigabe.

## Bibliothekssicherung (L04)

`.snaprivobackup` ist ein als Paket registrierter Ordner:

```text
Name.snaprivobackup/
  index.json
  <zufällige UUID>.snaprivo
  ...
```

Der Index enthält `format: com.snaprivo.backup`, `version: 1` und pro Projekt den streng validierten UUID-Dateinamen, `isTrashed` und SHA-256 der portablen Datei. Er ist auf 8 MB und 100.000 Einträge begrenzt. Beliebige relative Pfade, doppelte Dateinamen und Links werden nicht übernommen.

Die Sicherung hält dieselbe prozessübergreifende Bibliothekssperre wie Autosave. Sie enthält damit jeweils vollständige lesbare Revisionen samt Originalen und Papierkorbstatus. Offene Texteingaben/Änderungen werden vorher abgeschlossen und gesichert. Ein temporärer Ordner neben dem gewählten Ziel nimmt alle Dateien auf; erst nach Erfolg wird er auf den Zielnamen umbenannt. Ein vorhandenes Ziel wird abgelehnt. Unlesbare Projekte führen zu einem sichtbaren Fehler statt einer als vollständig gemeldeten Teilsicherung.

Wiederherstellung ergänzt die Bibliothek. Freie IDs bleiben erhalten, Kollisionen mit aktiven/gelöschten oder weiteren eingelesenen Projekten erhalten neue IDs. Zunächst werden alle Dateien geprüft, vollständig dekodiert, mit neuen Vorschaubildern versehen und als interne Pakete in einem temporären Ordner aufgebaut. Erst danach werden sie in aktive Bibliothek bzw. Papierkorb übernommen. Bei regulärem Fehler während dieser Übernahme werden bereits übernommene neue Pakete nach Möglichkeit zurückgerollt; bestehende Projekte werden nicht verändert.

Ein Prozessabbruch während der letzten Umbenennungen kann eine Teilmenge vollständiger neuer Projekte hinterlassen. Erneutes Einspielen erzeugt für bereits vorhandene IDs weitere Kopien. Ein Abbruch davor kann temporäre Ordner hinterlassen, die nicht als Projekte gelistet werden. Es gibt keine pauschale Transaktions-/Stromausfallgarantie für die gesamte Bibliothek. Voller Datenträger, Prozessabbruch und sehr große Backups bleiben Q02. Die Sicherung enthält aktuelle lesbare Stände, keine vollständige Versionshistorie oder App-Einstellungen.

[Tests und native Abnahme L03–S03](PORTABILITAET-DATENSCHUTZ-ABNAHME.md).


## Separate Anleitungsdatei P06

Bildprojekte verwenden inzwischen Format 8. Anleitungen verwenden unabhängig davon Format 1 als binäre `.snaprivoguide`-Property-List: ID/Revision, Titel, Einleitung, gemeinsamer PDF-Stil, Änderungsdatum und geordnete Schritte mit eigenen IDs, Schritttiteln, Bildunterschriften und flachen PNG-Pixeln. Lokale Arbeitsstände können einen Projektverweis und einen Hash der Bibliotheksidentität enthalten; portable Kopien entfernen beide. Keine Originale, Editorobjekte, vorherigen Revisionen oder OCR-Daten im Transfer. Arbeitsstände behalten separat eine vorherige vollständige Datei. PNG-Metadaten werden vor Import/Weitergabe bereinigt. Anleitungen werden im App-Container getrennt von der Bildbibliothek gesichert; deren Backup-/Ordnerwechsel übernimmt sie nicht. Grenzen, Wiederherstellung, Konfliktregeln und Nachweise: [Anleitungsausgabe](ANLEITUNG-AUSGABE-ABNAHME.md).


## Handgezeichneter Zeichenstil in Format 8

`EditorObject.drawingStyle` ist optional (`precise` / `handDrawn`) und nur für Pfeile/Ellipsen zulässig. Fehlend bedeutet präzise Darstellung. Die Kurven werden deterministisch aus den bestehenden Bildkoordinaten erzeugt; es werden keine Zufallspfade oder gerasterten Objektkopien gespeichert. Stilvorlagen übernehmen die optionale Eigenschaft nur für passende Werkzeuge. Versionen 1–7 werden im Speicher migriert; Tags und Sammlungen aus Format 7 bleiben dabei erhalten. Ältere Builds lehnen Format 8 ab, statt den Stil beim Speichern unbemerkt zu verlieren.

## Format 9: Gruppen und eingefügte Bilder

`EditorObject.groupID` ist eine optionale UUID. Gleiche IDs verbinden Objekte zu einer Gruppe; die Auswahl selbst wird nicht gespeichert. Duplikate erhalten neue Objekt- und Gruppen-IDs.

Der neue Typ `image` verlangt `imageAsset` mit SHA-256-`digest`, `size` und PNG-Daten. Andere Typen dürfen keine Bildassets tragen. Größen, PNG-Kopf und Hash werden validiert, die App dekodiert Assets zusätzlich vollständig. Limits: 4096 Pixel je Kante, 8 MB je Asset, insgesamt 16 MB PNG-Daten pro Dokument (Referenzen mehrfach gezählt).

Lokale Revisionen enthalten nur Digest und Größe. Unveränderliche PNGs liegen unter `Assets/<digest>.png`; sie werden vor Veröffentlichung der Revision geschrieben und beim Laden kontrolliert ergänzt. Unbenutzte Assets bleiben für frühere Revisionen und Undo erhalten, bis das Projekt endgültig entfernt wird. Archive und Bibliotheksbackups enthalten die PNG-Daten im eingebetteten Dokument und sind eigenständig. Import und Wiederherstellung legen die getrennten Assets wieder an. Vorhandene Symlink-/Datei- und Größenprüfungen gelten auch hier.

Formate 1–8 werden im Speicher nach 9 migriert, erst eine Änderung schreibt 9. Gruppen/Bildassets in einem fälschlich älter bezeichneten Dokument werden abgelehnt. Unbekannte zukünftige Versionen bleiben gesperrt. Paketmanifest und portable Container bleiben Version 1.

# Start über Xcode

Stand: 12. Oktober 2026. Das Projekt wird lokal mit Apple Development signiert. Kein separater Deployment-Schritt, keine Kopie nach Programme und kein Start aus einem zweiten Buildordner nötig.

1. `Snaprivo.xcodeproj` öffnen.
2. Oben Scheme **Snaprivo** und Ziel **My Mac** wählen.
3. Target → Signing & Capabilities: **Automatically manage signing**, Team **Simon Raach (24C8L59PV7)**. Debug verwendet **Apple Development**. Zertifikat und privater Schlüssel müssen im lokalen Schlüsselbund verfügbar sein.
4. **⌘R** baut und startet die App. Zum Beenden in der App ⌘Q verwenden, damit ausstehendes Autosave fertig wird. Xcodes Stop beendet den Prozess gegebenenfalls abrupt.
5. „Neue Aufnahme …“ aus Menüleiste oder Symbolleiste öffnen. **Bild** wählen, dann **Automatisch**, **Nur Fenster** oder **Bildschirm**, anschließend **Aufnehmen**. Automatisch erkennt das Fenster unter der Maus: Klicken für das Fenster, Ziehen für einen Bereich.

Für den schnellen Start enthält das Menüleisten-Icon zusätzlich direkte Bildschirm-, Bereichs- und Fensterbefehle sowie einen Bereich mit drei Sekunden Vorlauf. Globale Kürzel und deren Grenzen: [Aufnahmemenü](AUFNAHMEMENUE.md).

## Bildschirmzugriff nach dem Wechsel der Signatur

Die früheren Builds waren ad-hoc-signiert. Ihre sichtbare Freigabe in den Systemeinstellungen kann zur alten Code-Identität gehören. Die neue Apple-Development-Identität benötigt gegebenenfalls einmalig erneut die Freigabe.

In Snaprivo **Zugriff anfragen** wählen und in Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme die aktuell aus Xcode gestartete App erlauben. Verlangt macOS einen Neustart, Snaprivo vollständig beenden und mit ⌘R neu starten. Ist nur ein alter Eintrag vorhanden, diesen in den Systemeinstellungen entfernen und die neue App erneut über ihren Aufnahmeauftrag hinzufügen lassen. Diese Datenschutzentscheidung erfolgt durch den Nutzer; keine TCC-Datenbank wird bearbeitet.

Fehlt das Development-Zertifikat auf einem anderen Mac, in Xcode das eigene Team auswählen und dessen reguläre Development-Signierung einrichten. Nicht auf eine ad-hoc-Signatur oder wechselnde Bundle-ID zurückfallen, um Freigaben zu umgehen. Kein Store-Upload: dafür sind eigenes Provisioning, Distribution-Signierung und die Releaseabnahme erforderlich.

## Ein Buildort

Xcode verwendet seinen normalen DerivedData-Ordner. Das optionale `scripts/build.sh` nutzt denselben Ort und dieselbe Signierung und startet die App nicht. Der frühere Repo-Ordner `build/DerivedData` wird nicht mehr verwendet. Der lokale `build`-Ordner enthält gegebenenfalls reine Testausgaben, keine zusätzliche Snaprivo.app.

Die Bundle-ID bleibt `com.snagforge.app`, damit die vorhandene Sandbox-Bibliothek weiter genutzt wird. Die Namensentscheidung ist zurückgestellt; Projekt und Dateien werden nicht umbenannt.

Nach der Namensumstellung das bisherige Projektfenster schließen und **Snaprivo.xcodeproj** öffnen. Scheme/Target/App heißen Snaprivo; Quellordner, Domain-Modul, Bundle-ID und Bibliothekspfad bleiben kompatibel. Xcode kann wegen des neuen Projektnamens einen neuen DerivedData-Ordner verwenden. Alte Builds nicht parallel starten. macOS kann den bisherigen Namen im Datenschutzdialog zwischenspeichern; der historische Stand verwendete dieselbe App-ID. Aktuell lautet sie `com.snaprivo.app`; der frühere Container `com.snagforge.app` ist eine getrennte Identität. Siehe [Übernahme und Berechtigungen](RELEASE-WORKFLOWS-ABNAHME.md).

Aktueller Identitätsstand, 18.10.2026: `com.snaprivo.app`, Team `24C8L59PV7`. Bestehende alte Container über Einstellungen → Speicherorte → Bisherige Snaprivo-Daten übernehmen ausdrücklich auswählen. Bildschirmfreigaben werden von macOS für die aktuelle signierte Identität verwaltet; einen eingeschalteten alten Eintrag nicht als Freigabenachweis verwenden. Lokale StoreKit-Prüfungen: Scheme **SnaprivoStoreTests**, Ziel **My Mac**, ⌘U; der Testhost öffnet keine Nutzerbibliothek.

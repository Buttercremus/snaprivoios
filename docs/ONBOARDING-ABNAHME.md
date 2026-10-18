# Einführung und kontextabhängige Hinweise

Stand: 16. Oktober 2026.

Drei Schritte erklären Aufnahme, bearbeitbare Markierungen/Abdeckung und Autosave/PNG/JPEG/PDF. Illustrationen verwenden ausschließlich synthetische SwiftUI-Formen. Dekorative Bilder sind für VoiceOver ausgeblendet; Titel, Schrittstand, Erklärung und native Buttons bleiben zugänglich. Weiter mit Enter, Überspringen mit Escape, Zurück per Button. Animationen wiederholen sich nicht und sperren keine Eingabe. Bei „Bewegung reduzieren“ werden ihre Endzustände ohne Animation gezeigt.

Die Einführung erscheint nach Laden einer leeren Bildbibliothek nur ohne bisherige Aufnahme und ohne gespeicherten Abschluss. Bestehende Nutzer erreichen sie über Hilfe. Überspringen und Abschluss werden in `onboarding.completed.v1` gespeichert, ohne den Erfolg einer Aufnahme vorzutäuschen. Erst der ausdrücklich betätigte Startknopf führt nach Sheet-Schließung zum vorhandenen CaptureLauncher. Die Einführung enthält keine Capture- oder Berechtigungs-API.

Hinweise erscheinen unter der Werkzeugleiste: Auswahl erklärt Umschalt-Klick/⌘G, Pfeil/Ellipse erklären Handgezeichnet, andere Werkzeuge erklären die Ausgabe. Bestätigte Hinweise bleiben über Neustarts ausgeblendet (`onboarding.hints.v1`); Hilfe erlaubt erneutes Anzeigen. Unbestätigte Hinweise bleiben verfügbar.

Einstellungstests prüfen Abschluss, persistente Hinweisquittierung und Zurücksetzen. Vollständige VoiceOver- und systemweite Reduced-Motion-Abnahme bleiben manuell; die Implementierung berücksichtigt die SwiftUI-Umgebungsoption.

Prüfergebnis: macOS-Build, 124 Domain-Tests, Einstellungstests einschließlich Onboarding-Persistenz und Lokalisierungsprüfung bestanden. In der isolierten deutschen Test-App über Hilfe geöffnet; alle drei Schritte mit Illustrationen und Texten visuell geprüft. Weiter per Enter und Überspringen per Escape funktionieren. Auswahlhinweis quittiert, zum Pfeil gewechselt und Handzeichenhinweis gesehen; beim Zurückwechseln bleibt der quittierte Auswahlhinweis ausgeblendet. Keine echte Aufnahme und keine Berechtigungsänderung bei dieser UI-Prüfung ausgelöst. Der Startknopf ist mit dem bestehenden CaptureLauncher verbunden; dessen echte Aufnahme wurde in dieser Prüfung nicht erneut ausgeführt. Test-App beendet.

# Snaprivo Projektregeln

- Produktentscheidungen und Umfang: docs/ENTWICKLUNGSPLAN.md. Tatsächlichen Implementierungsstand in README.md aktuell halten.
- Native macOS-App, Deployment Target 26.0. Swift 6, SwiftUI für App-Oberfläche und gezieltes AppKit für präzise Mac-Interaktionen.
- App Sandbox bleibt aktiv. Nur öffentliche APIs. Keine privaten Aufnahmewege, keine Umgehung von TCC, kein Sparkle oder eigener Lizenzserver im Store-Build.
- Liquid Glass für Navigation und Bedienelemente, nicht für Bildinhalte. Native Komponenten, Tastatur und Accessibility berücksichtigen.
- Domain-Paket kennt weder UI- noch Capture-Frameworks. UI-Zustand MainActor-isolieren; intensive Verarbeitung nicht auf dem MainActor ausführen.
- Keine sensiblen Screenshots, OCR-Texte oder Signierschlüssel einchecken. Synthetische Fixtures verwenden.
- Build: ./scripts/build.sh. Domain-Tests: ./scripts/test.sh. Tests für neue Capture-, Koordinaten-, Export- und Persistenzlogik ergänzen; keine bedeutungslosen UI-Placeholder-Tests.
- APIs bei Unsicherheit im SDK und in Apple-Dokumentation prüfen. Neue Abhängigkeiten nur mit dokumentiertem Nutzen und Lizenzprüfung.
- Nicht implementierte Funktionen ehrlich kennzeichnen. Build-Erfolg ersetzt keinen Capture-, Berechtigungs- oder UX-Test auf einem echten Mac.
- Kleine überprüfbare Änderungen; keine ungefragten Veröffentlichungen. Signierung für Store erfordert Nutzer-Team und Provisioning.

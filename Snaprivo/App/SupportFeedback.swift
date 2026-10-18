import AppKit
import SwiftUI

enum SupportFeedback {
    static func destination(contact: String, version: String, build: String, bundle: Bundle = .main) -> URL? {
        let value = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isNewline }) else { return nil }
        let source = value.contains(":") ? value : "mailto:\(value)"
        guard var components = URLComponents(string: source) else { return nil }
        switch components.scheme?.lowercased() {
        case "https":
            guard components.host?.isEmpty == false else { return nil }
        case "mailto":
            let address = components.path
            let parts = address.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }),
                  !address.contains(where: { $0.isWhitespace }), components.fragment == nil else { return nil }
            components.queryItems = [
                URLQueryItem(name: "subject", value: String(localized: "Snaprivo – Support & Feedback", bundle: bundle)),
                URLQueryItem(name: "body", value: String(localized: """
                Hallo,

                meine Frage oder mein Feedback zu Snaprivo:



                ---
                Snaprivo \(version) (Build \(build))
                """, bundle: bundle))
            ]
        default: return nil
        }
        return components.url
    }

    @MainActor static func open() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? String(localized: "Entwicklungsversion")
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        let contact = bundle.object(forInfoDictionaryKey: "SnaprivoSupportURL") as? String ?? ""
        guard let url = destination(contact: contact, version: version, build: build) else {
            showError(String(localized: "Der Support-Kontakt ist in diesem Build noch nicht eingerichtet."))
            return
        }
        guard NSWorkspace.shared.open(url) else {
            showError(String(localized: "Der Support-Kontakt konnte nicht geöffnet werden. Prüfe deine Standard-App für E-Mail oder Weblinks. Du erreichst uns unter:\n\n\(contact)"))
            return
        }
    }

    @MainActor private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Support & Feedback")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}

struct SupportFeedbackButton: View {
    var body: some View {
        Button(String(localized: "Support & Feedback …"), systemImage: "bubble.left.and.bubble.right") { SupportFeedback.open() }
            .help(String(localized: "Eine Frage stellen, einen Fehler melden oder Feedback geben"))
            .accessibilityIdentifier("app.supportFeedback")
    }
}

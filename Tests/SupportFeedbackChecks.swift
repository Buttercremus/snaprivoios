import Foundation

@main struct SupportFeedbackChecks {
    static func main() throws {
        // Reserved example domain: no mail client, browser or network request is opened.
        let email = "feedback@example.com"
        let version = "0.1 & Beta", build = "2+3"
        let url = SupportFeedback.destination(contact: email, version: version, build: build)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        precondition(components.scheme == "mailto" && components.path == email)
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
        precondition(items.count == 2 && items["subject"] == "Snaprivo – Support & Feedback")
        precondition(items["body"]!.contains("Snaprivo \(version) (Build \(build))"))
        precondition(!items["body"]!.contains(NSHomeDirectory()), "Feedback template exposed local paths")
        precondition(SupportFeedback.destination(contact: "mailto:\(email)", version: version, build: build) == url)
        let web = "https://example.com/support?language=de&source=app#feedback"
        precondition(SupportFeedback.destination(contact: web, version: version, build: build)?.absoluteString == web)
        for invalid in ["", "  ", "unknown", "@example.com", "feedback@", "a b@example.com", "feedback@example.com\nBcc:other@example.com", "file:///tmp/feedback", "http://example.com", "https://", "mailto:feedback@example.com#fragment"] {
            precondition(SupportFeedback.destination(contact: invalid, version: version, build: build) == nil, "Invalid support target accepted: \(invalid)")
        }
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), format: nil) as! [String: Any]
        let configuredContact = info["SnaprivoSupportURL"] as! String
        let configured = SupportFeedback.destination(contact: configuredContact, version: version, build: build)!
        precondition(URLComponents(url: configured, resolvingAgainstBaseURL: false)?.path == "support@snaprivo.com",
                     "App bundle does not use the approved support address")
        print("Support checks passed: email/HTTPS routing, encoded subject/body/version, approved bundle address, no local paths, invalid targets rejected. No email or webpage opened.")
    }
}

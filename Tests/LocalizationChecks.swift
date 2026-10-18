import Foundation
import SnagForgeDomain

@main struct LocalizationChecks {
    @MainActor static func main() throws {
        let language = CommandLine.arguments[1]
        let english = language == "en"
        precondition(Bundle.main.preferredLocalizations.first == language, "macOS selected the wrong app language")
        precondition(AppAppearance.light.title == (english ? "Light" : "Hell"))
        precondition(EditorToolbarSize.large.title == (english ? "Large" : "Groß"))
        precondition(CaptureAction.region.title == (english ? "New Capture" : "Neue Aufnahme"))
        precondition(EditorToolbarAction.savePNG.title == (english ? "Save…" : "Speichern …"))
        precondition(ScreenshotError.noDisplays.errorDescription == (english ? "No capturable screen was found." : "Es wurde kein aufnehmbarer Bildschirm gefunden."))

        // Exercise Foundation's compiled stringsdict selection and interpolation,
        // including the singular branch and independent plural text in the same message.
        for count in [0, 1, 2, 10_000] {
            let number = count.formatted(.number.locale(.current))
            let projects = String(localized: "\(count) Projekte")
            let annotations = String(localized: "\(count) Markierungen")
            let steps = String(localized: "\(count) Schritte")
            precondition(steps == "\(number) \(english ? (count == 1 ? "step" : "steps") : (count == 1 ? "Schritt" : "Schritte"))")
            let images = String(localized: "\(count) Bilder")
            precondition(images == "\(number) \(english ? (count == 1 ? "image" : "images") : (count == 1 ? "Bild" : "Bilder"))")
            precondition(String(localized: "\(count) Videos") == "\(number) \(english ? (count == 1 ? "video" : "videos") : (count == 1 ? "Video" : "Videos"))")
            let restored = String(localized: "\(count) Videos als neue Kopien wiederhergestellt.")
            precondition(restored == (english
                ? "Restored \(number) \(count == 1 ? "video as a new copy." : "videos as new copies.")"
                : "\(number) \(count == 1 ? "Video als neue Kopie wiederhergestellt." : "Videos als neue Kopien wiederhergestellt.")"))
            let sections = String(localized: "\(count) Abschnitte")
            precondition(projects == "\(number) \(english ? (count == 1 ? "project" : "projects") : (count == 1 ? "Projekt" : "Projekte"))", "Unexpected \(language) count \(count): \(projects)")
            precondition(annotations == "\(number) \(english ? (count == 1 ? "annotation" : "annotations") : (count == 1 ? "Markierung" : "Markierungen"))")
            precondition(sections == "\(number) \(english ? (count == 1 ? "section" : "sections") : (count == 1 ? "Abschnitt" : "Abschnitte"))")
        }
        let count = 1
        precondition(String(localized: "\(count) Projekte wiederhergestellt. Vorhandene Projekte wurden beibehalten.") == (english
            ? "Restored 1 project. Existing projects have been kept."
            : "1 Projekt wiederhergestellt. Vorhandene Projekte wurden beibehalten."))
        let detail = "synthetic.png: denied & retry"
        let message = String(localized: "Das Projekt konnte nicht angelegt werden: \(detail)")
        precondition(message == (english ? "The project could not be created: \(detail)" : "Das Projekt konnte nicht angelegt werden: \(detail)"))
        let title = "Synthetic title"
        precondition(String(localized: "\(title) ausblenden") == (english ? "Hide Synthetic title" : "Synthetic title ausblenden"))
        let width = 1024, height = 395
        let size = "\(width.formatted(.number.locale(.current))) × \(height.formatted(.number.locale(.current)))"
        precondition(String(localized: "\(sectionsForOne()) · \(width) × \(height) Pixel\nPrüfe die Übergänge in der Vorschau.") == (english
            ? "1 section · \(size) pixels\nCheck the seams in the preview."
            : "1 Abschnitt · \(size) Pixel\nPrüfe die Übergänge in der Vorschau."))
        let recording = String(format: String(localized: "● Aufnahme läuft · %02d:%02d"), 1, 5)
        precondition(recording == (english ? "● Recording · 01:05" : "● Aufnahme läuft · 01:05"))
        let recordingDetail = String(localized: "\n\(width) × \(height) Pixel · \(title)\nMit Stop beenden und im Videoeditor öffnen.")
        precondition(recordingDetail == (english
            ? "\n\(size) pixels · \(title)\nChoose Stop to finish and open the video editor."
            : "\n\(size) Pixel · \(title)\nMit Stop beenden und im Videoeditor öffnen."))
        precondition(String(localized: "Mikrofon aufnehmen") == (english ? "Record microphone" : "Mikrofon aufnehmen"))
        precondition(String(localized: "Systemton und Mikrofon") == (english ? "System audio and microphone" : "Systemton und Mikrofon"))
        precondition(String(localized: "Die Videoaufnahme wurde unerwartet beendet. Bitte erneut aufnehmen.") == (english
            ? "The video recording ended unexpectedly. Please record again."
            : "Die Videoaufnahme wurde unerwartet beendet. Bitte erneut aufnehmen."))
        precondition(Bundle.main.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist") == (english
            ? "Snaprivo records your microphone only when you enable it and start a video recording. Audio stays in your local video."
            : "Snaprivo nimmt dein Mikrofon nur auf, wenn du es einschaltest und eine Videoaufnahme startest. Der Ton bleibt in deinem lokalen Video."))

        let draft = SupportFeedback.destination(contact: "feedback@example.com", version: "0.1 & Beta", build: "2+3")!
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: draft, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        precondition(query["body"]!.hasPrefix(english ? "Hello," : "Hallo,"))
        precondition(query["body"]!.contains("0.1 & Beta (Build 2+3)"))
        precondition(!query["body"]!.contains(NSHomeDirectory()))

        let domainURL = Bundle.main.resourceURL!.appendingPathComponent("SnagForgeDomain_SnagForgeDomain.bundle")
        let domainBundle = Bundle(url: domainURL)!
        precondition(domainBundle.preferredLocalizations.first == language)
        let domainMessage = String(localized: "Das Originalbild des Projekts fehlt.", bundle: domainBundle)
        precondition(domainMessage == (english ? "The original image for this project is missing." : "Das Originalbild des Projekts fehlt."))
        let scrollMessage = String(localized: "Noch kein neuer Abschnitt. Scrolle etwas nach unten und füge ihn erneut hinzu.", bundle: domainBundle)
        precondition(scrollMessage == (english ? "No new section yet. Scroll down a little and add it again." : "Noch kein neuer Abschnitt. Scrolle etwas nach unten und füge ihn erneut hinzu."))
        precondition(Bundle.main.localizedString(forKey: "Snaprivo Guide", value: nil, table: "InfoPlist") == (english ? "Snaprivo Guide" : "Snaprivo Anleitung"))
        precondition(Bundle.main.localizedString(forKey: "Snaprivo Projekt", value: nil, table: "InfoPlist") == (english ? "Snaprivo Project" : "Snaprivo Projekt"))

        let document = ProjectDocument(title: "Bibliothek – persönlicher Titel", pixelSize: PixelSize(width: 20, height: 20)!, objects: [EditorObject(kind: .text, start: .zero, text: "Abbrechen – mein Bildtext")])
        let reopened = try ProjectDocument.decode(JSONEncoder().encode(document))
        precondition(reopened == document, "Localization changed user content or persisted document fields")
        print("\(language) localization passed: native language selection, toolbar/capture/error labels, 0/1/2/10000 plurals, dynamic messages, support draft, domain bundle, file types and preserved user content.")
    }
    static func sectionsForOne() -> String { let count = 1; return String(localized: "\(count) Abschnitte") }
}

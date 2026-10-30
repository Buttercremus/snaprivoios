import Foundation
import SnagForgeDomain

@main struct LocalizationChecks {
    @MainActor static func main() throws {
        if CommandLine.arguments.dropFirst().first == "language-preference" {
            try checkStoredLanguage()
            return
        }
        let language = CommandLine.arguments[1]
        let english = language == "en"
        precondition(Bundle.main.preferredLocalizations.first == language, "macOS selected the wrong app language")
        precondition(EditorToolItem.all.first(where: { $0.tool == .magnifier })?.title == (english ? "Magnifier" : "Lupe"))
        precondition(String(localized: "Biegung") == (english ? "Bend" : "Biegung"))
        precondition(String(localized: "Vergrößerung") == (english ? "Magnification" : "Vergrößerung"))
        precondition(String(localized: "Skizze") == (english ? "Sketch" : "Skizze"))
        precondition(AppAppearance.light.title == (english ? "Light" : "Hell"))
        precondition(EditorToolbarSize.large.title == (english ? "Large" : "Groß"))
        precondition(AppLanguage.system.title == (english ? "System language" : "Systemsprache"))
        precondition(AppLanguage.german.title == (english ? "German" : "Deutsch"))
        precondition(AppLanguage.english.title == (english ? "English" : "Englisch"))
        precondition(String(localized: "Datenschutzerklärung") == (english ? "Privacy Policy" : "Datenschutzerklärung"))
        precondition(String(localized: "Speicher wird vorbereitet …") == (english ? "Preparing storage…" : "Speicher wird vorbereitet …"))
        precondition(String(localized: "Die Bildverarbeitung würde zu viel Arbeitsspeicher benötigen. Warte auf laufende Bildverarbeitungen oder wähle eine kleinere Ausgabegröße.") == (english
            ? "This image operation would require too much memory. Wait for other image operations to finish or choose a smaller output size."
            : "Die Bildverarbeitung würde zu viel Arbeitsspeicher benötigen. Warte auf laufende Bildverarbeitungen oder wähle eine kleinere Ausgabegröße."))
        precondition(String(localized: "Mit Beispiel üben") == (english ? "Try an Example" : "Mit Beispiel üben"))
        precondition(String(localized: "Erneut zeigen") == (english ? "Show Again" : "Erneut zeigen"))
        precondition(String(localized: "Animation erneut abspielen") == (english ? "Replay animation" : "Animation erneut abspielen"))
        precondition(String(localized: "Mehrere Bilder: ⌘- oder Strg-Klick") == (english ? "Multiple images: ⌘-click or Ctrl-click" : "Mehrere Bilder: ⌘- oder Strg-Klick"))
        precondition(String(localized: "Beispielbild") == (english ? "Example Image" : "Beispielbild"))
        precondition(String(localized: "Aufnahmekürzel anpassen") == (english ? "Customize capture shortcut" : "Aufnahmekürzel anpassen"))
        precondition(String(localized: "Hinweis zur Mehrfachauswahl ausblenden") == (english ? "Dismiss multiple selection hint" : "Hinweis zur Mehrfachauswahl ausblenden"))
        precondition(String(localized: "Auswahl kopieren") == (english ? "Copy Selection" : "Auswahl kopieren"))
        precondition(CaptureAction.region.title == (english ? "New Capture" : "Neue Aufnahme"))
        precondition(String(localized: "Foto-Aufnahmeart wählen") == (english ? "Choose photo capture type" : "Foto-Aufnahmeart wählen"))
        precondition(String(localized: "Scroll-Aufnahme") == (english ? "Scrolling capture" : "Scroll-Aufnahme"))
        precondition(String(localized: "Video kürzen") == (english ? "Trim Video" : "Video kürzen"))
        precondition(String(localized: "Schnitt sichern") == (english ? "Save Trim" : "Schnitt sichern"))
        precondition(String(localized: "MP4 exportieren …") == (english ? "Export MP4…" : "MP4 exportieren …"))
        precondition(String(localized: "GIF exportieren …") == (english ? "Export GIF…" : "GIF exportieren …"))
        precondition(EditorToolItem.all.first { $0.tool == .pen }?.title == (english ? "Pen" : "Stift"))
        precondition(String(localized: "Einrasten") == (english ? "Snapping" : "Einrasten"))
        precondition(String(localized: "Sensible Daten finden") == (english ? "Find Sensitive Data" : "Sensible Daten finden"))
        precondition(String(localized: "Auswahl: 1 Videobild") == (english ? "Selection: 1 frame" : "Auswahl: 1 Videobild"))
        precondition(String(localized: "Langsam nach unten scrollen · Dann Fertig.") == (english
            ? "Scroll down slowly · Then click Done."
            : "Langsam nach unten scrollen · Dann Fertig."))
        precondition(EditorToolbarAction.savePNG.title == (english ? "Export PNG…" : "PNG exportieren …"))
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
            let copied = String(localized: "\(count) Bilder kopiert")
            precondition(copied == "\(number) \(english ? (count == 1 ? "image copied" : "images copied") : (count == 1 ? "Bild kopiert" : "Bilder kopiert"))")
            let imageLoadFailure = String(localized: "\(count) Bilder konnten nicht geladen werden")
            precondition(imageLoadFailure == (english
                ? "\(number) \(count == 1 ? "image could" : "images could") not be loaded"
                : "\(number) \(count == 1 ? "Bild konnte" : "Bilder konnten") nicht geladen werden"))
            let imageOCRFailure = String(localized: "\(count) Bilder konnten nicht erkannt werden. Setze die Indexierung erneut fort.")
            precondition(imageOCRFailure == (english
                ? "\(number) \(count == 1 ? "image could" : "images could") not be recognized. Try resuming indexing."
                : "\(number) \(count == 1 ? "Bild konnte" : "Bilder konnten") nicht erkannt werden. Setze die Indexierung erneut fort."))
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
        precondition(String(localized: "Bilder durchsuchen") == (english ? "Search images" : "Bilder durchsuchen"))
        precondition(String(localized: "Bildtext erkannt: \(count) / \(count)") == (english ? "Image text recognized: 1 / 1" : "Bildtext erkannt: 1 / 1"))
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
        precondition(String(localized: "\(width) × \(height) Pixel · Wird automatisch zusammengefügt") == (english
            ? "\(size) pixels · Automatically combining"
            : "\(size) Pixel · Wird automatisch zusammengefügt"))
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
        let scrollMessage = String(localized: "Noch keine Scrollbewegung erkannt. Scrolle langsam nach unten.", bundle: domainBundle)
        precondition(scrollMessage == (english ? "No scrolling detected yet. Scroll down slowly." : "Noch keine Scrollbewegung erkannt. Scrolle langsam nach unten."))
        let movingMessage = String(localized: "Der Inhalt bewegt sich noch. Scrolle langsamer oder warte kurz.", bundle: domainBundle)
        precondition(movingMessage == (english ? "The content is still moving. Scroll more slowly or wait briefly." : "Der Inhalt bewegt sich noch. Scrolle langsamer oder warte kurz."))
        precondition(String(localized: "Bildschirm") == (english ? "Display" : "Bildschirm"))
        precondition(String(localized: "Ganzen Bildschirm auswählen") == (english ? "Select Entire Display" : "Ganzen Bildschirm auswählen"))
        let finalScrollMessage = String(localized: "Ende unklar. Übernehmen öffnet das bisherige Bild.")
        precondition(finalScrollMessage == (english ? "End unverified. Apply opens the current image." : "Ende unklar. Übernehmen öffnet das bisherige Bild."))
        precondition(Bundle.main.localizedString(forKey: "Snaprivo Guide", value: nil, table: "InfoPlist") == (english ? "Snaprivo Guide" : "Snaprivo Anleitung"))
        precondition(Bundle.main.localizedString(forKey: "Snaprivo Projekt", value: nil, table: "InfoPlist") == (english ? "Snaprivo Project" : "Snaprivo Projekt"))

        let document = ProjectDocument(title: "Bibliothek – persönlicher Titel", pixelSize: PixelSize(width: 20, height: 20)!, objects: [EditorObject(kind: .text, start: .zero, text: "Abbrechen – mein Bildtext")])
        let reopened = try ProjectDocument.decode(JSONEncoder().encode(document))
        precondition(reopened == document, "Localization changed user content or persisted document fields")
        print("\(language) localization passed: native language selection, toolbar/capture/error labels, 0/1/2/10000 plurals, dynamic messages, support draft, domain bundle, file types and preserved user content.")
    }
    @MainActor static func checkStoredLanguage() throws {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        precondition(domain.hasPrefix("com.snaprivo.localization-tests."), "Language tests must never modify the user's app preferences")
        let preferences = AppPreferences()
        switch arguments[0] {
        case "baseline":
            precondition(preferences.language == .system && !preferences.requiresLanguageRestart)
            try Bundle.main.preferredLocalizations.first!.write(toFile: arguments[1], atomically: true, encoding: .utf8)
            defaults.set("Synthetic title – unverändert", forKey: "language-test.preserved")
        case "write":
            preferences.language = AppLanguage(rawValue: arguments[1])!
            precondition(preferences.requiresLanguageRestart)
        case "read":
            let selection = AppLanguage(rawValue: arguments[1])!
            let language = arguments[2]
            precondition(preferences.language == selection && !preferences.requiresLanguageRestart)
            precondition(Bundle.main.preferredLocalizations.first == language, "Persisted language did not apply in a fresh process")
            precondition(String(localized: "Allgemein") == (language == "en" ? "General" : "Allgemein"))
            precondition(CaptureAction.region.title == (language == "en" ? "New Capture" : "Neue Aufnahme"))
            let domainBundle = Bundle(url: Bundle.main.resourceURL!.appendingPathComponent("SnagForgeDomain_SnagForgeDomain.bundle"))!
            precondition(String(localized: "Das Originalbild des Projekts fehlt.", bundle: domainBundle) == (language == "en"
                ? "The original image for this project is missing." : "Das Originalbild des Projekts fehlt."))
            precondition(defaults.string(forKey: "language-test.preserved") == "Synthetic title – unverändert")
        case "clear":
            preferences.language = .system
            precondition(preferences.requiresLanguageRestart)
            precondition(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil)
        case "read-system":
            precondition(preferences.language == .system && !preferences.requiresLanguageRestart)
            let expected = try String(contentsOfFile: arguments[1], encoding: .utf8)
            precondition(Bundle.main.preferredLocalizations.first == expected, "System language was not restored after removing the app override")
            precondition(defaults.string(forKey: "language-test.preserved") == "Synthetic title – unverändert")
        case "native-regional":
            defaults.set(["de-DE"], forKey: "AppleLanguages")
        case "cleanup":
            defaults.removePersistentDomain(forName: domain)
        default: preconditionFailure("Unknown language test phase")
        }
        print("Language preference phase \(arguments[0]) passed.")
    }
    static func sectionsForOne() -> String { let count = 1; return String(localized: "\(count) Abschnitte") }
}

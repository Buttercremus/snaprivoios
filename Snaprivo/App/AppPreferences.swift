import Foundation
import AppKit
import Observation
import SnagForgeDomain

struct CaptureRegionPreset: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let displayID: UInt32
    let screenFrame: CGRect
    let rect: CGRect
    let scale: CGFloat
    var isStructurallyValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
        !name.unicodeScalars.contains(where: { $0.value < 32 }) && displayID != 0 &&
        [screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height, rect.minX, rect.minY, rect.width, rect.height, scale].allSatisfy(\.isFinite) &&
        screenFrame.width > 1 && screenFrame.height > 1 && rect.width > 1 && rect.height > 1 &&
        (1...4).contains(scale) && screenFrame.contains(rect)
    }
    var isValidOnCurrentDisplay: Bool {
        guard isStructurallyValid else { return false }
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == displayID }) else { return false }
        return screen.frame == screenFrame && abs(screen.backingScaleFactor - scale) < 0.001 && rect.intersection(screenFrame) == rect
    }
}

enum EditorToolbarSize: String, CaseIterable {
    case compact, standard, large
    var title: String { switch self { case .compact: String(localized: "Kompakt"); case .standard: String(localized: "Standard"); case .large: String(localized: "Groß") } }
    var buttonWidth: CGFloat { switch self { case .compact: 48; case .standard: 58; case .large: 68 } }
    var buttonHeight: CGFloat { switch self { case .compact: 42; case .standard: 52; case .large: 64 } }
    var iconSize: CGFloat { switch self { case .compact: 16; case .standard: 20; case .large: 24 } }
    var labelSize: CGFloat { switch self { case .compact: 10; case .standard: 11; case .large: 12 } }
    var paletteHeight: CGFloat { buttonHeight + 16 }
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var title: String { switch self { case .system: String(localized: "System"); case .light: String(localized: "Hell"); case .dark: String(localized: "Dunkel") } }
    var appKitAppearance: NSAppearance? {
        switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}

enum AppLanguage: String, CaseIterable {
    case system, german = "de", english = "en"

    var title: String {
        switch self {
        case .system: String(localized: "Systemsprache")
        case .german: String(localized: "Deutsch")
        case .english: String(localized: "Englisch")
        }
    }

    init(preferredLanguages: [String]?) {
        guard let preferredLanguages, !preferredLanguages.isEmpty else {
            self = .system
            return
        }
        // Match regional identifiers and preference order using the same native
        // localization negotiation as the bundle. English is our fallback.
        let language = Bundle.preferredLocalizations(from: ["en", "de"], forPreferences: preferredLanguages).first
        self = language == "de" ? .german : .english
    }
}

@MainActor @Observable
final class AppPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let languageAtLaunch: AppLanguage
    var language: AppLanguage {
        didSet {
            if language == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([language.rawValue], forKey: "AppleLanguages")
            }
        }
    }
    var requiresLanguageRestart: Bool { language != languageAtLaunch }
    private var styleLibrary = EditorStyleLibrary()
    private(set) var styleLibraryError: String?
    var savedStyles: [EditorNamedStyle] { styleLibrary.styles }
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "app.appearance"); applyAppearance() }
    }
    var completedOnboarding: Bool { didSet { defaults.set(completedOnboarding, forKey: "onboarding.completed.v1") } }
    var dismissedEditorHints: Set<String> { didSet { defaults.set(dismissedEditorHints.sorted(), forKey: "onboarding.hints.v1") } }
    var completedFirstCapture: Bool { didSet { defaults.set(completedFirstCapture, forKey: "capture.completedFirstCapture") } }
    var librarySort: LibrarySort { didSet { defaults.set(librarySort.rawValue, forKey: "library.sort") } }
    var favoritesOnly: Bool { didSet { defaults.set(favoritesOnly, forKey: "library.favoritesOnly") } }
    @ObservationIgnored var onOCRIndexingChanged: ((Bool) -> Void)?
    var ocrIndexingEnabled: Bool {
        didSet {
            defaults.set(ocrIndexingEnabled, forKey: "library.ocrIndexingEnabled.v1")
            if ocrIndexingEnabled != oldValue { onOCRIndexingChanged?(ocrIndexingEnabled) }
        }
    }
    var toolbarSize: EditorToolbarSize { didSet { defaults.set(toolbarSize.rawValue, forKey: "editor.toolbarSize") } }
    var automaticallyFitsImage: Bool { didSet { defaults.set(automaticallyFitsImage, forKey: "editor.automaticallyFitsImage") } }
    private var storedToolbarTools: [AnnotationTool]
    private var storedToolbarActions: [EditorToolbarAction]
    var hiddenToolbarTools: Set<AnnotationTool> {
        didSet { defaults.set(hiddenToolbarTools.map(\.rawValue).sorted(), forKey: "editor.hiddenToolbarTools.v1") }
    }
    var hiddenToolbarActions: Set<EditorToolbarAction> {
        didSet { defaults.set(hiddenToolbarActions.map(\.rawValue).sorted(), forKey: "editor.hiddenToolbarActions.v1") }
    }
    var imageToolbarActions: [EditorToolbarAction] {
        get { toolbarActions.filter { !$0.isEditingTool } }
        set { toolbarActions = newValue + toolbarActions.filter(\.isEditingTool) }
    }
    var extraToolbarTools: [EditorToolbarAction] {
        get { toolbarActions.filter(\.isEditingTool) }
        set { toolbarActions = toolbarActions.filter { !$0.isEditingTool } + newValue }
    }
    var visibleToolbarTools: [AnnotationTool] { toolbarTools.filter { !hiddenToolbarTools.contains($0) } }
    var visibleToolbarActions: [EditorToolbarAction] { toolbarActions.filter { !hiddenToolbarActions.contains($0) } }
    var toolbarTools: [AnnotationTool] {
        get { storedToolbarTools }
        set {
            storedToolbarTools = Self.completeOrder(newValue.map(\.toolbarTool), defaults: EditorToolItem.all.map(\.tool))
            defaults.set(storedToolbarTools.map(\.rawValue), forKey: "editor.toolbarTools.v1")
        }
    }
    var toolbarActions: [EditorToolbarAction] {
        get { storedToolbarActions }
        set {
            storedToolbarActions = Self.completeOrder(newValue, defaults: EditorToolbarAction.allCases)
            defaults.set(storedToolbarActions.map(\.rawValue), forKey: "editor.toolbarActions.v1")
        }
    }
    var videoMouseClicks: Bool { didSet { defaults.set(videoMouseClicks, forKey: "capture.videoMouseClicks") } }
    var videoSystemAudio: Bool { didSet { defaults.set(videoSystemAudio, forKey: "capture.videoSystemAudio") } }
    var videoMicrophone: Bool { didSet { defaults.set(videoMicrophone, forKey: "capture.videoMicrophone") } }
    var opensVideoEditorAfterCapture: Bool { didSet { defaults.set(opensVideoEditorAfterCapture, forKey: "capture.videoDirectEditor") } }
    var captureDelay: Int { didSet { defaults.set(captureDelay, forKey: "capture.defaultDelay") } }
    var includesCursor: Bool { didSet { defaults.set(includesCursor, forKey: "capture.includesCursor") } }
    var quickPreviewAfterCapture: Bool { didSet { defaults.set(quickPreviewAfterCapture, forKey: "capture.quickPreview") } }
    var copyAfterCapture: Bool { didSet { defaults.set(copyAfterCapture, forKey: "capture.copyAfterCapture") } }
    /// Releasing a selection or clicking a window captures at once; ⌥ on release still shows the confirmation bar.
    var capturesImmediately: Bool { didSet { defaults.set(capturesImmediately, forKey: "capture.immediately") } }
    /// Guide steps captured from the guide editor receive an inline text suggestion.
    var suggestsGuideTextOnCapture: Bool { didSet { defaults.set(suggestsGuideTextOnCapture, forKey: "guides.suggestTextOnCapture") } }
    private(set) var capturePresets: [CaptureRegionPreset]

    init(defaults: UserDefaults = .standard, languageDomain: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        // Read only the app's explicit override, not the merged global language
        // list. Removing this key restores the Mac's preferred languages.
        let languages = languageDomain.flatMap { defaults.persistentDomain(forName: $0)?["AppleLanguages"] as? [String] }
        let initialLanguage = AppLanguage(preferredLanguages: languages)
        language = initialLanguage
        languageAtLaunch = initialLanguage
        videoMouseClicks = defaults.bool(forKey: "capture.videoMouseClicks")
        videoSystemAudio = defaults.bool(forKey: "capture.videoSystemAudio")
        videoMicrophone = defaults.bool(forKey: "capture.videoMicrophone")
        if let stored = defaults.object(forKey: "editor.savedStyles.v1") {
            do {
                guard let data = stored as? Data, data.count <= 512 * 1024 else { throw EditorStyleLibraryError.invalidLibrary }
                styleLibrary = try JSONDecoder().decode(EditorStyleLibrary.self, from: data).validated()
            } catch {
                styleLibraryError = String(localized: "Gespeicherte Stile konnten nicht geladen werden. Die vorhandenen Daten bleiben erhalten.")
            }
        }
        appearance = defaults.string(forKey: "app.appearance").flatMap(AppAppearance.init(rawValue:)) ?? .system
        completedOnboarding = defaults.bool(forKey: "onboarding.completed.v1")
        dismissedEditorHints = Set(defaults.stringArray(forKey: "onboarding.hints.v1") ?? [])
        completedFirstCapture = defaults.bool(forKey: "capture.completedFirstCapture")
        librarySort = defaults.string(forKey: "library.sort").flatMap(LibrarySort.init(rawValue:)) ?? .modifiedNewest
        favoritesOnly = defaults.bool(forKey: "library.favoritesOnly")
        ocrIndexingEnabled = defaults.bool(forKey: "library.ocrIndexingEnabled.v1")
        toolbarSize = defaults.string(forKey: "editor.toolbarSize").flatMap(EditorToolbarSize.init(rawValue:)) ?? .standard
        automaticallyFitsImage = defaults.object(forKey: "editor.automaticallyFitsImage") as? Bool ?? true
        storedToolbarTools = Self.completeOrder(
            (defaults.stringArray(forKey: "editor.toolbarTools.v1") ?? []).compactMap(AnnotationTool.init(rawValue:)).map(\.toolbarTool),
            defaults: EditorToolItem.all.map(\.tool))
        storedToolbarActions = Self.completeOrder(
            (defaults.stringArray(forKey: "editor.toolbarActions.v1") ?? []).compactMap(EditorToolbarAction.init(rawValue:)),
            defaults: EditorToolbarAction.allCases)
        let previousHiddenTools = Set((defaults.stringArray(forKey: "editor.hiddenToolbarTools.v1") ?? [])
            .compactMap(AnnotationTool.init(rawValue:)))
        hiddenToolbarTools = previousHiddenTools.intersection(EditorToolItem.all.map(\.tool))
        hiddenToolbarActions = Set((defaults.stringArray(forKey: "editor.hiddenToolbarActions.v1") ?? [])
            .compactMap(EditorToolbarAction.init(rawValue:)))
        let delay = defaults.integer(forKey: "capture.defaultDelay")
        captureDelay = [0, 3, 5].contains(delay) ? delay : 0
        includesCursor = defaults.bool(forKey: "capture.includesCursor")
        opensVideoEditorAfterCapture = defaults.bool(forKey: "capture.videoDirectEditor")
        quickPreviewAfterCapture = defaults.bool(forKey: "capture.quickPreview")
        copyAfterCapture = defaults.bool(forKey: "capture.copyAfterCapture")
        capturesImmediately = defaults.bool(forKey: "capture.immediately")
        suggestsGuideTextOnCapture = defaults.object(forKey: "guides.suggestTextOnCapture") as? Bool ?? true
        if let data = defaults.data(forKey: "capture.regionPresets.v1"),
           let values = try? JSONDecoder().decode([CaptureRegionPreset].self, from: data) {
            var seen = Set<UUID>()
            capturePresets = Array(values.filter { $0.isStructurallyValid && seen.insert($0.id).inserted }.prefix(20))
        } else { capturePresets = [] }
        // Migrate the previous untouched default; preserve deliberate custom orders.
        if storedToolbarActions.map(\.rawValue) == ["resize", "copy", "savePNG", "recognizeText", "share", "openWith", "pin", "colorPicker", "insertImage", "output"] {
            storedToolbarActions = EditorToolbarAction.allCases
        }
        if !defaults.bool(forKey: "editor.groupedShapes.v1") {
            // Keep Shapes available if either of its former entries was visible.
            if previousHiddenTools.contains(.rectangle), !previousHiddenTools.contains(.ellipse) {
                hiddenToolbarTools.remove(.rectangle)
            }
            defaults.set(storedToolbarTools.map(\.rawValue), forKey: "editor.toolbarTools.v1")
            defaults.set(hiddenToolbarTools.map(\.rawValue).sorted(), forKey: "editor.hiddenToolbarTools.v1")
            defaults.set(true, forKey: "editor.groupedShapes.v1")
        }

    }
    func saveCapturePreset(name: String, displayID: UInt32, screenFrame: CGRect, rect: CGRect, scale: CGFloat) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = CaptureRegionPreset(id: UUID(), name: clean, displayID: displayID, screenFrame: screenFrame, rect: rect, scale: scale)
        guard value.isStructurallyValid else { return }
        capturePresets.removeAll { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }
        capturePresets.insert(value, at: 0)
        capturePresets = Array(capturePresets.prefix(20)); persistCapturePresets()
    }
    func removeCapturePreset(_ id: UUID) { capturePresets.removeAll { $0.id == id }; persistCapturePresets() }
    func renameCapturePreset(_ id: UUID, to name: String) {
        guard let index = capturePresets.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty, clean.count <= 80, !clean.unicodeScalars.contains(where: { $0.value < 32 }), !capturePresets.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) else { return }
        capturePresets[index].name = clean; persistCapturePresets()
    }
    private func persistCapturePresets() { defaults.set(try? JSONEncoder().encode(capturePresets), forKey: "capture.regionPresets.v1") }
    func applyAppearance() { NSApp?.appearance = appearance.appKitAppearance }
    func saveStyle(name: String, style: EditorSavedStyle) throws {
        try changeStyles { try $0.add(EditorNamedStyle(name: name, style: style)) }
    }
    func renameStyle(_ id: UUID, to name: String) throws {
        try changeStyles { try $0.rename(id, to: name) }
    }
    func removeStyle(_ id: UUID) throws { try changeStyles { $0.remove(id) } }
    private func changeStyles(_ update: (inout EditorStyleLibrary) throws -> Void) throws {
        guard styleLibraryError == nil else { throw EditorStyleLibraryError.invalidLibrary }
        var next = styleLibrary
        try update(&next)
        let data = try JSONEncoder().encode(next.validated())
        defaults.set(data, forKey: "editor.savedStyles.v1")
        styleLibrary = next
    }
    func resetToolbarOrder() {
        toolbarTools = EditorToolItem.all.map(\.tool)
        toolbarActions = EditorToolbarAction.allCases
    }
    func showAllToolbarItems() {
        hiddenToolbarTools = []
        hiddenToolbarActions = []
    }
    /// Keep each supported item exactly once, appending newly introduced items on upgrade.
    private static func completeOrder<Item: Hashable>(_ order: [Item], defaults: [Item]) -> [Item] {
        var seen = Set<Item>()
        let supported = Set(defaults)
        return (order + defaults).filter { supported.contains($0) && seen.insert($0).inserted }
    }
    var captureConfiguration: CaptureConfiguration {
        CaptureConfiguration(includesCursor: includesCursor, delaySeconds: captureDelay)
    }
}

enum EditorToolbarAction: String, CaseIterable, Identifiable {
    case copy, savePNG, recognizeText, share, pin, openWith, resize, output, colorPicker, insertImage, presentation, transform, scanCode
    var isEditingTool: Bool { [.colorPicker, .insertImage, .resize, .recognizeText, .presentation, .transform, .scanCode].contains(self) }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .presentation: String(localized: "Gestaltung")
        case .transform: String(localized: "Drehen")
        case .scanCode: String(localized: "QR lesen")
        case .output: String(localized: "Bildausgabe")
        case .insertImage: String(localized: "Bild einfügen")
        case .colorPicker: String(localized: "Pipette")
        case .pin: String(localized: "Anheften")
        case .resize: String(localized: "Bildgröße …")
        case .recognizeText: String(localized: "Text erkennen")
        case .copy: String(localized: "Kopieren")
        case .savePNG: String(localized: "PNG exportieren …")
        case .share: String(localized: "Teilen")
        case .openWith: String(localized: "Öffnen mit …")
        }
    }
    var symbol: String {
        switch self {
        case .presentation: "photo.artframe"
        case .transform: "rotate.right"
        case .scanCode: "qrcode.viewfinder"
        case .output: "square.and.arrow.up.on.square"
        case .insertImage: "photo.badge.plus"
        case .colorPicker: "eyedropper"
        case .pin: "pin"
        case .resize: "arrow.up.left.and.arrow.down.right.square"
        case .recognizeText: "text.viewfinder"
        case .copy: "doc.on.doc"
        case .savePNG: "square.and.arrow.down"
        case .share: "square.and.arrow.up"
        case .openWith: "arrow.up.forward.app"
        }
    }
}


enum LibrarySort: String, CaseIterable {
    case modifiedNewest, modifiedOldest, nameAscending, nameDescending
    var title: String { switch self {
    case .modifiedNewest: String(localized: "Zuletzt geändert")
    case .modifiedOldest: String(localized: "Älteste Änderung zuerst")
    case .nameAscending: String(localized: "Name A–Z")
    case .nameDescending: String(localized: "Name Z–A")
    } }
    func ordered(_ items: [ProjectLibraryItem]) -> [ProjectLibraryItem] {
        items.sorted {
            if self == .modifiedNewest || self == .modifiedOldest {
                if $0.document.modifiedAt != $1.document.modifiedAt {
                    return self == .modifiedNewest ? $0.document.modifiedAt > $1.document.modifiedAt : $0.document.modifiedAt < $1.document.modifiedAt
                }
            } else {
                let result = $0.document.title.localizedStandardCompare($1.document.title)
                if result != .orderedSame { return self == .nameAscending ? result == .orderedAscending : result == .orderedDescending }
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

extension AnnotationTool {
    /// Ellipses retain their drawing behavior and share the Shapes toolbar entry.
    var toolbarTool: Self { self == .ellipse ? .rectangle : self }
}

struct EditorToolItem: Identifiable {
    let tool: AnnotationTool
    let title: String
    let symbol: String
    let hint: String
    var id: String { tool.rawValue }

    static let all: [Self] = [
        .init(tool: .selection, title: String(localized: "Auswahl"), symbol: "cursorarrow", hint: String(localized: "Objekte anklicken oder auf freier Fläche einen Auswahlrahmen ziehen. Umschalt ergänzt die Auswahl.")),
        .init(tool: .arrow, title: String(localized: "Pfeil"), symbol: "arrow.up.right", hint: String(localized: "Pfeil aufziehen; Umschalt hält die Richtung in 45°-Schritten")),
        .init(tool: .text, title: String(localized: "Text"), symbol: "textformat", hint: String(localized: "Ins Bild klicken, um Text einzufügen")),
        .init(tool: .callout, title: String(localized: "Callout"), symbol: "text.bubble", hint: String(localized: "Sprechblase mit Live-Vorschau aufziehen, dann Text eingeben")),
        .init(tool: .rectangle, title: String(localized: "Formen"), symbol: "square.on.circle", hint: String(localized: "Form rechts wählen und im Bild aufziehen")),
        .init(tool: .highlight, title: String(localized: "Markieren"), symbol: "highlighter", hint: String(localized: "Rechteckigen Bereich markieren oder freihändig mit dem Textmarker zeichnen")),
        .init(tool: .steps, title: String(localized: "Liste"), symbol: "list.number", hint: String(localized: "Klicken setzt die nächste Zahl oder den nächsten Buchstaben")),
        .init(tool: .pen, title: String(localized: "Stift"), symbol: "pencil.tip", hint: String(localized: "Freihändig mit geglätteten Strichen zeichnen")),
        .init(tool: .spotlight, title: String(localized: "Spotlight"), symbol: "light.max", hint: String(localized: "Fokusbereich aufziehen und die Umgebung abdunkeln")),
        .init(tool: .magnifier, title: String(localized: "Lupe"), symbol: "plus.magnifyingglass", hint: String(localized: "Bilddetails mit normaler oder versetzter Lupe vergrößern")),
        .init(tool: .blur, title: String(localized: "Unschärfe"), symbol: "drop.halffull", hint: String(localized: "Einen Bereich für Unschärfe aufziehen")),
        .init(tool: .redact, title: String(localized: "Abdecken"), symbol: "rectangle.fill", hint: String(localized: "Vertrauliche Inhalte für PNG und Zwischenablage deckend abdecken")),
        .init(tool: .crop, title: String(localized: "Zuschneiden"), symbol: "crop", hint: String(localized: "Ausschnitt aufziehen und mit Eingabe bestätigen (⌘K)"))
    ]
}


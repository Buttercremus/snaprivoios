import AppKit
import SwiftUI
import SnagForgeDomain

@MainActor private final class GuideQAStore: ProStoreClient {
    func offer() async throws -> ProOffer? { nil }
    func entitled() async throws -> Bool { true }
    func purchase() async throws -> ProPurchaseOutcome { .cancelled }
    func restore() async throws { }
    func updates() -> AsyncStream<Void> { AsyncStream { _ in } }
}

/// Production views and commands, with disposable images and a local fake entitlement.
@MainActor enum GuideWorkflowFixture {
    static func content(workspace: WorkspaceModel) -> some View {
        WorkspaceView(workspace: workspace)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
    }
    static func makeWorkspace() -> WorkspaceModel {
        let defaults = UserDefaults(suiteName: "com.snaprivo.guideworkflowqa.\(UUID())")!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        let workspace = WorkspaceModel(root: FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-GuideUI-\(UUID())"), defaults: defaults,
                                       purchases: ProPurchaseModel(client: GuideQAStore()))
        defaults.set(true, forKey: "onboarding.completed.v1")
        Task {
            do {
                await workspace.purchases.start()
                workspace.preferences.completedOnboarding = true
                workspace.preferences.completedFirstCapture = true
                var ids: [UUID] = []
                let titles = ["Einstellungen öffnen", "Benachrichtigungen aktivieren", "Änderungen prüfen"]
                for (index, title) in titles.enumerated() {
                    let image = screenshot(index: index)
                    let document = ProjectDocument(title: title, pixelSize: PixelSize(width: image.width, height: image.height)!)
                    try await workspace.store.create(document, original: EditorRenderer.png(image: image, objects: []), thumbnail: EditorRenderer.thumbnail(image: image, objects: []))
                    ids.append(document.id)
                }
                await workspace.refreshLibrary()
                workspace.createGuide(from: ids)
                _ = await workspace.guides.finishPendingWork()
                workspace.guides.edit {
                    $0.title = "Benachrichtigungen einrichten"
                    $0.introduction = "In drei Schritten passt du die Benachrichtigungen an."
                    $0.style = .compact; $0.includesCover = false
                    $0.steps[0].caption = "Öffne die Einstellungen über das Zahnrad."
                    $0.steps[1].caption = "Aktiviere die gewünschte Option."
                    $0.steps[2].caption = "Prüfe deine Auswahl und schließe die Einstellungen."
                }
                await workspace.guides.flush()
                try await workspace.guides.store.create(GuideDocument(title: "Weitere Beispielanleitung"))
                await workspace.guides.refresh()
            } catch { workspace.importError = error.localizedDescription }
        }
        return workspace
    }
    private static func screenshot(index: Int) -> CGImage {
        let image = NSImage(size: NSSize(width: 1200, height: 700))
        image.lockFocus()
        NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1200, height: 700).fill()
        NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 160, y: 80, width: 880, height: 540), xRadius: 16, yRadius: 16).fill()
        ("Einstellungen" as NSString).draw(at: NSPoint(x: 210, y: 545), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.black])
        for (row, title) in ["Benachrichtigungen", "Vorschau anzeigen", "Ton abspielen"].enumerated() {
            let y = CGFloat(440 - row * 110)
            (title as NSString).draw(at: NSPoint(x: 210, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.darkGray])
            (index > 0 ? NSColor.systemBlue : NSColor.lightGray).setFill()
            NSBezierPath(roundedRect: NSRect(x: 885, y: y, width: 80, height: 36), xRadius: 18, yRadius: 18).fill()
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: index > 0 ? 931 : 889, y: y + 4, width: 28, height: 28)).fill()
        }
        image.unlockFocus()
        var rect = NSRect(x: 0, y: 0, width: 1200, height: 700)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }
}

import AppKit
import SwiftUI
import SnagForgeDomain

@MainActor private final class CaptureToolsStore: ProStoreClient {
    var continuation: AsyncStream<Void>.Continuation?
    func offer() async throws -> ProOffer? { ProOffer(name: "Snaprivo Pro", price: "Synthetic", laterPrice: "Synthetic") }
    func entitled() async throws -> Bool { true }
    func purchase() async throws -> ProPurchaseOutcome { .purchased }
    func restore() async throws {}
    func updates() -> AsyncStream<Void> { AsyncStream { continuation = $0 } }
}

@main struct CaptureToolsUI: App {
    @Environment(\.openWindow) private var openWindow
    @State private var workspace: WorkspaceModel
    @State private var prepared = false

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-CaptureToolsUI-\(UUID())")
        let defaults = UserDefaults(suiteName: "Snaprivo-CaptureToolsUI-\(UUID())")!
        let purchases = ProPurchaseModel(client: CaptureToolsStore())
        _workspace = State(initialValue: WorkspaceModel(root: root, defaults: defaults, purchases: purchases))
    }

    var body: some Scene {
        Window("Snaprivo · Werkzeuge prüfen", id: "workspace") {
            WorkspaceView(workspace: workspace)
                .task {
                    guard !prepared else { return }
                    prepared = true
                    workspace.captureShortcuts.setEnabled(false)
                    workspace.preferences.completedOnboarding = true
                    workspace.preferences.completedFirstCapture = true
                    await workspace.purchases.start()
                    let image = syntheticDashboard()
                    workspace.openScreenshot(image)
                    while workspace.isLoading { try? await Task.sleep(for: .milliseconds(10)) }
                    workspace.section = .editor
                    if let editor = workspace.editor {
                        let asset = try! EditorImageAsset(png: EditorRenderer.png(image: image, objects: []), size: PixelSize(width: image.width, height: image.height)!)
                        var inserted = EditorObject(kind: .image, start: CGPoint(x: 640, y: 360), end: CGPoint(x: 940, y: 550))
                        inserted.imageAsset = asset
                        editor.commit([inserted]); editor.selectObjectFromList(inserted.id)
                        if CommandLine.arguments.contains("--text") { editor.beginInlineTextRecognition() }
                        // Make the new tools visible to exercise real controls in this fixture.
                        workspace.preferences.toolbarTools = [.selection, .arrow, .text]
                        workspace.preferences.hiddenToolbarTools = Set(EditorToolItem.all.map(\.tool)).subtracting([.selection, .arrow, .text])
                        workspace.preferences.extraToolbarTools = [.presentation, .transform, .recognizeText, .scanCode, .resize, .insertImage, .colorPicker]

                    }
                    if !CommandLine.arguments.contains("--editor-only") {
                        workspace.preferences.quickPreviewAfterCapture = true
                        workspace.openScreenshot(image)
                        if CommandLine.arguments.contains("--stack") {
                            while workspace.isLoading { try? await Task.sleep(for: .milliseconds(10)) }
                            for _ in 0..<2 {
                                workspace.openScreenshot(image)
                                while workspace.isLoading { try? await Task.sleep(for: .milliseconds(10)) }
                            }
                        }
                        if CommandLine.arguments.contains("--text-result") {
                            workspace.recognizeCapturedText(image, codesOnly: false, recognize: { _, _ in
                                try await Task.sleep(for: .milliseconds(1500))
                                return .init(text: "Snaprivo synthetic text capture.\nCopy this text with Command-V.", codes: [])
                            }, copy: { _ in true })
                        }
                        // Focus only this fixture's synthetic preview so UI inspection
                        // can select the non-activating panel without touching other apps.
                        for _ in 0..<100 {
                            if let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.title == String(localized: "Aufnahme bereit") }), panel.isVisible {
                                panel.makeKeyAndOrderFront(nil); break
                            }
                            try? await Task.sleep(for: .milliseconds(10))
                        }
                    }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandMenu("Fixture") {
                Button("Schnellvorschau zeigen") {
                    workspace.preferences.quickPreviewAfterCapture = true
                    workspace.openScreenshot(syntheticDashboard())
                }
            }
        }
        Window("Snaprivo Pro", id: "pro") {
            ProPaywallView(model: workspace.purchases, feature: workspace.requestedProFeature)
        }.defaultLaunchBehavior(.suppressed)
    }

    private func syntheticDashboard() -> CGImage {
        let width = 960, height = 600
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.13, blue: 0.31, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 60, y: 90, width: 840, height: 430))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSString(string: "Synthetic filter preview").draw(at: CGPoint(x: 60, y: 550), withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.labelColor])
        for (index, title) in ["Soft", "Pixel", "Mosaic"].enumerated() {
            let y = 430 - index * 120
            NSString(string: title).draw(at: CGPoint(x: 100, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.white])
            NSString(string: "DEMO 1234 5678 9012").draw(at: CGPoint(x: 290, y: y), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }
}

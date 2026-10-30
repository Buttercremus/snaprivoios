import AppKit
import SwiftUI
import SnagForgeDomain

@MainActor private final class BlurPolishStore: ProStoreClient {
    var continuation: AsyncStream<Void>.Continuation?
    func offer() async throws -> ProOffer? { ProOffer(name: "Snaprivo Pro", price: "Synthetic", laterPrice: "Synthetic") }
    func entitled() async throws -> Bool { true }
    func purchase() async throws -> ProPurchaseOutcome { .purchased }
    func restore() async throws {}
    func updates() -> AsyncStream<Void> { AsyncStream { continuation = $0 } }
}

@main struct BlurPolishUI: App {
    @Environment(\.openWindow) private var openWindow
    @State private var workspace: WorkspaceModel
    @State private var prepared = false

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-BlurPolishUI-\(UUID())")
        let defaults = UserDefaults(suiteName: "Snaprivo-BlurPolishUI-\(UUID())")!
        let purchases = ProPurchaseModel(client: BlurPolishStore())
        _workspace = State(initialValue: WorkspaceModel(root: root, defaults: defaults, purchases: purchases))
    }

    var body: some Scene {
        Window("Snaprivo · CleanShot Feature Fixture", id: "workspace") {
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
                        var objects: [EditorObject] = []
                        for (index, style) in EditorBlurStyle.allCases.enumerated() {
                            var object = EditorObject(kind: .blur, start: CGPoint(x: 285, y: 130 + index * 120), end: CGPoint(x: 850, y: 180 + index * 120))
                            object.blurStyle = style; object.blurRadius = 20; objects.append(object)
                        }
                        editor.commit(objects); editor.selectObjectFromList(objects[1].id)
                    }
                    if CommandLine.arguments.contains("--quick") {
                        workspace.preferences.quickPreviewAfterCapture = true
                        workspace.openScreenshot(image)
                    }
                }
        }
        .defaultSize(width: 1180, height: 780)
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

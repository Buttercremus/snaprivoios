import AppKit
import SwiftUI
import SnagForgeDomain

@MainActor private final class CleanShotFeatureStore: ProStoreClient {
    var continuation: AsyncStream<Void>.Continuation?
    func offer() async throws -> ProOffer? { ProOffer(name: "Snaprivo Pro", price: "Synthetic", laterPrice: "Synthetic") }
    func entitled() async throws -> Bool { true }
    func purchase() async throws -> ProPurchaseOutcome { .purchased }
    func restore() async throws {}
    func updates() -> AsyncStream<Void> { AsyncStream { continuation = $0 } }
}

@main struct CleanShotFeatureUI: App {
    @Environment(\.openWindow) private var openWindow
    @State private var workspace: WorkspaceModel
    @State private var prepared = false

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-CleanShotFeatureUI-\(UUID())")
        let defaults = UserDefaults(suiteName: "Snaprivo-CleanShotFeatureUI-\(UUID())")!
        let purchases = ProPurchaseModel(client: CleanShotFeatureStore())
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
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 60, y: 48, width: 840, height: 500))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        NSString(string: "Revenue overview").draw(at: CGPoint(x: 96, y: 500), withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1)])
        NSString(string: "Synthetic dashboard · October 2026").draw(at: CGPoint(x: 96, y: 470), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor])
        NSGraphicsContext.restoreGraphicsState()
        context.setStrokeColor(NSColor.systemBlue.cgColor); context.setLineWidth(5); context.move(to: CGPoint(x: 110, y: 180))
        for point in [CGPoint(x: 220, y: 260), CGPoint(x: 330, y: 230), CGPoint(x: 450, y: 340), CGPoint(x: 570, y: 320), CGPoint(x: 700, y: 420), CGPoint(x: 820, y: 390)] { context.addLine(to: point) }
        context.strokePath(); return context.makeImage()!
    }
}

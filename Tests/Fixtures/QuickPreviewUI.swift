import AppKit
import CoreImage
import SwiftUI
import SnagForgeDomain

@MainActor private final class QuickPreviewStore: ProStoreClient {
    func offer() async throws -> ProOffer? { nil }
    func entitled() async throws -> Bool { true }
    func purchase() async throws -> ProPurchaseOutcome { .purchased }
    func restore() async throws {}
    func updates() -> AsyncStream<Void> { AsyncStream { _ in } }
}

@MainActor private final class QuickPreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Exercises actual SwiftUI window classes and thumbnail controls without TCC or user images.
@main struct QuickPreviewUI: App {
    @NSApplicationDelegateAdaptor(QuickPreviewDelegate.self) private var delegate
    @State private var workspace: WorkspaceModel
    @State private var prepared = false
    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-QuickPreviewUI-\(UUID())")
        let defaults = UserDefaults(suiteName: "Snaprivo-QuickPreviewUI-\(UUID())")!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        _workspace = State(initialValue: WorkspaceModel(root: root, defaults: defaults,
            purchases: ProPurchaseModel(client: QuickPreviewStore())))
    }
    var body: some Scene {
        Window("Snaprivo · Miniaturprüfung", id: "workspace") {
            WorkspaceView(workspace: workspace).onAppear {
                guard !prepared else { return }; prepared = true
                Task { @MainActor in
                    workspace.preferences.completedOnboarding = true; workspace.preferences.completedFirstCapture = true
                    workspace.preferences.copyAfterCapture = false
                    await workspace.purchases.start()
                    workspace.openScreenshot(syntheticImage())
                    while workspace.isLoading { try? await Task.sleep(for: .milliseconds(10)) }
                    workspace.section = .editor
                    capturePreview(count: 3)
                }
            }
        }.defaultSize(width: 1000, height: 720)
        .commands {
            CommandMenu("Fixture") {
                Button("Neue synthetische Vorschau") { capturePreview() }
                Button("Vorschau zeigen") { QuickCapturePanelController.shared.restore() }
            }
        }
        MenuBarExtra("Snaprivo Prüfvorschau", systemImage: "photo") {
            Button("Vorschau zeigen") { QuickCapturePanelController.shared.restore() }
            Button("Prüf-App beenden") { NSApp.terminate(nil) }
        }
    }
    private func capturePreview(count: Int = 1) {
        workspace.preferences.quickPreviewAfterCapture = true
        let hidden = NSApp.windows.filter { $0.isVisible && $0.level.rawValue < NSWindow.Level.statusBar.rawValue }
        hidden.forEach { $0.orderOut(nil) }
        ScreenshotCoordinator.restoreAfterImageCapture(hidden, opensEditor: false)
        Task { @MainActor in
            for _ in 0..<count {
                workspace.openScreenshot(syntheticImage())
                while workspace.isLoading { try? await Task.sleep(for: .milliseconds(10)) }
            }
            // Only this synthetic fixture focuses the panel, so accessibility
            // inspection can bind it while its real workspace stays hidden.
            QuickCapturePanelController.shared.restore()
        }
    }
    private func syntheticImage() -> CGImage {
        let context = CGContext(data: nil, width: 800, height: 440, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 800, height: 440))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSString(string: "SNAPRIVO TEXT 42").draw(at: CGPoint(x: 36, y: 335), withAttributes: [.font: NSFont.systemFont(ofSize: 46, weight: .semibold), .foregroundColor: NSColor.black])
        NSString(string: "Synthetic preview · Text and QR").draw(at: CGPoint(x: 36, y: 278), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState()
        let filter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.com/synthetic-preview".utf8), "inputCorrectionLevel": "M"])!
        let qr = filter.outputImage!.transformed(by: .init(scaleX: 6, y: 6))
        if let code = CIContext().createCGImage(qr, from: qr.extent) { context.interpolationQuality = .none; context.draw(code, in: CGRect(x: 36, y: 40, width: 180, height: 180)) }
        return context.makeImage()!
    }
}

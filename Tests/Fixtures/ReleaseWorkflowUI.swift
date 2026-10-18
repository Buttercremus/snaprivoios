import SwiftUI
import SnagForgeDomain

@MainActor private final class WorkflowUIStore: ProStoreClient {
    var owns = CommandLine.arguments.contains("--pro")
    var continuation: AsyncStream<Void>.Continuation?
    func offer() async throws -> ProOffer? {
        if CommandLine.arguments.contains("--unavailable-price") { return nil }
        let regular = CommandLine.arguments.contains("--regular-price")
        let style = Decimal.FormatStyle.Currency(code: "EUR", locale: Locale(identifier: "de_DE"))
        let amount = regular ? ProOffer.regularPrice : ProOffer.launchPrice
        return ProOffer(name: "Snaprivo Pro", price: amount.formatted(style), laterPrice: ProOffer.laterPrice(displayPrice: amount.formatted(style), style: style))
    }
    func entitled() async throws -> Bool { owns }
    func purchase() async throws -> ProPurchaseOutcome { owns = true; continuation?.yield(()); return .purchased }
    func restore() async throws {}
    func updates() -> AsyncStream<Void> { AsyncStream { continuation = $0 } }
}

@main struct ReleaseWorkflowUI: App {
    @Environment(\.openWindow) private var openWindow
    @State private var workspace = WorkspaceModel(root: FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-WorkflowUI-\(UUID())"), defaults: UserDefaults(suiteName: "Snaprivo-WorkflowUI")!, purchases: ProPurchaseModel(client: WorkflowUIStore()))
    @State private var prepared = false
    var body: some Scene {
        Window("Snaprivo · Synthetic Workflow Checks", id: "workspace") {
            WorkspaceView(workspace: workspace).task {
                workspace.showPaywallWindow = { AppWindows.show("pro", using: openWindow) }
                guard !prepared else { return }; prepared = true
                workspace.preferences.completedOnboarding = true
                workspace.preferences.completedFirstCapture = true
                for index in 0..<3 {
                    let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.setFillColor(CGColor(red: 0.12 + Double(index) * 0.1, green: 0.22, blue: 0.38, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
                    workspace.openScreenshot(context.makeImage()!)
                    while workspace.isLoading { try? await Task.sleep(for: .milliseconds(10)) }
                    workspace.editor?.commit([EditorObject(kind: .arrow, start: CGPoint(x: 140, y: 220), end: CGPoint(x: 660, y: 440)), EditorObject(kind: .text, start: CGPoint(x: 140, y: 140), text: "Synthetic workflow \(index + 1)", fontSize: 42)])
                    _ = workspace.editor?.renameObject(workspace.editor!.history.objects[0].id, name: "Explanation arrow")
                    _ = await workspace.editor?.flush()
                }
                workspace.section = .editor
            }
        }.defaultSize(width: 1180, height: 780)
        Window("Snaprivo Pro", id: "pro") {
            ProPaywallView(model: workspace.purchases, feature: workspace.requestedProFeature)
        }.windowResizability(.contentSize).defaultLaunchBehavior(.suppressed)
        Settings { SettingsView(workspace: workspace) }
    }
}

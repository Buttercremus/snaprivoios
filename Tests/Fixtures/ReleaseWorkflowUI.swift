import SwiftUI
import SnagForgeDomain

@main struct ReleaseWorkflowUI: App {
    @State private var workspace = WorkspaceModel(root: FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-WorkflowUI-\(UUID())"), defaults: UserDefaults(suiteName: "Snaprivo-WorkflowUI")!)
    @State private var prepared = false
    var body: some Scene {
        Window("Snaprivo · Synthetic Workflow Checks", id: "workspace") {
            WorkspaceView(workspace: workspace).task {
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
        Settings { SettingsView(workspace: workspace) }
    }
}

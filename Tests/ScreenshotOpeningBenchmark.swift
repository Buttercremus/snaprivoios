import AppKit
import SnagForgeDomain

/// Measures model readiness with synthetic pixels, never the user's desktop/library.
@MainActor enum ScreenshotOpeningBenchmark {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotOpening-\(UUID())")
        let suite = "ScreenshotOpening-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        workspace.preferences.completedFirstCapture = true
        let context = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in stride(from: 0, to: 2160, by: 24) {
            context.setFillColor(NSColor(srgbRed: Double(y % 255) / 255, green: 0.4, blue: 0.8, alpha: 1).cgColor)
            context.fill(CGRect(x: y % 120, y: y, width: 3700, height: 20))
        }
        let image = context.makeImage()!, thumbnail = try EditorRenderer.thumbnail(image: image, objects: [])
        let original = try EditorRenderer.png(image: image, objects: [])
        for index in 0..<500 {
            let document = ProjectDocument(title: "Synthetic \(index)", pixelSize: PixelSize(width: 3840, height: 2160)!)
            // The unrelated originals are not decoded during this workload.
            try await workspace.store.create(document, original: index == 0 ? original : Data([1]), thumbnail: thumbnail)
        }
        await workspace.refreshLibrary()
        func milliseconds(since start: ContinuousClock.Instant) -> Double {
            let duration = start.duration(to: .now).components
            return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        }
        for dirty in [false, true] {
            var visible: [Double] = [], ready: [Double] = []
            for iteration in 0..<13 {
                if dirty, let editor = workspace.editor {
                    editor.commit((0..<30).map { index in
                        EditorObject(kind: .arrow, start: CGPoint(x: index * 80, y: 100), end: CGPoint(x: index * 80 + 90, y: 800))
                    })
                }
                let previousID = workspace.editor?.document.id, start = ContinuousClock.now
                workspace.openScreenshot(image)
                while workspace.editor?.document.id == previousID {
                    precondition(milliseconds(since: start) < 15_000, "Screenshot did not open: \(workspace.importError ?? "timeout")")
                    try await Task.sleep(for: .milliseconds(1))
                }
                let opened = milliseconds(since: start)
                while workspace.isLoading { try await Task.sleep(for: .milliseconds(1)) }
                precondition(workspace.importError == nil && workspace.editor?.isDirty == false)
                precondition(workspace.items.contains { $0.id == workspace.editor?.document.id })
                if iteration > 0 { visible.append(opened); ready.append(milliseconds(since: start)) }
            }
            func report(_ values: [Double]) -> String {
                "median \(Int(values.sorted()[values.count / 2])) ms, max \(Int(values.max()!)) ms"
            }
            print("4K screenshot, 500 existing projects, previous editor \(dirty ? "dirty" : "clean"), 12 warm opens: published \(report(visible)); ready for next capture \(report(ready))")
        }
        print("Model timings only; excludes shortcut dispatch, ScreenCaptureKit, selection and first rendered frame. No cold-launch or p95 claim.")
    }
}

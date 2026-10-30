import AppKit
import SnagForgeDomain

/// Reproducible library-click readiness timings; no user images or UI automation.
@main struct ProjectOpeningBenchmark {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectOpening-\(UUID())")
        let suite = "ProjectOpening-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        workspace.preferences.ocrIndexingEnabled = false
        workspace.preferences.completedFirstCapture = true
        let context = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        for y in stride(from: 0, to: 2160, by: 18) {
            context.setFillColor(NSColor(srgbRed: Double(y % 251) / 251, green: 0.3, blue: 0.6, alpha: 1).cgColor)
            for x in stride(from: 0, to: 3840, by: 80) { context.fill(CGRect(x: x + y % 19, y: y, width: 12 + (x + y) % 55, height: 13)) }
        }
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        var blurObjects: [EditorObject] = []
        for index in 0..<3 {
            var blur = EditorObject(kind: .blur, start: CGPoint(x: 180 + index * 700, y: 220 + index * 350), end: CGPoint(x: 1080 + index * 700, y: 820 + index * 350))
            blur.blurRadius = 14; blur.blurStyle = [.gaussian, .pixelate, .mosaic][index]
            blurObjects.append(blur)
        }
        let plain = (0..<2).map { ProjectDocument(title: "Synthetic plain \($0)", pixelSize: PixelSize(width: 3840, height: 2160)!) }
        let filtered = (0..<2).map { ProjectDocument(title: "Synthetic filtered \($0)", pixelSize: plain[0].pixelSize, objects: blurObjects) }
        for document in plain + filtered { try await workspace.store.create(document, original: original, thumbnail: nil) }
        await workspace.refreshLibrary()
        func elapsed(_ start: ContinuousClock.Instant) -> Double {
            let duration = start.duration(to: .now)
            return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        func report(_ values: [Double]) -> String {
            let ordered = values.sorted()
            return "median=\(String(format: "%.2f", ordered[ordered.count / 2]))ms max=\(String(format: "%.2f", ordered.last!))ms"
        }
        for (name, documents, dirty) in [("plain", plain, false), ("filtered", filtered, false), ("plain-dirty-outgoing", plain, true)] {
            let startRead = ContinuousClock.now, loaded = try await workspace.store.load(documents[0].id)
            let read = elapsed(startRead)
            let phases = try await Task.detached(priority: .userInitiated) {
                let decodeStart = ContinuousClock.now
                let source = CGImageSourceCreateWithData(loaded.original as CFData, nil)!
                let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
                let decode = decodeStart.duration(to: .now)
                let prepareStart = ContinuousClock.now
                _ = try EditorCanvasPreparation.prepare(image: decoded, document: loaded.document)
                return (decode, prepareStart.duration(to: .now))
            }.value
            func ms(_ duration: Duration) -> Double { Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15 }
            print("\(name) independent phases: read=\(String(format: "%.2f", read))ms decode=\(String(format: "%.2f", ms(phases.0)))ms prepare=\(String(format: "%.2f", ms(phases.1)))ms")
            var first: [Double] = [], warm: [Double] = []
            for iteration in 0..<14 {
                if dirty, let editor = workspace.editor {
                    editor.commit((0..<30).map { EditorObject(kind: .arrow, start: CGPoint(x: 20 + $0 * 60, y: 20), end: CGPoint(x: 80 + $0 * 60, y: 600)) })
                }
                workspace.section = .library
                let document = documents[iteration % 2], start = ContinuousClock.now
                workspace.openProject(document.id)
                while workspace.isLoading {
                    precondition(elapsed(start) < 15_000, "Project did not open")
                    try await Task.sleep(for: .milliseconds(1))
                }
                precondition(workspace.importError == nil && workspace.editor?.document.id == document.id)
                precondition(workspace.editor?.image.width == 3840 && workspace.editor?.image.height == 2160)
                if name == "filtered" { precondition(workspace.editor?.initialCanvas?.blurPatches.count == 3) }
                if iteration < 2 { first.append(elapsed(start)) } else { warm.append(elapsed(start)) }
            }
            print("\(name) first two=\(first.map { String(format: "%.2f", $0) }.joined(separator: ","))ms; 12 warm library opens \(report(warm))")
        }
        print("Model ready, 4K synthetic PNG, 1ms polling; excludes first drawn frame and true cold-disk/launch latency. No p95 claim.")
    }
}

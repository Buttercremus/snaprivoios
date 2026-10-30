import AppKit
import SnagForgeDomain

/// A deliberately slow native-style worker. Cancellation is observed while the result
/// remains held, so tests can also verify that a late result is never published.
private final class RenderCancellationGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var cancelled = false
    private var released = false
    private var file: URL?
    var hasStarted: Bool { condition.lock(); defer { condition.unlock() }; return entered }
    var sawCancellation: Bool { condition.lock(); defer { condition.unlock() }; return cancelled }
    var preparedFile: URL? { condition.lock(); defer { condition.unlock() }; return file }
    func hold(file: URL? = nil) {
        condition.lock(); defer { condition.unlock() }
        entered = true; self.file = file
        while !released {
            if Task.isCancelled { cancelled = true }
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.005))
        }
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}

@MainActor enum RenderCancellationChecks {
    private static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("Native render cancellation condition timed out")
    }
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RenderCancellation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        func solid(_ color: NSColor) -> CGImage {
            let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
            return context.makeImage()!
        }
        let red = solid(.red), blue = solid(.blue), size = PixelSize(width: 32, height: 24)!
        let store = ProjectStore(root: root)
        func model(_ objects: [EditorObject] = []) -> EditorModel {
            EditorModel(image: red, document: ProjectDocument(title: "Synthetic cancellation", pixelSize: size, objects: objects),
                        generation: 0, store: store, onSaved: {})
        }
        // Cancelling the owning canvas must reach asset validation and suppress its late error.
        let asset = try EditorImageAsset(png: EditorRenderer.png(image: blue, objects: []), size: size)
        var picture = EditorObject(kind: .image, start: .zero, end: CGPoint(x: 32, y: 24)); picture.imageAsset = asset
        let assetModel = model([picture]), assetGate = RenderCancellationGate()
        let assetCanvas = CanvasView(model: assetModel, renderClient: CanvasRenderClient(
            validateAssets: { _ in assetGate.hold(); throw CocoaError(.fileReadCorruptFile) },
            magnifier: { image, _ in .init(image: image, originalSize: CGSize(width: image.width, height: image.height)) }))
        assetCanvas.refreshComposition()
        try await wait { assetGate.hasStarted }
        assetCanvas.needsDisplay = false
        assetCanvas.cancelRendering()
        try await wait { assetGate.sawCancellation }
        assetGate.release()
        try await Task.sleep(for: .milliseconds(40))
        precondition(assetModel.error == nil && !assetCanvas.needsDisplay, "Cancelled validation published an error or requested stale UI work")

        // An old canvas job cannot publish over a new rendering generation.
        let magnifierModel = model(), oldGate = RenderCancellationGate()
        magnifierModel.tool = .magnifier
        let counter = LockedRenderCounter()
        let magnifierCanvas = CanvasView(model: magnifierModel, renderClient: CanvasRenderClient(validateAssets: { _ in }, magnifier: { _, _ in
            let invocation = counter.next()
            if invocation == 1 { oldGate.hold() }
            return .init(image: invocation == 1 ? red : blue, originalSize: CGSize(width: 32, height: 24))
        }))
        magnifierCanvas.refreshComposition()
        try await wait { oldGate.hasStarted }
        magnifierCanvas.cancelRendering()
        try await wait { oldGate.sawCancellation }
        magnifierCanvas.refreshComposition()
        try await wait { magnifierCanvas.magnifierImage === blue }
        oldGate.release()
        try await Task.sleep(for: .milliseconds(40))
        precondition(magnifierCanvas.magnifierImage === blue && magnifierModel.error == nil && counter.value == 2,
                     "Cancelled magnifier published stale pixels or restarted its coalescing loop")
        magnifierCanvas.cancelRendering()

        // When edits change during composition, discard the obsolete result before starting the next round.
        let coalescedModel = model(), firstGate = RenderCancellationGate(), secondGate = RenderCancellationGate()
        coalescedModel.tool = .magnifier
        let coalescedCount = LockedRenderCounter()
        let coalescedCanvas = CanvasView(model: coalescedModel, renderClient: CanvasRenderClient(validateAssets: { _ in }, magnifier: { _, _ in
            let invocation = coalescedCount.next()
            if invocation == 1 { firstGate.hold() } else { secondGate.hold() }
            return .init(image: invocation == 1 ? red : blue, originalSize: CGSize(width: 32, height: 24))
        }))
        coalescedCanvas.refreshComposition(); try await wait { firstGate.hasStarted }
        coalescedModel.preview = [EditorObject(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10))]
        coalescedCanvas.refreshComposition(); firstGate.release()
        try await wait { secondGate.hasStarted }
        precondition(coalescedCanvas.magnifierImage == nil, "Obsolete composition became visible while replacement was pending")
        secondGate.release(); try await wait { coalescedCanvas.magnifierImage === blue }
        precondition(coalescedCount.value == 2)
        coalescedCanvas.cancelRendering()

        // The actual quick-preview pipeline forwards cancellation into its thumbnail worker
        // and removes the previously prepared temporary PNG instead of leaking it.
        let decodeGate = RenderCancellationGate()
        let snapshot = EditorPNGShare(image: blue, objects: [], crop: nil, resizedSize: nil, title: "Synthetic cancelled preview")
        let quickRoot = root.appendingPathComponent("QuickCancelled")
        let quick = Task { try await QuickCapturePayload.prepare(snapshot, in: quickRoot, decode: { url in
            decodeGate.hold(file: url); return blue
        }) }
        try await wait { decodeGate.hasStarted }
        quick.cancel(); try await wait { decodeGate.sawCancellation }
        decodeGate.release()
        do { _ = try await quick.value; preconditionFailure("Cancelled thumbnail pipeline returned a payload") }
        catch is CancellationError { }
        guard let cancelledFile = decodeGate.preparedFile else { preconditionFailure("Thumbnail preparation never received a file") }
        precondition(!FileManager.default.fileExists(atPath: cancelledFile.path), "Cancelled preview leaked its prepared PNG")
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: quickRoot.path)
        precondition(remainingFiles.isEmpty)
        print("Render cancellation passed: detached asset/magnifier/thumbnail workers observe cancellation, stale errors/pixels suppressed, coalescing discards old results, cancelled temporary PNG cleaned")
    }
}

private final class LockedRenderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

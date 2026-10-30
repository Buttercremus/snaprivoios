import AppKit
import SnagForgeDomain

private final class RasterReservationGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var released = false
    var hasStarted: Bool { condition.lock(); defer { condition.unlock() }; return entered }
    func hold() {
        condition.lock(); defer { condition.unlock() }
        entered = true
        while !released && !Task.isCancelled { _ = condition.wait(until: Date(timeIntervalSinceNow: 0.005)) }
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}

@MainActor enum RenderingBudgetChecks {
    static func run() async throws {
        let width = 640, height = 320
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        let image = context.makeImage()!
        let sourceBytes = image.bytesPerRow * image.height
        let plain = EditorRenderer.rasterMemoryEstimate(image: image)
        let encoded = EditorRenderer.rasterMemoryEstimate(image: image, encoding: true)
        precondition(plain >= sourceBytes + width * height * 4 && encoded > plain,
                     "The source, output or encoder buffers were omitted from the reservation")
        let smallCrop = CGRect(x: 4, y: 4, width: 20, height: 20)
        precondition(EditorRenderer.rasterMemoryEstimate(image: image, crop: smallCrop) >= sourceBytes * 2,
                     "A tiny crop forgot its full-source composition raster")
        var presentation = EditorPresentation(); presentation.padding = 200; presentation.rotationDegrees = 35
        let geometry = presentation.geometry(for: PixelSize(width: width, height: height)!)!
        let framed = EditorRenderer.rasterMemoryEstimate(image: image, presentation: presentation)
        precondition(framed >= sourceBytes + geometry.outputSize.width * geometry.outputSize.height * 8,
                     "Presentation padding/rotation/aspect geometry was underestimated")
        for crop in [CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10),
                     CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10),
                     CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 10)] {
            do { _ = try EditorRenderer.render(image: image, objects: [], crop: crop); preconditionFailure("Invalid raster geometry was rendered") }
            catch { precondition(EditorRenderer.rasterBudgetSnapshot.reserved == 0) }
        }

        // Hold a real process-wide lease while another actual PNG render attempts admission.
        let limit = EditorRenderer.rasterBudgetSnapshot.limit, gate = RasterReservationGate()
        let held = Task.detached {
            try EditorRenderer.withRasterReservation(limit - 1) { gate.hold() }
        }
        for _ in 0..<1000 { if gate.hasStarted { break }; try await Task.sleep(for: .milliseconds(5)) }
        precondition(gate.hasStarted && EditorRenderer.rasterBudgetSnapshot.reserved == limit - 1)
        do { _ = try EditorRenderer.png(image: image, objects: []); preconditionFailure("Concurrent jobs exceeded the shared raster budget") }
        catch EditorRenderer.ExportError.memoryBudget { }
        gate.release(); try await held.value
        precondition(EditorRenderer.rasterBudgetSnapshot.reserved == 0)
        let cancelledGate = RasterReservationGate()
        let cancelled = Task.detached {
            try EditorRenderer.withRasterReservation(128) { cancelledGate.hold(); try Task.checkCancellation() }
        }
        for _ in 0..<1000 { if cancelledGate.hasStarted { break }; try await Task.sleep(for: .milliseconds(5)) }
        precondition(cancelledGate.hasStarted); cancelled.cancel()
        do { try await cancelled.value; preconditionFailure("Cancelled raster reservation completed") } catch is CancellationError { }
        precondition(EditorRenderer.rasterBudgetSnapshot.reserved == 0)
        do { try EditorRenderer.withRasterReservation(128) { throw CocoaError(.fileWriteUnknown) } }
        catch { precondition(EditorRenderer.rasterBudgetSnapshot.reserved == 0) }
        let exported = try EditorRenderer.png(image: image, objects: [])
        let bitmap = NSBitmapImageRep(data: exported)!
        precondition(bitmap.pixelsWide == width && bitmap.pixelsHigh == height, "Memory admission silently reduced export resolution")

        let preview = try EditorRenderer.renderMagnifierPreview(image: image, objects: [], maxDimension: 128)
        precondition(preview.image.width == 128 && preview.image.height == 64 && preview.originalSize == CGSize(width: width, height: height))
        var magnifier = EditorObject(kind: .magnifier, start: CGPoint(x: 500, y: 200), end: CGPoint(x: 580, y: 280))
        magnifier.magnifierSource = CGPoint(x: 120, y: 80)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        EditorRenderer.drawBase(image: image, in: context)
        EditorRenderer.drawAnnotations(objects: [magnifier], in: context, magnifierSource: preview.image, magnifierSourceSize: preview.originalSize)
        let canvas = context.makeImage()!, full = try EditorRenderer.render(image: image, objects: [magnifier])
        for candidate in [canvas, full] {
            let sampled = EditorRenderer.pixelColor(candidate, x: 540, y: 240)!
            precondition(sampled.redComponent > 0.95 && sampled.blueComponent < 0.05,
                         "Bounded magnifier sampled preview coordinates instead of original source coordinates")
        }
        precondition(EditorRenderer.rasterBudgetSnapshot.reserved == 0)

        var text = EditorObject(kind: .text, start: CGPoint(x: 20, y: 30), end: .zero,
                                text: String(repeating: "Synthetischer Langtext ", count: 6500), fontSize: 20, textWidth: 1400)
        EditorRenderer.resetTextGeometryCacheStatistics()
        let before = CFAbsoluteTimeGetCurrent(), cold = EditorRenderer.textRect(text)
        let coldMilliseconds = (CFAbsoluteTimeGetCurrent() - before) * 1000
        let warmStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10 { precondition(EditorRenderer.textRect(text) == cold) }
        let warmMilliseconds = (CFAbsoluteTimeGetCurrent() - warmStart) * 100
        let beforeMove = EditorRenderer.textGeometryCacheStatistics
        var equivalent = EditorObject(kind: .text, start: CGPoint(x: 120, y: 30), end: .zero,
                                      text: text.text, fontSize: text.fontSize, textWidth: text.textWidth)
        equivalent.color = EditorColor(red: 0, green: 1, blue: 0)
        precondition(EditorRenderer.textRect(equivalent).size == cold.size)
        let afterMove = EditorRenderer.textGeometryCacheStatistics
        precondition(afterMove.hits == beforeMove.hits + 1 && afterMove.misses == beforeMove.misses,
                     "Position, colour or object identity invalidated invariant text geometry")
        text.fontSize += 4; _ = EditorRenderer.textRect(text)
        precondition(EditorRenderer.textGeometryCacheStatistics.misses > afterMove.misses)
        print(String(format: "Text geometry benchmark: %d characters, cold %.3f ms, warm mean %.3f ms (10 measurements); cache hit/miss invalidation verified", text.text.count, coldMilliseconds, warmMilliseconds))
        print("Raster budget passed: source/crop/presentation/encoder estimates, invalid geometry, concurrent PNG admission, cancellation/failure release, full export dimensions and bounded magnifier source coordinates")
    }
}

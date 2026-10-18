import AppKit
import SnagForgeDomain

@main struct HandDrawnChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-HandDrawn-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 1000, height: 520, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 520))
        let image = context.makeImage()!
        var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 900, y: 180), end: CGPoint(x: 580, y: 300), lineWidth: 6)
        var ellipse = EditorObject(kind: .ellipse, start: CGPoint(x: 550, y: 340), end: CGPoint(x: 920, y: 470), lineWidth: 5)
        let doc = ProjectDocument(title: "Synthetic hand-drawn checks", pixelSize: PixelSize(width: 1000, height: 520)!, objects: [arrow, ellipse])
        let original = try EditorRenderer.png(image: image, objects: [])
        let store = ProjectStore(root: root)
        try await store.create(doc, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        model.selection = arrow.id; model.updateStyle(drawingStyle: .handDrawn)
        precondition(model.history.objects[0].effectiveDrawingStyle == .handDrawn)
        model.undo(); precondition(model.history.objects == doc.objects)
        model.redo(); precondition(model.history.objects[0].effectiveDrawingStyle == .handDrawn)
        model.selection = ellipse.id; model.updateStyle(drawingStyle: .handDrawn)
        let objects = model.history.objects
        let flushed = await model.flush(); precondition(flushed)
        let loaded = try await ProjectStore(root: root).load(doc.id)
        precondition(loaded.document.objects == objects)
        let crop = CGRect(x: 500, y: 120, width: 480, height: 380)
        let size = PixelSize(width: 720, height: 570)!
        let png = try EditorRenderer.png(image: image, objects: objects, crop: crop, resizedSize: size)
        let restored = try EditorRenderer.png(image: image, objects: loaded.document.objects, crop: crop, resizedSize: size)
        precondition(png == restored)
        let precisePNG = try EditorRenderer.png(image: image, objects: doc.objects, crop: crop, resizedSize: size)
        precondition(png != precisePNG)
        // Check a point on the curved shaft in image coordinates, away from the chord.
        var horizontal = EditorObject(kind: .arrow, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 450, y: 50), lineWidth: 6)
        horizontal.drawingStyle = .handDrawn
        let raster = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [horizontal]))!
        let onCurve = raster.colorAt(x: 264, y: 131)!.usingColorSpace(.deviceRGB)!
        let onChord = raster.colorAt(x: 250, y: 50)!.usingColorSpace(.deviceRGB)!
        precondition(onCurve.greenComponent < 0.5 && onChord.greenComponent > 0.95)
        model.selection = nil; model.tool = .arrow
        model.applySavedStyle(EditorSavedStyle(object: objects[0]))
        precondition(model.makeObject(kind: .arrow, start: .zero).effectiveDrawingStyle == .handDrawn)
        let inherited = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        inherited.inheritToolSettings(from: model)
        precondition(inherited.makeObject(kind: .arrow, start: .zero).effectiveDrawingStyle == .handDrawn)
        // Export a synthetic visual comparison through the production renderer.
        func label(_ text: String, x: CGFloat) -> EditorObject {
            var text = EditorObject(kind: .text, start: CGPoint(x: x, y: 45), text: text, fontSize: 32)
            text.color = EditorColor(red: 0.15, green: 0.17, blue: 0.20); return text
        }
        let preciseArrow = arrow.translated(by: CGSize(width: -480, height: 0))
        let preciseEllipse = ellipse.translated(by: CGSize(width: -480, height: 0))
        arrow.drawingStyle = .handDrawn; ellipse.drawingStyle = .handDrawn
        let preview = try EditorRenderer.png(image: image, objects: [label("Präzise", x: 70), label("Handgezeichnet", x: 550), preciseArrow, preciseEllipse, arrow, ellipse])
        try preview.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Hand-drawn checks passed: native style undo/redo, autosave/reopen, identical cropped/resized export, curved shaft pixels, saved style defaults and editor inheritance.")
    }
}

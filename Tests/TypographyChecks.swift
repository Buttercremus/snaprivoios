import AppKit
import SnagForgeDomain

@main struct TypographyChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Typography-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let image = context.makeImage()!, original = try EditorRenderer.png(image: image, objects: [])
        var object = EditorObject(kind: .callout, start: CGPoint(x: 180, y: 130), text: "First line\nShort", fontSize: 24, textWidth: 240)
        object.color = EditorColor(red: 0, green: 0, blue: 0)
        let legacyFont = EditorRenderer.font(object)
        precondition(legacyFont == NSFont.systemFont(ofSize: 24, weight: .semibold))
        let legacyTip = EditorRenderer.calloutTip(object), legacyBox = EditorRenderer.calloutBox(object)
        precondition(legacyTip.y == legacyBox.maxY + 25)
        let store = ProjectStore(root: root)
        let doc = ProjectDocument(title: "Typography (synthetic)", pixelSize: PixelSize(width: 600, height: 400)!, objects: [object],
                                  crop: CGRect(x: 20, y: 10, width: 560, height: 380), resizedSize: PixelSize(width: 280, height: 190))
        try await store.create(doc, original: original, thumbnail: nil)
        let model = EditorModel(image: image, document: doc, generation: 0, store: store, onSaved: {})
        model.selection = object.id
        let style = EditorTextStyle(family: "Helvetica", weight: .bold, italic: true, alignment: .right)
        model.updateStyle(textStyle: style)
        precondition(model.selectedObject!.textStyle == style)
        let styled = model.history.objects
        model.undo(); precondition(model.history.objects == [object])
        model.redo(); precondition(model.history.objects == styled)
        object = styled[0]
        let font = EditorRenderer.font(object)
        precondition(font.fontDescriptor.symbolicTraits.contains([.bold, .italic]), "Font traits missing")
        var unavailable = object; unavailable.textStyle?.family = "Snaprivo-Missing-Font-12345"
        precondition(EditorRenderer.font(unavailable).pointSize == 24)
        // Paragraph layout must move glyphs, not merely change a persisted enum.
        func glyphOrigin(_ alignment: EditorTextStyle.Alignment) -> CGFloat {
            var value = object; value.textStyle?.alignment = alignment
            let storage = NSTextStorage(string: value.text, attributes: EditorRenderer.textAttributes(value))
            let layout = NSLayoutManager(), container = NSTextContainer(size: CGSize(width: 240, height: 1000))
            container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            return layout.location(forGlyphAt: 0).x
        }
        precondition(glyphOrigin(.left) < glyphOrigin(.center) && glyphOrigin(.center) < glyphOrigin(.right))
        // Underline must reach the exported pixels as one line under the words, spaces included.
        func longestDarkRun(underlined: Bool) throws -> (run: Int, extent: Int) {
            var value = EditorObject(kind: .text, start: CGPoint(x: 40, y: 60), text: "il il il", fontSize: 40)
            value.color = EditorColor(red: 0, green: 0, blue: 0); value.textStyle = EditorTextStyle(underline: underlined)
            let bitmap = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [value]))!
            var longest = 0, minX = Int.max, maxX = 0
            for y in 0..<bitmap.pixelsHigh {
                var run = 0
                for x in 0..<bitmap.pixelsWide {
                    guard bitmap.colorAt(x: x, y: y)!.brightnessComponent < 0.5 else { run = 0; continue }
                    run += 1; longest = max(longest, run); minX = min(minX, x); maxX = max(maxX, x)
                }
            }
            return (longest, maxX - minX + 1)
        }
        let plainRun = try longestDarkRun(underlined: false), underlinedRun = try longestDarkRun(underlined: true)
        precondition(plainRun.run < plainRun.extent / 3, "Synthetic glyphs already form a long line")
        precondition(underlinedRun.run >= plainRun.extent * 8 / 10, "Underline missing from rendered text")
        var auto = object; auto.textWidth = nil
        precondition(EditorRenderer.textRect(auto).width < 500 && EditorRenderer.textContainerWidth(auto) < 500)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let canvas = CanvasView(model: model); window.contentView = canvas; canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.synchronizeViewport(); window.makeFirstResponder(canvas)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let projection = EditorImageProjection(source: model.sourceRect, destination: model.viewport.imageRect(image: model.imageSize, in: canvas.bounds, backingScale: window.backingScaleFactor))
            return NSEvent.mouseEvent(with: type, location: canvas.convert(projection.viewPoint(point), to: nil), modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let target = CGPoint(x: 90, y: 80)
        model.selection = object.id
        let tip = EditorRenderer.calloutTip(object)
        canvas.mouseDown(with: event(.leftMouseDown, tip))
        canvas.mouseDragged(with: event(.leftMouseDragged, target))
        precondition(model.preview?[0].calloutTip == target && model.history.objects[0].calloutTip == nil, "Tail must preview live")
        canvas.mouseUp(with: event(.leftMouseUp, target))
        precondition(model.history.objects[0].calloutTip == target && model.history.objects[0].start == object.start)
        let moved = model.history.objects
        model.undo(); precondition(model.history.objects == styled)
        model.redo(); precondition(model.history.objects == moved)
        // Resize frame without moving the target.
        model.selection = object.id
        let box = EditorRenderer.calloutBox(model.history.objects[0]), corner = CGPoint(x: box.maxX, y: box.maxY)
        canvas.mouseDown(with: event(.leftMouseDown, corner)); canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: corner.x + 30, y: corner.y + 20)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: corner.x + 30, y: corner.y + 20)))
        precondition(model.history.objects[0].calloutTip == target)
        model.undo(); precondition(model.history.objects == moved)
        // All four tail directions are part of one closed, filled outline; no bounding-box phantom hit.
        for destination in [CGPoint(x: 300, y: 40), CGPoint(x: 500, y: 170), CGPoint(x: 300, y: 320), CGPoint(x: 80, y: 170)] {
            var value = object; value.calloutTip = destination
            let path = EditorRenderer.calloutPath(value)
            precondition(path.boundingBoxOfPath.minX <= destination.x && path.boundingBoxOfPath.maxX >= destination.x)
            precondition(path.boundingBoxOfPath.minY <= destination.y && path.boundingBoxOfPath.maxY >= destination.y)
            let box = EditorRenderer.calloutBox(value)
            precondition(path.contains(CGPoint(x: (destination.x * 0.9 + box.midX * 0.1), y: (destination.y * 0.9 + box.midY * 0.1))))
            _ = try EditorRenderer.png(image: image, objects: [value])
        }
        model.selection = object.id; model.duplicateSelection()
        precondition(model.selectedObject!.calloutTip != target && model.selectedObject!.textStyle == style)
        model.undo(); precondition(model.history.objects == moved)
        model.editText(at: object.start, object: model.history.objects[0]); canvas.synchronizeTextEditor()
        func textView(_ view: NSView) -> NSTextView? { (view as? NSTextView) ?? view.subviews.lazy.compactMap { textView($0) }.first }
        let editor = textView(canvas)!
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        var centre = style; centre.alignment = .center
        model.updateStyle(textStyle: centre); canvas.synchronizeTextEditor()
        precondition(editor.selectedRange() == NSRange(location: 0, length: 5) && editor.alignment == .center && editor.font == EditorRenderer.font(model.editingTextObject!))
        // The inline editor shows the underline at once, for existing and newly typed text, and drops it again.
        var underlined = centre; underlined.isUnderlined = true
        model.updateStyle(textStyle: underlined); canvas.synchronizeTextEditor()
        func underlineValue() -> Int? { editor.textStorage!.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int }
        precondition(underlineValue() == NSUnderlineStyle.single.rawValue && editor.typingAttributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        model.updateStyle(textStyle: centre); canvas.synchronizeTextEditor()
        precondition(underlineValue() == nil && editor.typingAttributes[.underlineStyle] == nil && model.editingTextObject!.textStyle == centre)
        model.finishTextEditing(); model.undo(); precondition(model.history.objects == moved)
        for _ in 0..<500 where model.isDirty || model.isSaving { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!model.isDirty && model.saveError == nil)
        let loaded = try await ProjectStore(root: root).load(doc.id)
        precondition(loaded.document.objects == moved && loaded.original == original && loaded.document.resizedSize == doc.resizedSize)
        let png = try EditorRenderer.png(image: image, objects: moved, crop: doc.crop, resizedSize: doc.resizedSize)
        let restored = EditorModel(image: image, document: loaded.document, generation: loaded.generation, store: store, onSaved: {})
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("Snaprivo-Typography-\(UUID())")); defer { pasteboard.releaseGlobally() }
        restored.copyPNG(to: pasteboard)
        for _ in 0..<500 where restored.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        precondition(pasteboard.data(forType: .png) == png)
        print("Typography checks passed: legacy font, font traits/fallback, paragraph layout, underline pixels and inline editor, live independent tail, frame resize, four directions, duplicate, inline selection, undo/redo, autosave/reopen and resized/cropped PNG/clipboard.")
    }
}

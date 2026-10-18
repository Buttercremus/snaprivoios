import AppKit
import SnagForgeDomain

enum CropRendererChecks {
    static func run(image: CGImage) throws {
        var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 20, y: 40), end: CGPoint(x: 170, y: 115), lineWidth: 7)
        arrow.color = EditorColor(red: 0, green: 1, blue: 0)
        var text = EditorObject(kind: .text, start: CGPoint(x: 80, y: 40), text: "Crop Text", fontSize: 20)
        text.color = EditorColor(red: 1, green: 1, blue: 0)
        var shape = EditorObject(kind: .ellipse, start: CGPoint(x: 150, y: 80), end: CGPoint(x: 220, y: 130), lineWidth: 5)
        shape.fill = EditorFill(isEnabled: true, color: EditorColor(red: 0, green: 1, blue: 1), opacity: 0.5)
        let blur = EditorObject(kind: .blur, start: CGPoint(x: 20, y: 60), end: CGPoint(x: 100, y: 100))
        let objects = [blur, arrow, text, shape]
        let crop = CGRect(x: 50, y: 35, width: 140, height: 90)
        let full = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: objects))!
        let cropped = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: objects, crop: crop))!
        precondition(cropped.pixelsWide == 140 && cropped.pixelsHigh == 90, "PNG crop dimensions wrong")
        for y in 0..<90 {
            for x in 0..<140 {
                var a = [Int](repeating: 0, count: 4), b = a
                full.getPixel(&a, atX: x + 50, y: y + 35); cropped.getPixel(&b, atX: x, y: y)
                precondition(a == b, "Cropped pixels differ from original composition at \(x),\(y)")
            }
        }
        let thumb = NSBitmapImageRep(data: try EditorRenderer.thumbnail(image: image, objects: objects, crop: crop))!
        precondition(thumb.pixelsWide == 140 && thumb.pixelsHigh == 90)
        let onePixel = try EditorRenderer.render(image: image, objects: [], crop: CGRect(x: 239, y: 159, width: 1, height: 1))
        precondition(onePixel.width == 1 && onePixel.height == 1)
        do {
            _ = try EditorRenderer.png(image: image, objects: [], crop: CGRect(x: -1, y: 0, width: 10, height: 10))
            preconditionFailure("Invalid crop exported silently")
        } catch EditorRenderer.ExportError.render { }
        print("Crop renderer checks passed: exact pixel equality with full composition including blur/text/arrow/fill, top-left orientation, PNG/thumbnail dimensions, one pixel and rejected invalid crop.")
    }
}

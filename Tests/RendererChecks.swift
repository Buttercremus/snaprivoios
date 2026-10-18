import AppKit
import SnagForgeDomain

@main
struct RendererChecks {
    private static func pixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        // colorAt labels its components as calibrated RGB even for an sRGB bitmap.
        // Check the actual 8-bit PNG samples to avoid an extra ColorSync conversion.
        precondition(bitmap.bitsPerSample == 8 && bitmap.samplesPerPixel == 4)
        var rgba = [Int](repeating: 0, count: 4)
        bitmap.getPixel(&rgba, atX: x, y: y)
        return (Double(rgba[0]) / 255, Double(rgba[1]) / 255, Double(rgba[2]) / 255, Double(rgba[3]) / 255)
    }
    @MainActor static func main() throws {
        let width = 240, height = 160
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = y < height / 2 ? 255 : 0
                bytes[i + 2] = y < height / 2 ? 0 : 255
                bytes[i + 3] = x < 10 ? 0 : 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let plain = try EditorRenderer.png(image: image, objects: [])
        let plainRep = NSBitmapImageRep(data: plain)!
        precondition(plainRep.pixelsWide == width && plainRep.pixelsHigh == height, "Export dimensions changed")
        let top = plainRep.colorAt(x: 20, y: 10)!.usingColorSpace(.deviceRGB)!
        let bottom = plainRep.colorAt(x: 20, y: 150)!.usingColorSpace(.deviceRGB)!
        precondition(top.redComponent > 0.9 && bottom.blueComponent > 0.9, "Image flipped during export")
        precondition(plainRep.colorAt(x: 2, y: 10)!.alphaComponent < 0.01, "Alpha was lost")
        let thumbnail = try EditorRenderer.render(image: image, objects: [], maxDimension: 120)
        precondition(thumbnail.width == 120 && thumbnail.height == 80, "Thumbnail dimensions changed")
        let thumbnailRep = NSBitmapImageRep(cgImage: thumbnail)
        precondition(thumbnailRep.colorAt(x: 20, y: 10)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9 &&
                     thumbnailRep.colorAt(x: 20, y: 70)!.usingColorSpace(.deviceRGB)!.blueComponent > 0.9,
                     "Thumbnail changed image orientation")
        let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 30, y: 100), end: CGPoint(x: 200, y: 100))
        let text = EditorObject(kind: .text, start: CGPoint(x: 40, y: 115), text: "SnagForge", fontSize: 22)
        let annotated = try EditorRenderer.png(image: image, objects: [arrow, text])
        let annotatedRep = NSBitmapImageRep(data: annotated)!
        let arrowPixel = annotatedRep.colorAt(x: 100, y: 100)!.usingColorSpace(.deviceRGB)!
        precondition(arrowPixel.redComponent > 0.5, "Arrow absent from export")
        var textPixels = 0
        for y in 115..<150 {
            for x in 40..<210 {
                if annotatedRep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent > 0.3 { textPixels += 1 }
            }
        }
        precondition(textPixels > 30, "Text absent or vertically misplaced in export")
        var largeText = text
        largeText.fontSize = 44
        precondition(EditorRenderer.textRect(largeText).width > EditorRenderer.textRect(text).width * 1.8, "Font size ignored")
        let wrapped = EditorObject(kind: .text, start: CGPoint(x: 40, y: 90), text: "Eins zwei drei vier", fontSize: 14, textWidth: 78)
        let wrappedRect = EditorRenderer.textRect(wrapped)
        precondition(wrappedRect.width == 78 && wrappedRect.height > 30, "Text width did not cause wrapping")
        let wrappedPNG = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [wrapped]))!
        var secondLinePixels = 0, overflowPixels = 0
        for y in 110..<150 {
            for x in 40..<150 {
                if wrappedPNG.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent > 0.3 {
                    if x < 119 { secondLinePixels += 1 } else { overflowPixels += 1 }
                }
            }
        }
        precondition(secondLinePixels > 20 && overflowPixels == 0, "PNG lost wrapping or drew beyond the text box")
        var thickArrow = arrow
        thickArrow.lineWidth = 18; thickArrow.color = EditorColor(red: 0, green: 1, blue: 0)
        let thick = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [thickArrow]))!
        precondition(thick.colorAt(x: 70, y: 106)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.8, "Arrow style ignored")
        var rectangle = EditorObject(kind: .rectangle, start: CGPoint(x: 30, y: 20), end: CGPoint(x: 90, y: 60), lineWidth: 4)
        rectangle.color = EditorColor(red: 0, green: 1, blue: 0)
        var ellipse = EditorObject(kind: .ellipse, start: CGPoint(x: 110, y: 20), end: CGPoint(x: 170, y: 60), lineWidth: 4)
        ellipse.color = rectangle.color
        var callout = EditorObject(kind: .callout, start: CGPoint(x: 40, y: 100), text: "Hi", fontSize: 12)
        callout.color = rectangle.color
        let shapes = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [rectangle, ellipse, callout]))!
        precondition(shapes.colorAt(x: 30, y: 40)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.8, "Rectangle/color absent")
        precondition(shapes.colorAt(x: 140, y: 20)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.8, "Ellipse absent")
        precondition(shapes.colorAt(x: 35, y: 100)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.8, "Callout background absent")
        precondition(shapes.colorAt(x: 60, y: 40)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9, "Legacy rectangle unexpectedly filled")
        rectangle.fill = EditorFill(isEnabled: true, color: rectangle.color, opacity: 0.5)
        rectangle.cornerRadius = 16
        ellipse.fill = EditorFill(isEnabled: true, color: rectangle.color, opacity: 1)
        let fills = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [rectangle, ellipse]))!
        let blended = pixel(fills, x: 60, y: 40)
        try fills.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "-fill.png"))
        precondition(abs(blended.red - 0.5) < 0.03 && abs(blended.green - 0.5) < 0.03,
                     "Fill opacity did not blend with source pixels")
        precondition(pixel(fills, x: 30, y: 40).green > 0.9, "Fill opacity changed outline opacity")
        precondition(pixel(fills, x: 30, y: 20).red > 0.9, "Rounded corner rendered as a sharp corner")
        precondition(pixel(fills, x: 140, y: 40).green > 0.9, "Ellipse fill absent")
        rectangle.fill?.isEnabled = false
        let unfilled = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [rectangle]))!
        precondition(pixel(unfilled, x: 60, y: 40).green < 0.01, "Disabled fill remains visible")
        // Callout fill covers its tail exactly once; no seam across the join.
        let box = EditorRenderer.textRect(callout).insetBy(dx: -12, dy: -10)
        callout.fill = EditorFill(isEnabled: true, color: rectangle.color, opacity: 0.5)
        let bubble = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [callout]))!
        let tail = pixel(bubble, x: Int(box.minX + 22), y: Int(box.maxY + 5))
        let join = pixel(bubble, x: Int(box.minX + 24), y: Int(box.maxY))
        precondition(abs(tail.green - 0.5) < 0.03 && abs(join.green - 0.5) < 0.03, "Callout tail opacity or seam incorrect")
        callout.fill?.isEnabled = false
        let clearBubble = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [callout]))!
        precondition(pixel(clearBubble, x: Int(box.minX + 22), y: Int(box.maxY + 5)).blue > 0.9,
                     "Callout cannot have a transparent background")
        var resizedBubble = callout
        resizedBubble.start = CGPoint(x: 40, y: 20); resizedBubble.textWidth = 120; resizedBubble.textHeight = 70
        resizedBubble.fill = EditorFill(isEnabled: true, color: rectangle.color)
        let resizedBubblePNG = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [resizedBubble]))!
        precondition(EditorRenderer.calloutBox(resizedBubble) == CGRect(x: 28, y: 10, width: 144, height: 90), "Callout frame ignored explicit height")
        precondition(pixel(resizedBubblePNG, x: 140, y: 80).green > 0.9, "Export retained the old callout frame")
        let bubbleThumbnail = NSBitmapImageRep(cgImage: try EditorRenderer.render(image: image, objects: [resizedBubble], maxDimension: 120))
        precondition(pixel(bubbleThumbnail, x: 70, y: 40).green > 0.9, "Thumbnail lost resized callout height")
        resizedBubble.textWidth = 35; resizedBubble.textHeight = 1; resizedBubble.text = "Hinweis mit mehr Text"
        precondition(EditorRenderer.textRect(resizedBubble).height > 40, "Small callout frame clipped wrapped text")
        let smallFilled = NSBitmapImageRep(cgImage: try EditorRenderer.render(image: image, objects: [ellipse], maxDimension: 120))
        precondition(pixel(smallFilled, x: 70, y: 20).green > 0.9, "Thumbnail lost fill")
        var outline = EditorObject(kind: .rectangle, start: CGPoint(x: 25, y: 95), end: CGPoint(x: 110, y: 145), lineWidth: 4)
        outline.color = EditorColor(red: 0, green: 1, blue: 0)
        func strokePixels(_ style: EditorStroke.Style) throws -> [Bool] {
            outline.stroke = EditorStroke(style: style)
            let png = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [outline]))!
            return (30..<105).map { pixel(png, x: $0, y: 95).green > 0.8 }
        }
        let solid = try strokePixels(.solid), dashed = try strokePixels(.dashed), dotted = try strokePixels(.dotted)
        precondition(solid.allSatisfy { $0 }, "Solid outline has gaps")
        precondition(dashed.filter { $0 }.count > 10 && dashed.filter { !$0 }.count > 10, "Dashed outline has no dashes or gaps")
        precondition(dotted.filter { $0 }.count > 10 && dotted.filter { !$0 }.count > 10 && dashed != dotted, "Dotted outline is not distinct")
        outline.stroke = EditorStroke(isEnabled: false)
        outline.fill = EditorFill(isEnabled: true, color: outline.color, opacity: 0.5)
        let noBorder = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [outline]))!
        precondition(pixel(noBorder, x: 24, y: 120).blue > 0.9 && abs(pixel(noBorder, x: 60, y: 120).green - 0.5) < 0.03,
                     "Disabling the border changed fill or left outline pixels")
        outline.fill?.isEnabled = false
        let invisible = try EditorRenderer.png(image: image, objects: [outline])
        precondition(invisible == plain, "Disabled border and fill still draw pixels")
        for kind in [EditorObject.Kind.triangle, .diamond, .star] {
            var shape = outline; shape.kind = kind
            shape.fill = EditorFill(isEnabled: true, color: outline.color)
            let forward = try EditorRenderer.png(image: image, objects: [shape])
            let polygon = NSBitmapImageRep(data: forward)!
            precondition(pixel(polygon, x: 67, y: 120).green > 0.9 && pixel(polygon, x: 26, y: 96).blue > 0.9,
                         "Polygon fill missing or geometry rendered as a rectangle")
            swap(&shape.start, &shape.end)
            let reversed = try EditorRenderer.png(image: image, objects: [shape])
            precondition(reversed == forward, "Reverse drag changes polygon orientation")
            let thumb = NSBitmapImageRep(cgImage: try EditorRenderer.render(image: image, objects: [shape], maxDimension: 120))
            precondition(pixel(thumb, x: 34, y: 60).green > 0.9, "Polygon missing in thumbnail")
        }
        var blur = EditorObject(kind: .blur, start: CGPoint(x: 100, y: 60), end: CGPoint(x: 170, y: 100))
        blur.blurRadius = 12
        let blurred = NSBitmapImageRep(data: try EditorRenderer.png(image: image, objects: [blur]))!
        let edge = blurred.colorAt(x: 130, y: 79)!.usingColorSpace(.deviceRGB)!
        try blurred.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "-blur.png"))
        precondition(edge.blueComponent > 0.1 && edge.redComponent > 0.1, "Blur did not mix the boundary")
        let outside = blurred.colorAt(x: 60, y: 79)!.usingColorSpace(.deviceRGB)!
        precondition(outside.redComponent > 0.9 && outside.blueComponent < 0.1, "Blur escaped its selected region")
        print("Renderer checks passed: resized callout frame, text overflow and thumbnails; triangle/diamond/star including reverse drag, solid/dashed/dotted/disabled borders, independent fill; existing blur, size, orientation, alpha, arrows and text.")
        try CropRendererChecks.run(image: image)
        // Synthetic fixture for interactive editor checks; no user image is saved.
        try plain.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}

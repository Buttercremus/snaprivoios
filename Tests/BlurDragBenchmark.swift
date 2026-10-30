import AppKit
import CoreImage
import SnagForgeDomain

@main struct BlurDragBenchmark {
    // Frozen pre-optimization path, retained only to reproduce the baseline on identical input.
    static func legacyFrame(image: CGImage, object: EditorObject) throws -> CGImage {
        let output = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        output.translateBy(x: 0, y: CGFloat(image.height)); output.scaleBy(x: 1, y: -1)
        EditorRenderer.drawBase(image: image, in: output)
        let source = CIImage(cgImage: image).clampedToExtent(), filtered: CIImage
        switch object.effectiveBlurStyle {
        case .gaussian: filtered = source.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: object.blurRadius])
        case .pixelate: filtered = source.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(2, object.blurRadius), kCIInputCenterKey: CIVector(x: 0, y: 0)])
        case .mosaic: filtered = source.applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: max(2, object.blurRadius), kCIInputCenterKey: CIVector(x: 0, y: 0)])
        }
        let area = object.rect
        let ciArea = CGRect(x: area.minX, y: CGFloat(image.height) - area.maxY, width: area.width, height: area.height)
        guard let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(filtered, from: ciArea) else { throw EditorRenderer.ExportError.render }
        output.translateBy(x: area.minX, y: area.maxY); output.scaleBy(x: 1, y: -1)
        output.draw(result, in: CGRect(origin: .zero, size: area.size))
        return output.makeImage()!
    }
    static func main() throws {
        let legacy = CommandLine.arguments.contains("--legacy")
        let context = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.12, green: 0.23, blue: 0.45, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        for row in 0..<108 {
            for column in 0..<192 {
                context.setFillColor(CGColor(red: CGFloat(column % 7) / 7, green: CGFloat(row % 11) / 11, blue: CGFloat((column + row) % 13) / 13, alpha: 1))
                context.fill(CGRect(x: column * 20, y: row * 20, width: 14, height: 14))
            }
        }
        let image = context.makeImage()!
        for style in EditorBlurStyle.allCases {
            var milliseconds: [Double] = []
            for step in 0..<16 {
                try autoreleasepool {
                    var blur = EditorObject(kind: .blur, start: CGPoint(x: 400 + step * 14, y: 500), end: CGPoint(x: 1000 + step * 14, y: 780))
                    blur.blurStyle = style; blur.blurRadius = 24
                    let start = DispatchTime.now().uptimeNanoseconds
                    let rendered = try legacy ? legacyFrame(image: image, object: blur) : EditorRenderer.render(image: image, objects: [blur])
                    precondition(rendered.width == image.width && rendered.height == image.height)
                    milliseconds.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                }
            }
            let sorted = milliseconds.dropFirst(2).sorted()
            print("\(legacy ? "legacy" : "full-frame") \(style.rawValue): 4K, 600×280 region, n=\(sorted.count), median=\(String(format: "%.2f", sorted[sorted.count / 2])) ms, p95=\(String(format: "%.2f", sorted[Int(Double(sorted.count - 1) * 0.95)])) ms")
            if legacy { continue }
            var object = EditorObject(kind: .blur, start: CGPoint(x: 400, y: 500), end: CGPoint(x: 1000, y: 780))
            object.blurStyle = style; object.blurRadius = 24
            let preparedAt = DispatchTime.now().uptimeNanoseconds
            let patch = try EditorRenderer.blurPatch(image: image, object: object)!
            let preparation = Double(DispatchTime.now().uptimeNanoseconds - preparedAt) / 1_000_000
            var cached: [Double] = []
            for step in 0..<16 {
                try autoreleasepool {
                    let moved = object.translated(by: CGSize(width: step * 14, height: 0))
                    precondition(patch.matches(moved) && patch.rect.contains(moved.rect), "Prepared movement reserve is incomplete")
                    let start = DispatchTime.now().uptimeNanoseconds
                    let output = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    output.translateBy(x: 0, y: 2160); output.scaleBy(x: 1, y: -1)
                    EditorRenderer.drawBase(image: image, in: output)
                    EditorRenderer.drawBlurPatch(patch, clippedTo: moved.rect, in: output)
                    let rendered = output.makeImage()!
                    cached.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                    let expected = try EditorRenderer.render(image: image, objects: [moved])
                    for point in [CGPoint(x: moved.rect.midX, y: moved.rect.midY), CGPoint(x: moved.rect.maxX - 4, y: moved.rect.minY + 4), CGPoint(x: 402, y: 502)] {
                        let a = EditorRenderer.pixelColor(rendered, x: Int(point.x), y: Int(point.y))!
                        let b = EditorRenderer.pixelColor(expected, x: Int(point.x), y: Int(point.y))!
                        guard zip([a.redComponent, a.greenComponent, a.blueComponent], [b.redComponent, b.greenComponent, b.blueComponent]).allSatisfy({ abs($0 - $1) < 0.02 }) else {
                            throw NSError(domain: "SyntheticBlurPixelGate", code: 1, userInfo: [NSLocalizedDescriptionKey:
                                "\(style.rawValue) step=\(step) point=\(point) cached=\([a.redComponent, a.greenComponent, a.blueComponent]) export=\([b.redComponent, b.greenComponent, b.blueComponent])"])
                        }
                    }
                }
            }
            let times = cached.dropFirst(2).sorted()
            print("cached-mask \(style.rawValue): same 4K output, median=\(String(format: "%.2f", times[times.count / 2])) ms, p95=\(String(format: "%.2f", times[Int(Double(times.count - 1) * 0.95)])) ms, one-time reserve=\(String(format: "%.2f", preparation)) ms, filter jobs during 16 moves=0, bytes=\(patch.byteCount), pixel gate passed")
        }
        if !legacy {
            let large = EditorObject(kind: .blur, start: .zero, end: CGPoint(x: image.width, y: image.height))
            let limited = try EditorRenderer.blurPatch(image: image, object: large, maximumPixels: 1_000_000)!
            precondition(limited.image.width * limited.image.height < 1_010_000 && limited.rect.contains(large.rect), "Large live preview exceeded its pixel budget")
            print("Large-region preview pixel budget passed; export remains at full source resolution")
        }
    }
}

import AppKit
import CoreImage
import ImageIO
import SnagForgeDomain

/// Shared top-left pixel-space composition for canvas, PNG and pasteboard.
private final class ImageAssetCache: @unchecked Sendable {
    let images = NSCache<NSString, CGImage>()
    init() { images.totalCostLimit = 128_000_000 }
}

enum EditorRenderer {
    private static let assetCache = ImageAssetCache()
    static func cachedAssetImage(_ asset: EditorImageAsset) -> CGImage? { assetCache.images.object(forKey: asset.digest as NSString) }
    static func validateAssets(_ objects: [EditorObject]) throws {
        for asset in objects.compactMap(\.imageAsset) {
            guard assetImage(asset) != nil else { throw ProjectError.invalidDocument }
        }
    }
    static func assetImage(_ asset: EditorImageAsset) -> CGImage? {
        if let image = assetCache.images.object(forKey: asset.digest as NSString) { return image }
        guard let source = CGImageSourceCreateWithData(asset.png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete, CGImageSourceGetCount(source) == 1,
              image.width == asset.size.width, image.height == asset.size.height else { return nil }
        assetCache.images.setObject(image, forKey: asset.digest as NSString, cost: image.bytesPerRow * image.height)
        return image
    }
    static func pixelColor(_ image: CGImage, x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let converted = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy); context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
        }
        guard converted else { return nil }
        let alpha = CGFloat(rgba[3]) / 255, divisor = max(CGFloat(rgba[3]), 1)
        return NSColor(srgbRed: CGFloat(rgba[0]) / divisor, green: CGFloat(rgba[1]) / divisor,
                       blue: CGFloat(rgba[2]) / divisor, alpha: alpha)
    }
    static func color(_ object: EditorObject) -> NSColor {
        NSColor(srgbRed: object.color.red, green: object.color.green, blue: object.color.blue, alpha: 1)
    }
    static func bounds(_ object: EditorObject) -> CGRect {
        switch object.kind {
        case .arrow where object.effectiveDrawingStyle == .handDrawn:
            EditorHandDrawn.path(for: object).boundingBoxOfPath
        case .text: textRect(object)
        case .callout: calloutPath(object).boundingBoxOfPath
        case .highlight where object.effectiveHighlightStyle.mode == .freehand:
            highlightPath(object).boundingBoxOfPath.insetBy(dx: -object.lineWidth / 2, dy: -object.lineWidth / 2)
        default: object.rect
        }
    }
    private static func drawBlur(image: CGImage, object: EditorObject, context: CGContext) {
        let area = object.rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !area.isNull, area.width > 0, area.height > 0 else { return }
        let ciArea = CGRect(x: area.minX, y: CGFloat(image.height) - area.maxY, width: area.width, height: area.height)
        let filtered = CIImage(cgImage: image).clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: object.blurRadius])
        if let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(filtered, from: ciArea) {
            context.saveGState()
            context.translateBy(x: area.minX, y: area.maxY); context.scaleBy(x: 1, y: -1)
            context.draw(result, in: CGRect(origin: .zero, size: area.size))
            context.restoreGState()
        } else {
            // Fail closed: never silently expose the original region if filtering fails.
            context.setFillColor(NSColor.black.cgColor); context.fill(area)
        }
    }
    static func font(_ object: EditorObject) -> NSFont {
        let style = object.effectiveTextStyle
        let weight: NSFont.Weight = style.weight == .bold ? .bold : style.weight == .semibold ? .semibold : .regular
        let base = style.family.flatMap { NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: $0]), size: object.fontSize) }
            ?? NSFont.systemFont(ofSize: object.fontSize, weight: weight)
        var traits = base.fontDescriptor.symbolicTraits
        if style.weight != .regular { traits.insert(.bold) } else { traits.remove(.bold) }
        if style.italic { traits.insert(.italic) } else { traits.remove(.italic) }
        // Preserve the exact legacy system semibold face; apply traits to custom families/italics.
        if style.family == nil && !style.italic { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: object.fontSize) ?? base
    }
    static func textAttributes(_ object: EditorObject) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        switch object.effectiveTextStyle.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        return [.font: font(object), .foregroundColor: color(object), .paragraphStyle: paragraph]
    }
    /// Auto-width text first measures left-aligned, so alignment never uses the million-pixel sentinel.
    static func textContainerWidth(_ object: EditorObject) -> CGFloat {
        if let width = object.textWidth { return width }
        guard object.effectiveTextStyle.alignment != .left else { return 1_000_000 }
        var measured = object; var style = object.effectiveTextStyle; style.alignment = .left; measured.textStyle = style
        return max(1, textRect(measured).width)
    }
    /// Each layout owns its text system. It is never shared across render jobs.
    private static func textLayout(_ object: EditorObject) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(string: object.text, attributes: textAttributes(object))
        let layout = NSLayoutManager()
        layout.usesFontLeading = true
        let container = NSTextContainer(size: CGSize(width: textContainerWidth(object), height: 1_000_000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return (storage, layout, container)
    }
    static func textRect(_ object: EditorObject) -> CGRect {
        let (storage, layout, container) = textLayout(object)
        return withExtendedLifetime(storage) {
            var size = layout.usedRect(for: container).size
            size.width = object.textWidth ?? size.width
            size.height = max(size.height, layout.extraLineFragmentRect.maxY)
            if object.kind == .callout { size.height = max(size.height, object.textHeight ?? 0) }
            return CGRect(origin: object.start, size: size)
        }
    }
    static func calloutBox(_ object: EditorObject) -> CGRect { textRect(object).insetBy(dx: -12, dy: -10) }
    static func calloutTip(_ object: EditorObject) -> CGPoint {
        let box = calloutBox(object)
        let right = min(box.maxX - 8, box.minX + 44)
        return object.calloutTip ?? CGPoint(x: min(box.minX + 18, right - 8) + 2, y: box.maxY + 25)
    }
    static func calloutPath(_ object: EditorObject) -> CGPath {
        let box = calloutBox(object), tip = calloutTip(object)
        let r: CGFloat = min(8, box.width / 2, box.height / 2)
        let left = box.minX, right = box.maxX, top = box.minY, bottom = box.maxY
        // 0 top, 1 right, 2 bottom, 3 left. A tip inside the frame hides the tail.
        let dx = (tip.x - box.midX) / max(1, box.width), dy = (tip.y - box.midY) / max(1, box.height)
        let side = box.contains(tip) ? -1 : abs(dx) > abs(dy) ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0)
        let path = CGMutablePath()
        func edge(_ from: CGPoint, _ to: CGPoint, _ index: Int) {
            path.addLine(to: from)
            if side == index {
                let length = hypot(to.x - from.x, to.y - from.y)
                let half = min(13, length / 3)
                let ux = (to.x - from.x) / max(1, length), uy = (to.y - from.y) / max(1, length)
                let centre = min(length - half, max(half, (tip.x - from.x) * ux + (tip.y - from.y) * uy))
                if object.calloutTip == nil && index == 2 {
                    let tailRight = min(right - r, left + 44), tailLeft = min(left + 18, tailRight - 8)
                    path.addLine(to: CGPoint(x: tailRight, y: bottom)); path.addLine(to: tip)
                    path.addLine(to: CGPoint(x: tailLeft, y: bottom))
                } else {
                    path.addLine(to: CGPoint(x: from.x + ux * (centre - half), y: from.y + uy * (centre - half)))
                    path.addLine(to: tip)
                    path.addLine(to: CGPoint(x: from.x + ux * (centre + half), y: from.y + uy * (centre + half)))
                }
            }
            path.addLine(to: to)
        }
        path.move(to: CGPoint(x: left + r, y: top))
        edge(CGPoint(x: left + r, y: top), CGPoint(x: right - r, y: top), 0)
        path.addQuadCurve(to: CGPoint(x: right, y: top + r), control: CGPoint(x: right, y: top))
        edge(CGPoint(x: right, y: top + r), CGPoint(x: right, y: bottom - r), 1)
        path.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        edge(CGPoint(x: right - r, y: bottom), CGPoint(x: left + r, y: bottom), 2)
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - r), control: CGPoint(x: left, y: bottom))
        edge(CGPoint(x: left, y: bottom - r), CGPoint(x: left, y: top + r), 3)
        path.addQuadCurve(to: CGPoint(x: left + r, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()
        return path
    }
    private static func drawText(_ object: EditorObject) {
        let (storage, layout, container) = textLayout(object)
        withExtendedLifetime(storage) {
            layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container), at: object.start)
        }
    }
    static func drawBase(image: CGImage, in context: CGContext, size: CGSize? = nil) {
        let size = size ?? CGSize(width: image.width, height: image.height)
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }
    static func draw(image: CGImage, objects: [EditorObject], in context: CGContext) {
        drawBase(image: image, in: context)
        for object in EditorLayers.paintOrder(objects) where object.kind == .blur { drawBlur(image: image, object: object, context: context) }
        drawAnnotations(objects: objects, in: context)
    }
    /// Cheap vector pass, used synchronously during mouse tracking as well as export.
    static func drawAnnotations(objects: [EditorObject], in context: CGContext, editingTextID: UUID? = nil, cachedAssetsOnly: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for object in EditorLayers.paintOrder(objects) {
            switch object.kind {
            case .image:
                if let asset = object.imageAsset, let image = cachedAssetsOnly ? cachedAssetImage(asset) : assetImage(asset) {
                    context.saveGState()
                    context.translateBy(x: object.rect.minX, y: object.rect.minY)
                    drawBase(image: image, in: context, size: object.rect.size)
                    context.restoreGState()
                }
            case .highlight:
                drawHighlight(object, in: context)
            case .step:
                drawStep(object, in: context)
            case .text:
                if object.id != editingTextID { drawText(object) }
            case .blur: break
            case .redact:
                drawRedactions(objects: [object], in: context)
            case .rectangle, .ellipse, .triangle, .diamond, .star:
                context.saveGState()
                drawShape(shapePath(object), object: object, in: context)
                context.restoreGState()
            case .callout:
                context.saveGState()
                drawShape(calloutPath(object), object: object, in: context)
                context.restoreGState()
                if object.id != editingTextID { drawText(object) }
            case .arrow:
                context.saveGState()
                context.setStrokeColor(color(object).cgColor)
                context.setFillColor(color(object).cgColor)
                context.setLineWidth(object.lineWidth)
                context.setLineCap(.round)
                if object.effectiveDrawingStyle == .handDrawn {
                    context.setLineJoin(.round)
                    context.addPath(EditorHandDrawn.path(for: object)); context.strokePath()
                    context.restoreGState()
                    continue
                }
                let angle = atan2(object.end.y - object.start.y, object.end.x - object.start.x)
                let length = min(hypot(object.end.x - object.start.x, object.end.y - object.start.y) * 0.45, object.lineWidth * 4)
                let back = CGPoint(x: object.end.x - cos(angle) * length, y: object.end.y - sin(angle) * length)
                context.move(to: object.start); context.addLine(to: back); context.strokePath()
                context.move(to: object.end)
                context.addLine(to: CGPoint(x: back.x - sin(angle) * length * 0.45, y: back.y + cos(angle) * length * 0.45))
                context.addLine(to: CGPoint(x: back.x + sin(angle) * length * 0.45, y: back.y - cos(angle) * length * 0.45))
                context.closePath(); context.fillPath()
                context.restoreGState()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func highlightPath(_ object: EditorObject) -> CGPath {
        let path = CGMutablePath()
        let points = object.effectiveHighlightStyle.points
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.001, y: first.y)) }
        else { for point in points.dropFirst() { path.addLine(to: point) } }
        return path
    }
    private static func drawHighlight(_ object: EditorObject, in context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        context.setBlendMode(.multiply); context.setAlpha(object.effectiveHighlightStyle.opacity)
        context.setFillColor(color(object).cgColor); context.setStrokeColor(color(object).cgColor)
        if object.effectiveHighlightStyle.mode == .freehand {
            context.setLineWidth(object.lineWidth); context.setLineCap(.round); context.setLineJoin(.round)
            context.addPath(highlightPath(object)); context.strokePath()
        } else { context.fill(object.rect) }
    }
    static func stepPath(_ object: EditorObject) -> CGPath {
        let path = CGMutablePath(), rect = object.rect
        switch object.stepStyle?.shape ?? .circle {
        case .circle: path.addEllipse(in: rect)
        case .roundedRectangle:
            let radius = min(rect.width, rect.height) * 0.2
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        case .diamond:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); path.closeSubpath()
        case .pointer:
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY))
            path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY),
                          control1: CGPoint(x: rect.minX - rect.width * 0.12, y: rect.minY),
                          control2: CGPoint(x: rect.minX - rect.width * 0.12, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); path.closeSubpath()
        }
        return path
    }
    static func drawStep(_ object: EditorObject, in context: CGContext) {
        guard let style = object.stepStyle else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.setFillColor(color(object).cgColor); context.addPath(stepPath(object)); context.fillPath()
        let rect = object.rect
        let baseSize = min(rect.width, rect.height) * (style.shape == .diamond ? 0.42 : 0.5)
        var font = NSFont.systemFont(ofSize: baseSize, weight: .bold)
        let available = rect.width * (style.shape == .diamond ? 0.5 : style.shape == .pointer ? 0.55 : 0.72)
        let measured = (style.label as NSString).size(withAttributes: [.font: font])
        if measured.width > available { font = NSFont.systemFont(ofSize: baseSize * available / measured.width, weight: .bold) }
        let attributes: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: NSColor(srgbRed: style.textColor.red, green: style.textColor.green, blue: style.textColor.blue, alpha: 1)]
        let size = (style.label as NSString).size(withAttributes: attributes)
        let centreX = style.shape == .pointer ? rect.minX + rect.width * 0.4 : rect.midX
        (style.label as NSString).draw(at: CGPoint(x: centreX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
    /// Round outward to device pixels and replace them opaquely. No edge antialiasing.
    static func drawRedactions(objects: [EditorObject], in context: CGContext) {
        context.saveGState()
        context.setShouldAntialias(false); context.setBlendMode(.copy); context.setAlpha(1)
        for object in objects where object.kind == .redact {
            let pixels = context.convertToDeviceSpace(object.rect).standardized.integral
            guard pixels.width > 0, pixels.height > 0 else { continue }
            context.setFillColor(color(object).cgColor)
            context.fill(context.convertToUserSpace(pixels))
        }
        context.restoreGState()
    }
    /// Also used by the form picker so its icons match the actual exported geometry.
    static func shapePath(_ object: EditorObject) -> CGPath {
        let path = CGMutablePath(), rect = object.rect
        switch object.kind {
        case .rectangle:
            let radius = min(object.cornerRadius ?? 0, rect.width / 2, rect.height / 2)
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        case .ellipse:
            if object.effectiveDrawingStyle == .handDrawn { return EditorHandDrawn.path(for: object) }
            path.addEllipse(in: rect)
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath()
        case .diamond:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); path.closeSubpath()
        case .star:
            for index in 0..<10 {
                let angle = CGFloat(index) * .pi / 5 - .pi / 2
                let radius: CGFloat = index.isMultiple(of: 2) ? 1 : 0.42
                let point = CGPoint(x: rect.midX + cos(angle) * rect.width / 2 * radius,
                                    y: rect.midY + sin(angle) * rect.height / 2 * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        default: break
        }
        return path
    }
    private static func drawShape(_ path: CGPath, object: EditorObject, in context: CGContext) {
        let fill = object.effectiveFill
        if fill.isEnabled {
            context.setFillColor(NSColor(srgbRed: fill.color.red, green: fill.color.green, blue: fill.color.blue, alpha: fill.opacity).cgColor)
            context.addPath(path); context.fillPath()
        }
        let stroke = object.effectiveStroke
        if stroke.isEnabled {
            context.setStrokeColor(color(object).cgColor); context.setLineWidth(object.lineWidth)
            context.setLineJoin(.round)
            if object.effectiveDrawingStyle == .handDrawn { context.setLineCap(.round) }
            switch stroke.style {
            case .solid: context.setLineDash(phase: 0, lengths: [])
            case .dashed: context.setLineDash(phase: 0, lengths: [object.lineWidth * 3, object.lineWidth * 2])
            case .dotted:
                context.setLineCap(.round)
                context.setLineDash(phase: 0, lengths: [0, object.lineWidth * 2])
            }
            context.addPath(path); context.strokePath()
        }
    }
    static func render(image: CGImage, objects: [EditorObject], crop: CGRect? = nil, resizedSize: PixelSize? = nil, maxDimension: Int? = nil) throws -> CGImage {
        try validateAssets(objects)
        let size = PixelSize(width: image.width, height: image.height)!
        let area = crop ?? EditorCrop.fullRect(size)
        guard EditorCrop.isValid(area, in: size) else { throw ExportError.render }
        if let resizedSize {
            guard EditorResize.isValid(resizedSize) else { throw ExportError.render }
            let factor = maxDimension.map { min(1, CGFloat($0) / CGFloat(max(resizedSize.width, resizedSize.height))) } ?? 1
            let width = max(1, Int((CGFloat(resizedSize.width) * factor).rounded()))
            let height = max(1, Int((CGFloat(resizedSize.height) * factor).rounded()))
            if CGFloat(width) == area.width && CGFloat(height) == area.height {
                return try render(image: image, objects: objects, crop: crop)
            }
            // Apply raster effects and opaque masks before sampling: secret source
            // pixels must not bleed into neighbouring pixels during downsampling.
            let rasterObjects = objects.filter { $0.kind == .blur || $0.kind == .redact }
            let base: CGImage
            if rasterObjects.isEmpty {
                guard let cut = image.cropping(to: area) else { throw ExportError.render }
                base = cut
            } else {
                base = try render(image: image, objects: rasterObjects, crop: crop)
            }
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExportError.render }
            context.interpolationQuality = .high
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: CGFloat(width) / area.width, y: -CGFloat(height) / area.height)
            context.translateBy(x: -area.minX, y: -area.minY)
            context.clip(to: area)
            // Sample the source once and rasterize text/vector objects directly
            // at the output resolution. A flattened intermediate softens their edges.
            // Opaque redactions are painted last on the destination pixel grid.
            context.saveGState()
            context.translateBy(x: area.minX, y: area.minY)
            drawBase(image: base, in: context)
            context.restoreGState()
            drawAnnotations(objects: objects, in: context)
            guard let result = context.makeImage() else { throw ExportError.render }
            return result
        }
        if let crop {
            // Compose in original coordinates first. Translating vector paths before rasterizing
            // changes CoreGraphics edge antialiasing, even for integer pixel offsets.
            // Cutting the composed pixels also keeps blur sampling independent of the crop.
            let full = try render(image: image, objects: objects)
            guard let cut = full.cropping(to: crop) else { throw ExportError.render }
            if let maxDimension, max(cut.width, cut.height) > maxDimension {
                return try render(image: cut, objects: [], maxDimension: maxDimension)
            }
            return cut
        }
        let scale = maxDimension.map { min(1, CGFloat($0) / max(area.width, area.height)) } ?? 1
        let width = max(1, Int(area.width * scale)), height = max(1, Int(area.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExportError.render }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)
        context.clip(to: area)
        draw(image: image, objects: objects, in: context)
        guard let rendered = context.makeImage() else { throw ExportError.render }
        return rendered
    }
    static func thumbnail(image: CGImage, objects: [EditorObject], crop: CGRect? = nil, resizedSize: PixelSize? = nil) throws -> Data {
        let rendered = try render(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: 420)
        guard let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { throw ExportError.render }
        return data
    }
    static func png(image: CGImage, objects: [EditorObject], crop: CGRect? = nil, resizedSize: PixelSize? = nil) throws -> Data {
        let rendered = try render(image: image, objects: objects, crop: crop, resizedSize: resizedSize)
        guard let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { throw ExportError.render }
        return data
    }
    enum ExportError: LocalizedError {
        case render
        var errorDescription: String? { String(localized: "Das Bild konnte nicht gerendert werden. Möglicherweise reicht der Arbeitsspeicher nicht aus.") }
    }
}

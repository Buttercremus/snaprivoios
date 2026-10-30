import AppKit
import CoreImage
import ImageIO
import SnagForgeDomain

/// Source-space filter pixels with room for pointer movement. Geometry never changes the filter's sampling origin.
struct EditorBlurPatch: Sendable {
    let objectID: UUID
    let style: EditorBlurStyle
    let radius: CGFloat
    let rect: CGRect
    let image: CGImage
    var byteCount: Int { image.bytesPerRow * image.height }
    func matches(_ object: EditorObject) -> Bool {
        objectID == object.id && style == object.effectiveBlurStyle && radius == object.blurRadius
    }
}

/// Prepared off the main actor before replacing the visible editor. Only transient pixels, never persisted.
struct EditorCanvasPreparation: Sendable {
    let project: UUID
    let revision: Int
    let blurPatches: [EditorBlurPatch]
    let magnifierImage: CGImage?
    let magnifierSourceSize: CGSize?
    let magnifierObjects: [EditorObject]?
    let wallpaper: CGImage?

    static func prepare(image: CGImage, document: ProjectDocument) throws -> Self {
        try Task.checkCancellation()
        try EditorRenderer.validateAssets(document.objects)
        let blurs = document.objects.filter { $0.kind == .blur }
        let patches = try blurs.compactMap { try EditorRenderer.blurPatch(image: image, object: $0, maximumPixels: 8_000_000 / max(1, blurs.count)) }
        let magnifierObjects = document.objects.contains { $0.kind == .magnifier } ? document.objects.filter { $0.kind != .magnifier } : nil
        let magnifier = try magnifierObjects.map { try EditorRenderer.renderMagnifierPreview(image: image, objects: $0) }
        let wallpaper = try EditorRenderer.preparePresentationWallpaper(document.presentation?.background)
        try Task.checkCancellation()
        return Self(project: document.id, revision: document.revision, blurPatches: patches,
                    magnifierImage: magnifier?.image, magnifierSourceSize: magnifier?.originalSize,
                    magnifierObjects: magnifierObjects, wallpaper: wallpaper)
    }
}

/// Shared top-left pixel-space composition for canvas, PNG and pasteboard.
private final class ImageAssetCache: @unchecked Sendable {
    let images = NSCache<NSString, CGImage>()
    init() { images.totalCostLimit = 128_000_000 }
}

/// A process-wide admission gate for transient full-size rasters. It prevents two
/// expensive exports/previews from silently multiplying their peak memory.
private final class RasterMemoryBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var reserved = 0
    // Keep headroom for the OS and other apps; this is a work-admission budget, not an RSS promise.
    let limit = Int(min(2_147_483_648, max(536_870_912, ProcessInfo.processInfo.physicalMemory / 4)))

    func reserve(_ bytes: Int) -> Bool {
        guard bytes > 0, bytes <= limit else { return false }
        lock.lock(); defer { lock.unlock() }
        guard reserved <= limit - bytes else { return false }
        reserved += bytes
        return true
    }
    func release(_ bytes: Int) {
        lock.lock(); reserved = max(0, reserved - bytes); lock.unlock()
    }
    func snapshot() -> (reserved: Int, limit: Int) {
        lock.lock(); defer { lock.unlock() }
        return (reserved, limit)
    }
}

private final class TextGeometryKey: NSObject, @unchecked Sendable {
    let text: String
    let kind: EditorObject.Kind
    let fontSize: CGFloat
    let width: CGFloat?
    let minimumHeight: CGFloat?
    let style: EditorTextStyle
    private let cachedHash: Int
    init(_ object: EditorObject) {
        text = object.text; kind = object.kind; fontSize = object.fontSize; width = object.textWidth
        minimumHeight = object.kind == .callout ? object.textHeight : nil
        style = object.effectiveTextStyle
        var hasher = Hasher()
        hasher.combine(text); hasher.combine(kind); hasher.combine(fontSize); hasher.combine(width); hasher.combine(minimumHeight)
        hasher.combine(style.family); hasher.combine(style.weight); hasher.combine(style.italic); hasher.combine(style.alignment)
        cachedHash = hasher.finalize()
    }
    override var hash: Int { cachedHash }
    override func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? TextGeometryKey else { return false }
        return kind == other.kind && text == other.text && fontSize == other.fontSize && width == other.width
            && minimumHeight == other.minimumHeight && style == other.style
    }
    var cost: Int { text.utf8.count + 128 }
}

private final class TextGeometryCache: @unchecked Sendable {
    let values = NSCache<TextGeometryKey, NSValue>()
    private let lock = NSLock()
    private var hits = 0
    private var misses = 0
    init() { values.countLimit = 512; values.totalCostLimit = 4 * 1024 * 1024 }
    func key(for object: EditorObject) -> TextGeometryKey { TextGeometryKey(object) }
    func hit() { lock.lock(); hits += 1; lock.unlock() }
    func miss() { lock.lock(); misses += 1; lock.unlock() }
    var statistics: (hits: Int, misses: Int) { lock.lock(); defer { lock.unlock() }; return (hits, misses) }
    func resetStatistics() { lock.lock(); hits = 0; misses = 0; lock.unlock() }
    func set(_ value: NSValue, forKey key: TextGeometryKey) { values.setObject(value, forKey: key, cost: key.cost) }
    func value(forKey key: TextGeometryKey) -> NSValue? { values.object(forKey: key) }
}

enum EditorRenderer {
    struct MagnifierPreview: Sendable {
        let image: CGImage
        let originalSize: CGSize
    }
    // CIContext is thread-safe and retains expensive kernel/command-queue setup across renders.
    private static let blurContext = CIContext(options: [.cacheIntermediates: false])
    private static let assetCache = ImageAssetCache()
    private static let rasterBudget = RasterMemoryBudget()
    private static let textGeometryCache = TextGeometryCache()
    static var rasterBudgetSnapshot: (reserved: Int, limit: Int) { rasterBudget.snapshot() }
    static var textGeometryCacheStatistics: (hits: Int, misses: Int) { textGeometryCache.statistics }
    static func resetTextGeometryCacheStatistics() { textGeometryCache.resetStatistics() }
    static func rasterMemoryEstimate(image: CGImage, objects: [EditorObject] = [], crop: CGRect? = nil, resizedSize: PixelSize? = nil,
                                         maxDimension: Int? = nil, canvasRect: CGRect? = nil, transform: EditorImageTransform = .identity,
                                         presentation: EditorPresentation? = nil, encoding: Bool = false) -> Int {
        rasterBytes(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: maxDimension,
                    canvasRect: canvasRect, transform: transform, presentation: presentation, encoding: encoding)
    }
    /// Owns a reservation over all nested synchronous work, including encoding when requested.
    static func withRasterReservation<Value>(_ bytes: Int, operation: () throws -> Value) throws -> Value {
        try Task.checkCancellation()
        guard rasterBudget.reserve(bytes) else { throw ExportError.memoryBudget }
        defer { rasterBudget.release(bytes) }
        try Task.checkCancellation()
        let result = try operation()
        try Task.checkCancellation()
        return result
    }
    static func cachedAssetImage(_ asset: EditorImageAsset) -> CGImage? { assetCache.images.object(forKey: asset.digest as NSString) }
    static func validateAssets(_ objects: [EditorObject]) throws {
        for asset in objects.compactMap(\.imageAsset) {
            try Task.checkCancellation()
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
        case .image: object.rotatedImageBounds
        case .arrow where object.effectiveDrawingStyle != .precise || object.arrowBend != nil:
            EditorArrow.path(for: object).boundingBoxOfPath
        case .pen: object.penStroke?.path.boundingBoxOfPath.insetBy(dx: -object.lineWidth / 2, dy: -object.lineWidth / 2) ?? object.rect
        case .text: textRect(object)
        case .callout: calloutPath(object).boundingBoxOfPath
        case .highlight where object.effectiveHighlightStyle.mode == .freehand:
            highlightPath(object).boundingBoxOfPath.insetBy(dx: -object.lineWidth / 2, dy: -object.lineWidth / 2)
        default: object.rect
        }
    }
    /// Visible ink, including outline thickness and arrowheads; selection handles are excluded.
    static func paintedBounds(_ object: EditorObject) -> CGRect {
        switch object.kind {
        case .rectangle, .ellipse, .triangle, .diamond, .star, .callout:
            guard object.effectiveStroke.isEnabled || object.effectiveFill.isEnabled else { return .null }
            let path = object.kind == .callout ? calloutPath(object) : shapePath(object)
            let outline = object.effectiveStroke.isEnabled ? drawingLineWidth(object) / 2 : 0
            return path.boundingBoxOfPath.insetBy(dx: -outline, dy: -outline)
        case .magnifier: return object.rect.union(object.magnifierSourceRect).insetBy(dx: -object.lineWidth / 2, dy: -object.lineWidth / 2)
        case .arrow:
            if object.effectiveDrawingStyle != .precise || object.arrowBend != nil {
                let width = drawingLineWidth(object)
                return EditorArrow.path(for: object).boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2)
            }
            let angle = atan2(object.end.y - object.start.y, object.end.x - object.start.x)
            let length = min(hypot(object.end.x - object.start.x, object.end.y - object.start.y) * 0.45, object.lineWidth * 4)
            let back = CGPoint(x: object.end.x - cos(angle) * length, y: object.end.y - sin(angle) * length)
            let shaft = CGRect(x: min(object.start.x, back.x), y: min(object.start.y, back.y),
                               width: abs(object.start.x - back.x), height: abs(object.start.y - back.y))
                .insetBy(dx: -object.lineWidth / 2, dy: -object.lineWidth / 2)
            let head = CGMutablePath(); head.move(to: object.end)
            head.addLine(to: CGPoint(x: back.x - sin(angle) * length * 0.45, y: back.y + cos(angle) * length * 0.45))
            head.addLine(to: CGPoint(x: back.x + sin(angle) * length * 0.45, y: back.y - cos(angle) * length * 0.45))
            return shaft.union(head.boundingBoxOfPath)
        default: return bounds(object)
        }
    }
    private static func blurSource(image: CGImage, object: EditorObject) -> CIImage {
        let source = CIImage(cgImage: image).clampedToExtent()
        let filtered: CIImage
        switch object.effectiveBlurStyle {
        case .gaussian:
            filtered = source.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: object.blurRadius])
        case .pixelate:
            filtered = source.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(2, object.blurRadius), kCIInputCenterKey: CIVector(x: 0, y: 0)])
        case .mosaic:
            filtered = source.applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: max(2, object.blurRadius), kCIInputCenterKey: CIVector(x: 0, y: 0)])
        }
        return filtered
    }
    private static func drawBlur(image: CGImage, object: EditorObject, context: CGContext) {
        let area = object.rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !area.isNull, area.width > 0, area.height > 0 else { return }
        // Evaluate with a sampling reserve before clipping. Pixel/mosaic kernels
        // must not change their edge samples when only the masking rectangle moves.
        if let patch = try? blurPatch(image: image, object: object, maximumPixels: Int.max) {
            drawBlurPatch(patch, clippedTo: area, in: context)
        } else {
            // Fail closed: never silently expose the original region if filtering fails.
            context.setFillColor(NSColor.black.cgColor); context.fill(area)
        }
    }
    static func blurPatch(image: CGImage, object: EditorObject, maximumPixels: Int = 8_000_000) throws -> EditorBlurPatch? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = object.rect.intersection(bounds)
        guard !area.isNull, area.width > 0, area.height > 0 else { return nil }
        let expanded = area.insetBy(dx: -256, dy: -256).integral.intersection(bounds)
        let scale = min(1, sqrt(Double(max(1, maximumPixels)) / (expanded.width * expanded.height)))
        let ciArea = CGRect(x: expanded.minX, y: CGFloat(image.height) - expanded.maxY, width: expanded.width, height: expanded.height)
            .applying(CGAffineTransform(scaleX: scale, y: scale)).integral
        let filtered = blurSource(image: image, object: object).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        try Task.checkCancellation()
        let sourceBytes = Int64(image.bytesPerRow) * Int64(image.height)
        let filteredBytes = Int64(ceil(ciArea.width)) * Int64(ceil(ciArea.height)) * 4
        let requested = min(Int64(Int.max), sourceBytes * 3 + filteredBytes)
        return try withRasterReservation(Int(requested)) {
            // Finish GPU work on the worker, not lazily during AppKit's next draw pass.
            guard let rendered = blurContext.createCGImage(filtered, from: ciArea, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB), deferred: false) else { throw ExportError.render }
            try Task.checkCancellation()
            let rect = CGRect(x: ciArea.minX / scale, y: CGFloat(image.height) - ciArea.maxY / scale,
                              width: ciArea.width / scale, height: ciArea.height / scale)
            return EditorBlurPatch(objectID: object.id, style: object.effectiveBlurStyle, radius: object.blurRadius, rect: rect, image: rendered)
        }
    }
    static func drawBlurPatch(_ patch: EditorBlurPatch, clippedTo area: CGRect, in context: CGContext) {
        context.saveGState(); context.clip(to: area)
        context.translateBy(x: patch.rect.minX, y: patch.rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(patch.image, in: CGRect(origin: .zero, size: patch.rect.size)); context.restoreGState()
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
        let key = textGeometryCache.key(for: object)
        if let cached = textGeometryCache.value(forKey: key)?.rectValue {
            textGeometryCache.hit()
            return CGRect(origin: object.start, size: cached.size)
        }
        textGeometryCache.miss()
        let (storage, layout, container) = textLayout(object)
        let result = withExtendedLifetime(storage) {
            var size = layout.usedRect(for: container).size
            size.width = object.textWidth ?? size.width
            size.height = max(size.height, layout.extraLineFragmentRect.maxY)
            if object.kind == .callout { size.height = max(size.height, object.textHeight ?? 0) }
            return CGRect(origin: object.start, size: size)
        }
        textGeometryCache.set(NSValue(rect: CGRect(origin: .zero, size: result.size)), forKey: key)
        return result
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
    static func draw(image: CGImage, objects: [EditorObject], in context: CGContext) throws {
        drawBase(image: image, in: context)
        for object in EditorLayers.paintOrder(objects) where object.kind == .blur { drawBlur(image: image, object: object, context: context) }
        drawAnnotations(objects: objects, in: context, magnifierSource: try magnifierSourceUnbudgeted(image: image, objects: objects))
    }
    /// Cheap vector pass, used synchronously during mouse tracking as well as export.
    static func drawAnnotations(objects: [EditorObject], in context: CGContext, editingTextID: UUID? = nil, cachedAssetsOnly: Bool = false, magnifierSource: CGImage? = nil, magnifierSourceSize: CGSize? = nil) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawSpotlights(objects: objects, in: context)
        for object in EditorLayers.paintOrder(objects) {
            switch object.kind {
            case .spotlight: break
            case .pen:
                if let pen = object.penStroke {
                    context.saveGState()
                    context.setStrokeColor(color(object).cgColor); context.setLineWidth(object.lineWidth)
                    context.setLineCap(.round); context.setLineJoin(.round)
                    context.addPath(pen.path); context.strokePath(); context.restoreGState()
                }
            case .magnifier:
                drawMagnifier(object, source: magnifierSource, sourceSize: magnifierSourceSize, in: context)
            case .image:
                if let asset = object.imageAsset, let image = cachedAssetsOnly ? cachedAssetImage(asset) : assetImage(asset) {
                    context.saveGState()
                    context.concatenate(object.imageRotationTransform)
                    if object.imageRotationDegrees != nil { context.interpolationQuality = .high }
                    context.translateBy(x: object.rect.minX, y: object.rect.minY)
                    let rect = CGRect(origin: .zero, size: object.rect.size)
                    drawFramedImage(image, in: context, rect: rect, radius: object.cornerRadius ?? 0,
                                    border: object.stroke?.isEnabled == true ? EditorImageBorder(width: object.lineWidth, color: object.color) : nil)
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
                context.setLineWidth(drawingLineWidth(object))
                context.setLineCap(.round)
                if object.effectiveDrawingStyle != .precise {
                    context.setLineJoin(.round)
                    context.addPath(EditorHandDrawn.path(for: object)); context.strokePath()
                    context.restoreGState()
                    continue
                }
                if object.arrowBend != nil {
                    context.addPath(EditorArrow.shaft(for: object, trimHead: true)); context.strokePath()
                    context.addPath(EditorArrow.head(for: object)); context.fillPath()
                    context.restoreGState(); continue
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
    private static func drawSpotlights(objects: [EditorObject], in context: CGContext) {
        let spotlights = objects.filter { $0.kind == .spotlight }
        guard !spotlights.isEmpty else { return }
        let area = context.boundingBoxOfClipPath
        guard !area.isNull, !area.isInfinite else { return }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(NSColor.black.withAlphaComponent(spotlights.map { $0.effectiveSpotlightStyle.opacity }.max() ?? 0.55).cgColor)
        context.fill(area)
        context.setBlendMode(.clear)
        for object in spotlights {
            context.addPath(object.effectiveSpotlightStyle.path(in: object.rect)); context.fillPath()
        }
        context.setBlendMode(.normal); context.endTransparencyLayer(); context.restoreGState()
    }
    static func drawingLineWidth(_ object: EditorObject) -> CGFloat {
        switch object.effectiveDrawingStyle {
        case .sketch: object.lineWidth * 0.65
        case .marker: object.lineWidth * 1.6
        default: object.lineWidth
        }
    }
    /// Lenses sample the flat composition with every opaque mask already applied.
    /// Excluding lenses prevents recursive feedback and keeps multiple lenses deterministic.
    static func magnifierSource(image: CGImage, objects: [EditorObject]) throws -> CGImage? {
        guard objects.contains(where: { $0.kind == .magnifier }) else { return nil }
        return try render(image: image, objects: objects.filter { $0.kind != .magnifier })
    }
    private static func magnifierSourceUnbudgeted(image: CGImage, objects: [EditorObject]) throws -> CGImage? {
        guard objects.contains(where: { $0.kind == .magnifier }) else { return nil }
        return try renderUnbudgeted(image: image, objects: objects.filter { $0.kind != .magnifier })
    }
    static func renderMagnifierPreview(image: CGImage, objects: [EditorObject], maxDimension: Int = 2048) throws -> MagnifierPreview {
        let originalSize = CGSize(width: image.width, height: image.height)
        let preview = try render(image: image, objects: objects.filter { $0.kind != .magnifier }, maxDimension: maxDimension)
        return MagnifierPreview(image: preview, originalSize: originalSize)
    }
    private static func drawMagnifier(_ object: EditorObject, source: CGImage?, sourceSize: CGSize?, in context: CGContext) {
        let rect = object.rect, zoom = object.effectiveMagnification
        context.saveGState()
        if let sourcePoint = object.magnifierSource {
            let dx = rect.midX - sourcePoint.x, dy = rect.midY - sourcePoint.y
            let length = hypot(dx, dy)
            let sourceRadius = object.magnifierSourceRect.width / 2
            if length > sourceRadius + rect.width / 2 {
                context.setStrokeColor(color(object).cgColor); context.setLineWidth(object.lineWidth)
                context.move(to: CGPoint(x: sourcePoint.x + dx / length * sourceRadius, y: sourcePoint.y + dy / length * sourceRadius))
                context.addLine(to: CGPoint(x: rect.midX - dx / length * rect.width / 2, y: rect.midY - dy / length * rect.width / 2))
                context.strokePath()
            }
            context.setStrokeColor(color(object).cgColor); context.setLineWidth(object.lineWidth)
            context.strokeEllipse(in: object.magnifierSourceRect)
        }
        context.addEllipse(in: rect); context.clip()
        context.interpolationQuality = .high
        let sample = object.magnifierSource ?? CGPoint(x: rect.midX, y: rect.midY)
        context.translateBy(x: rect.midX - sample.x * zoom, y: rect.midY - sample.y * zoom)
        context.scaleBy(x: zoom, y: zoom)
        if let source {
            let originalSize = sourceSize ?? CGSize(width: source.width, height: source.height)
            context.scaleBy(x: originalSize.width / CGFloat(source.width), y: originalSize.height / CGFloat(source.height))
            drawBase(image: source, in: context)
        }
        context.restoreGState()
        context.saveGState()
        context.setStrokeColor(color(object).cgColor); context.setLineWidth(object.lineWidth)
        context.strokeEllipse(in: rect)
        context.restoreGState()
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
        if object.kind.isShape, object.effectiveDrawingStyle != .precise { return EditorHandDrawn.path(for: object) }
        let path = CGMutablePath(), rect = object.rect
        switch object.kind {
        case .rectangle:
            let radius = min(object.cornerRadius ?? 0, rect.width / 2, rect.height / 2)
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        case .ellipse:
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
            context.setStrokeColor(color(object).cgColor); context.setLineWidth(drawingLineWidth(object))
            context.setLineJoin(.round)
            if object.effectiveDrawingStyle != .precise { context.setLineCap(.round) }
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
    static func render(image: CGImage, objects: [EditorObject], crop: CGRect? = nil, resizedSize: PixelSize? = nil, maxDimension: Int? = nil, canvasRect: CGRect? = nil, transform: EditorImageTransform = .identity, presentation: EditorPresentation? = nil) throws -> CGImage {
        let requested = rasterBytes(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: maxDimension,
                                    canvasRect: canvasRect, transform: transform, presentation: presentation, encoding: false)
        return try withRasterReservation(requested) {
            try renderUnbudgeted(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: maxDimension,
                                 canvasRect: canvasRect, transform: transform, presentation: presentation)
        }
    }

    private static func rasterBytes(image: CGImage, objects: [EditorObject], crop: CGRect?, resizedSize: PixelSize?,
                                    maxDimension: Int?, canvasRect: CGRect?, transform: EditorImageTransform,
                                    presentation: EditorPresentation?, encoding: Bool) -> Int {
        let invalid = Int.max
        func add(_ a: Int, _ b: Int) -> Int {
            let value = a.addingReportingOverflow(b); return value.overflow ? invalid : value.partialValue
        }
        func multiply(_ a: Int, _ b: Int) -> Int {
            let value = a.multipliedReportingOverflow(by: b); return value.overflow ? invalid : value.partialValue
        }
        func bytes(_ size: PixelSize) -> Int { multiply(multiply(size.width, size.height), 4) }
        guard let sourceSize = PixelSize(width: image.width, height: image.height),
              maxDimension.map({ (1...32768).contains($0) }) ?? true else { return invalid }
        let canvas = canvasRect ?? EditorCrop.fullRect(sourceSize)
        guard canvasRect.map({ EditorCanvasExtent.isValid($0) && $0.contains(EditorCrop.fullRect(sourceSize)) }) ?? true,
              crop.map({ EditorCrop.isValid($0, in: canvas) }) ?? true else { return invalid }
        let area = crop ?? canvas
        guard area.width.isFinite, area.height.isFinite, (1...32768).contains(area.width), (1...32768).contains(area.height),
              resizedSize.map(EditorResize.isValid) ?? true,
              let content = resizedSize ?? PixelSize(width: Int(ceil(area.width)), height: Int(ceil(area.height))) else { return invalid }
        let transformed = transform.applying(to: content)
        let output: PixelSize
        let hasPresentation = presentation?.isIdentity == false
        if let presentation, hasPresentation {
            guard presentation.isValid, let geometry = presentation.geometry(for: transformed) else { return invalid }
            output = geometry.outputSize
        } else { output = transformed }
        let scale = maxDimension.map { min(1, CGFloat($0) / CGFloat(max(output.width, output.height))) } ?? 1
        func scaledBytes(_ size: PixelSize) -> Int {
            // Presentation rounding can add an edge pixel before the final size clamp.
            let allowance = hasPresentation && scale < 1 ? 2 : 0
            let width = min(32768, max(1, Int(ceil(CGFloat(size.width) * scale)) + allowance))
            let height = min(32768, max(1, Int(ceil(CGFloat(size.height) * scale)) + allowance))
            return multiply(multiply(width, height), 4)
        }
        let source = multiply(image.bytesPerRow, image.height)
        let contentRaster = scaledBytes(content), outputRaster = scaledBytes(output)
        var total = add(source, contentRaster)
        if transform != .identity { total = add(total, contentRaster) }
        // A cropped image is composed at full source size before being cut. Raster
        // effects must also finish before downsampling so redacted pixels cannot bleed.
        if canvasRect == nil && crop != nil && resizedSize == nil { total = add(total, bytes(sourceSize)) }
        if objects.contains(where: { $0.kind == .blur || $0.kind == .redact }) {
            total = add(total, multiply(bytes(sourceSize), 2))
        }
        if objects.contains(where: { $0.kind == .magnifier }) { total = add(total, bytes(sourceSize)) }
        var assets = Set<String>()
        for asset in objects.compactMap(\.imageAsset) where assets.insert(asset.digest).inserted { total = add(total, bytes(asset.size)) }
        if let background = presentation?.background, case .asset(let asset, _) = background,
           assets.insert(asset.digest).inserted { total = add(total, bytes(asset.size)) }
        if hasPresentation { total = add(total, multiply(outputRaster, 2)) }
        // The encoder may retain its bitmap wrapper and a nearly incompressible output.
        if encoding { total = add(total, add(multiply(outputRaster, 2), 65_536)) }
        return total
    }

    private static func renderUnbudgeted(image: CGImage, objects: [EditorObject], crop: CGRect? = nil, resizedSize: PixelSize? = nil, maxDimension: Int? = nil, canvasRect: CGRect? = nil, transform: EditorImageTransform = .identity, presentation: EditorPresentation? = nil) throws -> CGImage {
        if let presentation, !presentation.isIdentity {
            let area = crop ?? canvasRect ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard area.width.isFinite, area.height.isFinite, (1...32768).contains(area.width), (1...32768).contains(area.height),
                  let sourceSize = resizedSize ?? PixelSize(width: Int(area.width), height: Int(area.height)) else { throw ExportError.render }
            let contentSize = transform.applying(to: sourceSize)
            guard presentation.isValid, let geometry = presentation.geometry(for: contentSize) else { throw ExportError.render }
            let scale = maxDimension.map { min(1, CGFloat($0) / CGFloat(max(geometry.outputSize.width, geometry.outputSize.height))) } ?? 1
            let limit = scale < 1 ? max(1, Int(ceil(CGFloat(max(contentSize.width, contentSize.height)) * scale))) : nil
            let composed = try renderUnbudgeted(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: limit, canvasRect: canvasRect, transform: transform)
            try Task.checkCancellation()
            let actualScale = CGFloat(composed.width) / CGFloat(contentSize.width)
            var scaled = presentation
            scaled.padding = Int((CGFloat(presentation.padding) * actualScale).rounded())
            scaled.cornerRadius *= actualScale
            if scaled.border != nil { scaled.border!.width *= actualScale }
            let presented = try self.presentedUnbudgeted(composed, by: scaled, backgroundOverride: nil, effectScale: actualScale)
            if let maxDimension, max(presented.width, presented.height) > maxDimension {
                return try renderUnbudgeted(image: presented, objects: [], maxDimension: maxDimension)
            }
            return presented
        }
        if transform != .identity {
            let composed = try renderUnbudgeted(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: maxDimension, canvasRect: canvasRect)
            return try transformed(composed, by: transform)
        }
        try validateAssets(objects)
        let size = PixelSize(width: image.width, height: image.height)!
        if let canvasRect {
            guard EditorCanvasExtent.isValid(canvasRect), canvasRect.contains(EditorCrop.fullRect(size)),
                  crop.map({ EditorCrop.isValid($0, in: canvasRect) }) ?? true else { throw ExportError.render }
            return try renderExpanded(image: image, objects: objects, area: crop ?? canvasRect, resizedSize: resizedSize, maxDimension: maxDimension)
        }
        let area = crop ?? EditorCrop.fullRect(size)
        guard EditorCrop.isValid(area, in: size) else { throw ExportError.render }
        if let resizedSize {
            guard EditorResize.isValid(resizedSize) else { throw ExportError.render }
            let factor = maxDimension.map { min(1, CGFloat($0) / CGFloat(max(resizedSize.width, resizedSize.height))) } ?? 1
            let width = max(1, Int((CGFloat(resizedSize.width) * factor).rounded()))
            let height = max(1, Int((CGFloat(resizedSize.height) * factor).rounded()))
            if CGFloat(width) == area.width && CGFloat(height) == area.height {
                return try renderUnbudgeted(image: image, objects: objects, crop: crop)
            }
            // Apply raster effects and opaque masks before sampling: secret source
            // pixels must not bleed into neighbouring pixels during downsampling.
            let rasterObjects = objects.filter { $0.kind == .blur || $0.kind == .redact }
            let base: CGImage
            if rasterObjects.isEmpty {
                guard let cut = image.cropping(to: area) else { throw ExportError.render }
                base = cut
            } else {
                base = try renderUnbudgeted(image: image, objects: rasterObjects, crop: crop)
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
            drawAnnotations(objects: objects, in: context, magnifierSource: try magnifierSourceUnbudgeted(image: image, objects: objects))
            guard let result = context.makeImage() else { throw ExportError.render }
            return result
        }
        if let crop {
            // Compose in original coordinates first. Translating vector paths before rasterizing
            // changes CoreGraphics edge antialiasing, even for integer pixel offsets.
            // Cutting the composed pixels also keeps blur sampling independent of the crop.
            let full = try renderUnbudgeted(image: image, objects: objects)
            guard let cut = full.cropping(to: crop) else { throw ExportError.render }
            if let maxDimension, max(cut.width, cut.height) > maxDimension {
                return try renderUnbudgeted(image: cut, objects: [], maxDimension: maxDimension)
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
        try draw(image: image, objects: objects, in: context)
        guard let rendered = context.makeImage() else { throw ExportError.render }
        return rendered
    }
    private static func renderExpanded(image: CGImage, objects: [EditorObject], area: CGRect,
                                       resizedSize: PixelSize?, maxDimension: Int?) throws -> CGImage {
        let output = resizedSize ?? PixelSize(width: Int(area.width), height: Int(area.height))!
        guard EditorResize.isValid(output), maxDimension.map({ $0 > 0 }) ?? true else { throw ExportError.render }
        let factor = maxDimension.map { min(1, CGFloat($0) / CGFloat(max(output.width, output.height))) } ?? 1
        let width = max(1, Int((CGFloat(output.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(output.height) * factor).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExportError.render }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / area.width, y: -CGFloat(height) / area.height)
        context.translateBy(x: -area.minX, y: -area.minY); context.clip(to: area)
        if CGFloat(width) == area.width && CGFloat(height) == area.height {
            context.interpolationQuality = .none
            try draw(image: image, objects: objects, in: context)
        } else {
            // Resolve crop, blur and opaque masks before sampling; vector/text ink stays at destination resolution.
            let raster = objects.filter { $0.kind == .blur || $0.kind == .redact }
            let base = try renderExpanded(image: image, objects: raster, area: area, resizedSize: nil, maxDimension: nil)
            context.interpolationQuality = .high
            context.saveGState(); context.translateBy(x: area.minX, y: area.minY)
            drawBase(image: base, in: context); context.restoreGState()
            drawAnnotations(objects: objects, in: context, magnifierSource: try magnifierSourceUnbudgeted(image: image, objects: objects))
        }
        guard let result = context.makeImage() else { throw ExportError.render }
        return result
    }
    static func thumbnail(image: CGImage, objects: [EditorObject], crop: CGRect? = nil, resizedSize: PixelSize? = nil, canvasRect: CGRect? = nil, transform: EditorImageTransform = .identity, presentation: EditorPresentation? = nil) throws -> Data {
        try encodedPNG(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: 420, canvasRect: canvasRect, transform: transform, presentation: presentation)
    }
    static func png(image: CGImage, objects: [EditorObject], crop: CGRect? = nil, resizedSize: PixelSize? = nil, canvasRect: CGRect? = nil, transform: EditorImageTransform = .identity, presentation: EditorPresentation? = nil) throws -> Data {
        try encodedPNG(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: nil, canvasRect: canvasRect, transform: transform, presentation: presentation)
    }
    private static func encodedPNG(image: CGImage, objects: [EditorObject], crop: CGRect?, resizedSize: PixelSize?, maxDimension: Int?, canvasRect: CGRect?, transform: EditorImageTransform, presentation: EditorPresentation?) throws -> Data {
        let requested = rasterBytes(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: maxDimension,
                                    canvasRect: canvasRect, transform: transform, presentation: presentation, encoding: true)
        return try withRasterReservation(requested) {
            let rendered = try renderUnbudgeted(image: image, objects: objects, crop: crop, resizedSize: resizedSize, maxDimension: maxDimension,
                                              canvasRect: canvasRect, transform: transform, presentation: presentation)
            try Task.checkCancellation()
            guard let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { throw ExportError.render }
            try Task.checkCancellation()
            return data
        }
    }
    static func presented(_ image: CGImage, by presentation: EditorPresentation, backgroundOverride: PresentationBackground? = nil, effectScale: CGFloat = 1) throws -> CGImage {
        let requested = rasterBytes(image: image, objects: [], crop: nil, resizedSize: nil, maxDimension: nil,
                                    canvasRect: nil, transform: .identity, presentation: presentation, encoding: false)
        return try withRasterReservation(requested) {
            try presentedUnbudgeted(image, by: presentation, backgroundOverride: backgroundOverride, effectScale: effectScale)
        }
    }
    private static func presentedUnbudgeted(_ image: CGImage, by presentation: EditorPresentation, backgroundOverride: PresentationBackground?, effectScale: CGFloat) throws -> CGImage {
        guard let geometry = presentation.geometry(for: PixelSize(width: image.width, height: image.height)!),
              let ctx = CGContext(data: nil, width: geometry.outputSize.width, height: geometry.outputSize.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExportError.render }
        ctx.translateBy(x: 0, y: CGFloat(geometry.outputSize.height)); ctx.scaleBy(x: 1, y: -1)
        try drawPresentationScene(image, sourceSize: CGSize(width: image.width, height: image.height), presentation: presentation,
                                  in: ctx, backgroundOverride: backgroundOverride, effectScale: effectScale)
        guard let output = ctx.makeImage() else { throw ExportError.render }
        return output
    }
    /// Top-left pixel coordinates, shared by the interactive scene and exported bitmap.
    static func drawPresentationScene(_ image: CGImage?, sourceSize: CGSize, presentation: EditorPresentation,
                                      in ctx: CGContext, preparedWallpaper: CGImage? = nil, usesPreparedWallpaper: Bool = false,
                                      backgroundOverride: PresentationBackground? = nil, effectScale: CGFloat = 1) throws {
        guard let source = PixelSize(width: Int(sourceSize.width), height: Int(sourceSize.height)),
              let geometry = presentation.geometry(for: source) else { throw ExportError.render }
        let canvas = CGRect(x: 0, y: 0, width: geometry.outputSize.width, height: geometry.outputSize.height)
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.clip(to: canvas)
        if let background = backgroundOverride ?? presentation.background {
            ctx.saveGState(); ctx.translateBy(x: 0, y: canvas.height); ctx.scaleBy(x: 1, y: -1)
            switch background {
            case .asset where usesPreparedWallpaper, .image where usesPreparedWallpaper:
                if let preparedWallpaper { drawCover(preparedWallpaper, in: ctx, canvas: canvas) }
            default: try drawPresentationBackground(background, in: ctx, canvas: canvas)
            }
            ctx.restoreGState()
        }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.concatenate(geometry.imageTransform)
        let rect = CGRect(origin: .zero, size: sourceSize)
        let radius = min(presentation.cornerRadius, min(rect.width, rect.height) / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if presentation.shadowStrength > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -6 * effectScale), blur: 18 * effectScale, color: CGColor(gray: 0, alpha: presentation.shadowStrength))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.addPath(path); ctx.fillPath(); ctx.restoreGState()
        }
        ctx.interpolationQuality = presentation.rotationDegrees == 0 ? .none : .high
        if let image { drawFramedImage(image, in: ctx, rect: rect, radius: radius, border: presentation.border) }
    }
    static func drawFramedImage(_ image: CGImage, in ctx: CGContext, rect: CGRect, radius: CGFloat, border: EditorImageBorder?) {
        drawFramedContent(in: ctx, rect: rect, radius: radius, border: border) {
            drawBase(image: image, in: ctx, size: rect.size)
        }
    }
    /// Share the final composition mask and inset border with the editable canvas.
    static func drawFramedContent(in ctx: CGContext, rect: CGRect, radius: CGFloat, border: EditorImageBorder?, draw: () -> Void) {
        let radius = max(0, min(radius, min(rect.width, rect.height) / 2))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
        draw()
        ctx.restoreGState()
        if let border {
            let width = min(border.width, min(rect.width, rect.height))
            let inset = rect.insetBy(dx: width / 2, dy: width / 2), corner = max(0, radius - width / 2)
            ctx.saveGState(); ctx.setStrokeColor(NSColor(srgbRed: border.color.red, green: border.color.green, blue: border.color.blue, alpha: 1).cgColor)
            ctx.setLineWidth(width); ctx.addPath(CGPath(roundedRect: inset, cornerWidth: corner, cornerHeight: corner, transform: nil)); ctx.strokePath(); ctx.restoreGState()
        }
    }
    static func drawPresentationBackground(_ background: PresentationBackground, in ctx: CGContext, canvas: CGRect) throws {
        switch background {
        case .solid(let color):
            ctx.setFillColor(NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).cgColor); ctx.fill(canvas)
        case .gradient(let gradient):
            let colors = gradient.colors.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1).cgColor } as CFArray
            guard let gradientRef = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil) else { throw ExportError.render }
            let angle = gradient.angle * .pi / 180, length = hypot(canvas.width, canvas.height) / 2
            ctx.drawLinearGradient(gradientRef, start: CGPoint(x: canvas.midX - cos(angle) * length, y: canvas.midY - sin(angle) * length),
                                   end: CGPoint(x: canvas.midX + cos(angle) * length, y: canvas.midY + sin(angle) * length), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .asset, .image:
            if let image = try preparePresentationWallpaper(background) { drawCover(image, in: ctx, canvas: canvas) }
        }
    }
    static func preparePresentationWallpaper(_ background: PresentationBackground?) throws -> CGImage? {
        let data: Data, blur: Double
        switch background {
        case .asset(let asset, let value):
            guard asset.isValid else { throw ExportError.render }; data = asset.png; blur = value
        case .image(let path, let value): data = try ProjectArchive.readRegularFile(URL(fileURLWithPath: path), limit: 100_000_000); blur = value
        default: return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8000, height <= 8000, Int64(width) * Int64(height) <= 64_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ExportError.render }
        try Task.checkCancellation()
        if blur > 0 {
            let ci = CIImage(cgImage: image), extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let blurred = ci.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: min(40, blur)]).cropped(to: extent)
            guard let output = CIContext().createCGImage(blurred, from: extent) else { throw ExportError.render }
            return output
        }
        return image
    }
    static func drawCover(_ image: CGImage, in ctx: CGContext, canvas: CGRect) {
        let scale = max(canvas.width / CGFloat(image.width), canvas.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        ctx.draw(image, in: CGRect(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2, width: size.width, height: size.height))
    }
    static func transformed(_ image: CGImage, by transform: EditorImageTransform) throws -> CGImage {
        guard transform != .identity else { return image }
        let size = transform.applying(to: PixelSize(width: image.width, height: image.height)!)
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExportError.render }
        context.interpolationQuality = .none
        context.translateBy(x: 0, y: CGFloat(size.height)); context.scaleBy(x: 1, y: -1)
        context.concatenate(transform.affineTransform(size: CGSize(width: image.width, height: image.height)))
        drawBase(image: image, in: context)
        guard let result = context.makeImage() else { throw ExportError.render }
        return result
    }
    enum ExportError: LocalizedError {
        case render
        case memoryBudget
        var errorDescription: String? {
            switch self {
            case .render: String(localized: "Das Bild konnte nicht gerendert werden.")
            case .memoryBudget: String(localized: "Die Bildverarbeitung würde zu viel Arbeitsspeicher benötigen. Warte auf laufende Bildverarbeitungen oder wähle eine kleinere Ausgabegröße.")
            }
        }
    }
}

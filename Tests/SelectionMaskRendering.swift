import AppKit

/// Native material views need the window-server compositor and cannot participate
/// in an offscreen cacheDisplay bitmap. Rasterize the actual desktop/chrome draw
/// methods without the control surface; its material is checked in the native UI.
@MainActor
func renderSelectionMask(_ view: SelectionView) -> NSBitmapImageRep {
    let scale = view.window?.backingScaleFactor ?? 1
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
        pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)
    view.draw(view.bounds)
    for child in view.subviews where !(child is CaptureReviewToolbar) && !child.isHidden {
        context.saveGState()
        context.translateBy(x: child.frame.minX, y: child.frame.minY)
        context.setAlpha(child.alphaValue)
        child.draw(child.bounds)
        context.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

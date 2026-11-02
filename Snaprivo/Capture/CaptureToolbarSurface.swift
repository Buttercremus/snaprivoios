import AppKit

/// Keeps the selection visible until its windows belong to a live capture.
/// Taking the panels transfers ownership without ordering them out or closing them.
@MainActor
final class CaptureSelectionOverlay {
    private var panels: [NSPanel]
    static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    static let controlsLevel = NSWindow.Level(rawValue: level.rawValue + 1)

    init(panels: [NSPanel]) { self.panels = panels }
    func takePanels() -> [NSPanel] {
        defer { panels.removeAll() }
        return panels
    }
    func close() { takePanels().forEach { $0.orderOut(nil); $0.close() } }
}

/// Shared compact metrics and one subdued backdrop for the review, scroll and
/// recording bars. The separate preparation window retains its glass variant.
@MainActor
class CaptureToolbarSurface: NSView {
    static let barHeight: CGFloat = 56
    static let controlHeight: CGFloat = 36
    static let accent = NSColor(srgbRed: 0, green: 0.6, blue: 1, alpha: 1)
    let controls = NSView()
    private var subduedBackdrop: NSVisualEffectView?
    private var optionalGlass: NSGlassEffectView?
    override convenience init(frame: NSRect) { self.init(frame: frame, subdued: false) }
    init(frame: NSRect, subdued: Bool) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        controls.frame = bounds; controls.autoresizingMask = [.width, .height]
        if subdued {
            let backdrop = NSVisualEffectView(frame: bounds)
            subduedBackdrop = backdrop
            backdrop.autoresizingMask = [.width, .height]
            backdrop.material = .hudWindow; backdrop.blendingMode = .withinWindow; backdrop.state = .active
            backdrop.wantsLayer = true; backdrop.layer?.cornerRadius = 18; backdrop.layer?.masksToBounds = true
            let tint = NSView(frame: bounds)
            tint.autoresizingMask = [.width, .height]; tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.135, blue: 0.19, alpha: 0.96).cgColor
            backdrop.addSubview(tint)
            addSubview(backdrop); addSubview(controls)
        } else {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular; glass.cornerRadius = min(28, frame.height / 2)
            glass.contentView = controls
            addSubview(glass)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The selection keeps its native control container when changing photo/video mode.
    func setGlassPresentation(_ enabled: Bool) {
        guard let subduedBackdrop else { return }
        if enabled && optionalGlass == nil {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]; glass.style = .regular; glass.cornerRadius = 28
            // A dark native tint separates controls from bright text behind the selection.
            glass.tintColor = NSColor(white: 0.06, alpha: 0.7)
            glass.contentView = NSView(frame: bounds)
            addSubview(glass, positioned: .below, relativeTo: controls); optionalGlass = glass
        }
        subduedBackdrop.isHidden = enabled; optionalGlass?.isHidden = !enabled
    }

    static func style(_ button: NSButton, prominent: Bool = false) {
        button.bezelStyle = .glass; button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.imageHugsTitle = true
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        button.bezelColor = prominent ? .controlAccentColor : nil
    }

    static func styleFlat(_ button: CaptureFlatButton, prominent: Bool = false) {
        button.font = .systemFont(ofSize: 13, weight: prominent ? .semibold : .medium)
        button.flatCell.foreground = .white
        button.flatCell.fill = prominent ? accent : nil
        button.flatCell.iconSize = 20
    }
    static func divider(frame: NSRect = .zero) -> NSView {
        let view = NSView(frame: frame); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        return view
    }
}

/// Native button tracking, actions, keyboard and accessibility with the flat
/// icon/text treatment of the capture reference, rather than a glass bezel.
@MainActor
final class CaptureFlatButton: NSButton {
    private var hoverTracking: NSTrackingArea?
    var flatCell: CaptureFlatButtonCell { cell as! CaptureFlatButtonCell }
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = CaptureFlatButtonCell(textCell: "")
        setButtonType(.momentaryPushIn); isBordered = false
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { flatCell.isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { flatCell.isHovered = false; needsDisplay = true }
}

@MainActor
final class CaptureFlatButtonCell: NSButtonCell {
    var isHovered = false
    var showsChevron = false
    var fill: NSColor?
    var foreground = NSColor.white.withAlphaComponent(0.82)
    var iconSize: CGFloat = 24
    var symbolWeight: NSFont.Weight = .regular
    var contentScale: CGFloat = 1
    var cornerRadius: CGFloat = 16

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: cornerRadius * contentScale, yRadius: cornerRadius * contentScale)
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if let fill {
            let resolved = increasedContrast ? (fill.blended(withFraction: 0.35, of: .black) ?? fill) : fill
            resolved.setFill(); path.fill()
        }
        if increasedContrast {
            NSColor.white.withAlphaComponent(isEnabled ? 0.85 : 0.5).setStroke()
            path.lineWidth = 1; path.stroke()
        }
        if isEnabled && (isHovered || isHighlighted) {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.16 : 0.07).setFill(); path.fill()
        }
        let color = foreground.withAlphaComponent(isEnabled ? (increasedContrast ? 1 : foreground.alphaComponent) : (increasedContrast ? 0.6 : 0.4))
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 16), .foregroundColor: color]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let side = iconSize * contentScale, gap = 7 * contentScale
        let arrowWidth: CGFloat = showsChevron ? 9 * contentScale : 0
        let width = (image == nil ? 0 : side) + (title.isEmpty ? 0 : textSize.width)
            + (image != nil && !title.isEmpty ? gap : 0) + (showsChevron ? gap + arrowWidth : 0)
        var x = cellFrame.midX - width / 2
        if let image {
            drawSymbol(image, in: NSRect(x: x, y: cellFrame.midY - side / 2, width: side, height: side), color: color)
            x += side + (title.isEmpty ? 0 : gap)
        }
        if !title.isEmpty {
            (title as NSString).draw(in: NSRect(x: x, y: cellFrame.midY - textSize.height / 2, width: textSize.width, height: textSize.height), withAttributes: attributes)
            x += textSize.width
        }
        if showsChevron, let arrow = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            drawSymbol(arrow, in: NSRect(x: x + gap, y: cellFrame.midY - arrowWidth / 2, width: arrowWidth, height: arrowWidth), color: color)
        }
        if showsFirstResponder {
            NSGraphicsContext.saveGraphicsState(); NSFocusRingPlacement.only.set(); path.fill(); NSGraphicsContext.restoreGraphicsState()
        }
    }
    private func drawSymbol(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: iconSize * contentScale, weight: symbolWeight)
            .applying(.preferringMonochrome())
        let symbol = image.withSymbolConfiguration(configuration) ?? image
        let size = symbol.size
        guard size.width > 0, size.height > 0 else { return }
        let ratio = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSRect(x: rect.midX - size.width * ratio / 2, y: rect.midY - size.height * ratio / 2,
                            width: size.width * ratio, height: size.height * ratio)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // Tint only the monochrome contour. A palette can introduce a filled
        // secondary screen layer in SF Symbols such as "display".
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        symbol.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.setBlendMode(.sourceIn); context.setFillColor(color.cgColor); context.fill(fitted)
        context.endTransparencyLayer(); context.restoreGState()
    }
}


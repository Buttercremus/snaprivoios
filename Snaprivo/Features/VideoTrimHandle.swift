import AppKit
import SwiftUI

enum VideoTrimEdge { case start, end }

struct VideoTrimHandle: NSViewRepresentable {
    let model: VideoEditorModel
    let edge: VideoTrimEdge
    let timelineWidth: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> VideoTrimHandleView {
        VideoTrimHandleView(model: model, edge: edge)
    }
    func updateNSView(_ view: VideoTrimHandleView, context: Context) {
        view.timelineWidth = timelineWidth
        view.isEnabled = isEnabled
        // Read both observed boundaries so drawing and accessibility follow every edit.
        view.refresh(value: edge == .start ? model.start : model.end)
    }
}

/// AppKit keeps delivering drag events to the view that received mouseDown,
/// even while SwiftUI moves that view to follow the edited boundary.
@MainActor final class VideoTrimHandleView: NSView {
    private let model: VideoEditorModel
    private let edge: VideoTrimEdge
    var timelineWidth: CGFloat = 0
    var isEnabled = true {
        didSet {
            if !isEnabled { drag = nil }
            setAccessibilityEnabled(isEnabled)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private struct Drag {
        let pointerX: CGFloat
        let value: Double
        let secondsPerPoint: Double
    }
    private var drag: Drag?
    private var canEdit: Bool { isEnabled && !model.isBusy && model.hasProAccess() }
    private var value: Double { edge == .start ? model.start : model.end }
    private var gripRect: NSRect { NSRect(x: bounds.midX - 6, y: bounds.midY - 24, width: 12, height: 48) }

    init(model: VideoEditorModel, edge: VideoTrimEdge) {
        self.model = model; self.edge = edge
        super.init(frame: .zero)
        focusRingType = .exterior
        setAccessibilityElement(true); setAccessibilityRole(.slider)
        setAccessibilityLabel(edge == .start ? String(localized: "Trimmbeginn") : String(localized: "Trimmende"))
        setAccessibilityIdentifier(edge == .start ? "video.editor.handle.start" : "video.editor.handle.end")
        setAccessibilityHelp(String(localized: "Pfeiltasten ändern um 0,1 Sekunden, mit Umschalt um 1 Sekunde."))
        refresh(value: value)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { canEdit }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resignFirstResponder() -> Bool {
        drag = nil
        return super.resignFirstResponder()
    }
    override var focusRingMaskBounds: NSRect { gripRect }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: gripRect, xRadius: 4, yRadius: 4).fill() }
    override func resetCursorRects() {
        if canEdit { addCursorRect(bounds, cursor: .resizeLeftRight) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(canEdit ? 1 : 0.5).setFill()
        NSBezierPath(roundedRect: gripRect, xRadius: 4, yRadius: 4).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 1, y: bounds.midY - 10, width: 2, height: 20), xRadius: 1, yRadius: 1).fill()
    }
    func refresh(value: Double) {
        setAccessibilityValue(NSNumber(value: value))
        setAccessibilityValueDescription(VideoTimeText.clock(value))
        setAccessibilityMinValue(NSNumber(value: 0)); setAccessibilityMaxValue(NSNumber(value: model.duration))
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        drag = nil
        guard canEdit, timelineWidth.isFinite, timelineWidth > 0, model.duration.isFinite, model.duration > 0 else { return }
        window?.makeFirstResponder(self)
        // Window coordinates and a frozen scale preserve the grab offset while
        // the handle's own frame changes. The first click never jumps the cut.
        drag = Drag(pointerX: event.locationInWindow.x, value: value, secondsPerPoint: model.duration / Double(timelineWidth))
        model.scrub(to: edge == .start ? value : max(model.start, value - min(1.0 / 30, model.duration)))
    }
    override func mouseDragged(with event: NSEvent) { move(with: event) }
    override func mouseUp(with event: NSEvent) {
        move(with: event)
        drag = nil
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { drag = nil }
    }
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 123 || event.keyCode == 124 else { super.keyDown(with: event); return }
        guard canEdit else { return }
        drag = nil
        adjust(by: (event.keyCode == 123 ? -1 : 1) * (event.modifierFlags.contains(.shift) ? 1 : 0.1))
    }
    override func accessibilityPerformIncrement() -> Bool { adjust(by: 0.1) }
    override func accessibilityPerformDecrement() -> Bool { adjust(by: -0.1) }

    private func move(with event: NSEvent) {
        guard canEdit, let drag, event.locationInWindow.x.isFinite else { self.drag = nil; return }
        setValue(drag.value + Double(event.locationInWindow.x - drag.pointerX) * drag.secondsPerPoint)
    }
    @discardableResult private func adjust(by amount: Double) -> Bool {
        guard canEdit else { return false }
        setValue(value + amount)
        return true
    }
    private func setValue(_ seconds: Double) {
        if edge == .start { model.moveStart(to: seconds) } else { model.moveEnd(to: seconds) }
        refresh(value: value)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
}

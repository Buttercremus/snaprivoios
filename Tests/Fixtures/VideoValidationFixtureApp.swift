import AppKit

/// Silent visual source only. No capture APIs, audio devices or user files.
@MainActor final class VideoValidationFixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var timer: Timer?
    private let signal = VideoValidationSignalView()
    private var narrow = false
    private var originalPosition: CGPoint?
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: CGRect(x: 40, y: 240, width: 960, height: 512),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Snaprivo V04 – stumme Testquelle"
        window.isReleasedWhenClosed = false
        signal.frame = CGRect(x: 0, y: 0, width: 960, height: 512)
        signal.autoresizingMask = [.width, .height]
        window.contentView = signal
        let resize = NSButton(title: "Größe ändern", target: self, action: #selector(resizeSource))
        resize.frame = CGRect(x: 20, y: 466, width: 150, height: 30); resize.autoresizingMask = [.minYMargin]
        resize.bezelStyle = .rounded; resize.setAccessibilityIdentifier("v04.source.resize"); signal.addSubview(resize)
        let reset = NSButton(title: "Zähler zurücksetzen", target: self, action: #selector(resetSource))
        reset.frame = CGRect(x: 185, y: 466, width: 190, height: 30); reset.autoresizingMask = [.minYMargin]
        reset.bezelStyle = .rounded; reset.setAccessibilityIdentifier("v04.source.reset"); signal.addSubview(reset)
        let move = NSButton(title: "Verschieben", target: self, action: #selector(moveSource))
        move.frame = CGRect(x: 390, y: 466, width: 150, height: 30); move.autoresizingMask = [.minYMargin]
        move.bezelStyle = .rounded; move.setAccessibilityIdentifier("v04.source.move"); signal.addSubview(move)
        let minimize = NSButton(title: "2 s minimieren", target: self, action: #selector(minimizeSource))
        minimize.frame = CGRect(x: 555, y: 466, width: 160, height: 30); minimize.autoresizingMask = [.minYMargin]
        minimize.bezelStyle = .rounded; minimize.setAccessibilityIdentifier("v04.source.minimize"); signal.addSubview(minimize)
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.signal.needsDisplay = true; self?.signal.displayIfNeeded() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func resizeSource() {
        narrow.toggle(); window.setContentSize(narrow ? NSSize(width: 560, height: 680) : NSSize(width: 960, height: 512))
    }
    @objc private func resetSource() { signal.origin = ProcessInfo.processInfo.systemUptime; signal.needsDisplay = true }
    @objc private func moveSource() {
        if let originalPosition { window.setFrameOrigin(originalPosition); self.originalPosition = nil }
        else {
            originalPosition = window.frame.origin
            let area = window.screen?.visibleFrame ?? window.frame
            window.setFrameOrigin(CGPoint(x: min(window.frame.minX + 60, area.maxX - window.frame.width), y: min(window.frame.minY + 40, area.maxY - window.frame.height)))
        }
    }
    @objc private func minimizeSource() {
        window.miniaturize(nil)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2)); self?.window.deminiaturize(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}

@MainActor final class VideoValidationSignalView: NSView {
    var origin = ProcessInfo.processInfo.systemUptime
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let seconds = ProcessInfo.processInfo.systemUptime - origin, tick = Int(seconds * 60)
        NSColor(calibratedWhite: 0.12 + Double(tick % 60) / 180, alpha: 1).setFill(); bounds.fill()
        let size = min(bounds.width, bounds.height) * 0.18
        let x = 20 + (bounds.width - size - 40) * (sin(seconds * 1.8) + 1) / 2
        NSColor.systemOrange.setFill(); CGRect(x: x, y: bounds.midY - size / 2, width: size, height: size).fill()
        for (index, color) in [NSColor.systemRed, .systemGreen, .systemBlue, .white].enumerated() {
            color.setFill()
            let right = index % 2 == 1, top = index >= 2
            CGRect(x: right ? bounds.maxX - 14 : 2, y: top ? bounds.maxY - 14 : 2, width: 12, height: 12).fill()
        }
        let text = String(format: "STUMME V04-TESTQUELLE\n%02d:%02d:%02d · Bildzähler %d\n60 Zeichenupdates/s · Aufnahmeziel 30 fps · Kein Ton", Int(seconds) / 3600, Int(seconds) / 60 % 60, Int(seconds) % 60, tick)
        text.draw(at: CGPoint(x: 30, y: 35), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium), .foregroundColor: NSColor.white])
    }
}

@main struct VideoValidationFixtureApp {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = VideoValidationFixtureDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

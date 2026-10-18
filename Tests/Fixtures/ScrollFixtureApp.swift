import AppKit

/// Standalone synthetic source for the real ScreenCaptureKit end-to-end test.
/// It requests no permissions, reads no user files and creates no screenshots.
@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let scroll = NSScrollView()
    private let status = NSTextField(labelWithString: "Position: 0 pt")
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 740),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Snaprivo Scroll Fixture – synthetische Daten"
        // Stay visible while the capture controller has focus; only this test app floats.
        window.level = .floating
        window.isReleasedWhenClosed = false
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 740))
        window.contentView = root
        scroll.frame = CGRect(x: 20, y: 20, width: 680, height: 700)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false
        scroll.documentView = FixturePage(frame: CGRect(x: 0, y: 0, width: 660, height: 6000))
        root.addSubview(scroll)
        let title = NSTextField(wrappingLabelWithString: "Synthetischer T01-Test\n\nNur den Inhalt links auswählen. Die Knöpfe lösen reproduzierbare manuelle Scroll-Schritte aus.")
        title.frame = CGRect(x: 720, y: 500, width: 160, height: 200); root.addSubview(title)
        let advance = NSButton(title: "120 pt nach unten", target: self, action: #selector(nextSection))
        advance.frame = CGRect(x: 720, y: 430, width: 160, height: 36)
        advance.bezelStyle = .rounded; advance.setAccessibilityIdentifier("fixture.next"); root.addSubview(advance)
        let reset = NSButton(title: "Zum Anfang", target: self, action: #selector(resetPosition))
        reset.frame = CGRect(x: 720, y: 380, width: 160, height: 36); reset.bezelStyle = .rounded; root.addSubview(reset)
        status.frame = CGRect(x: 720, y: 330, width: 160, height: 32); root.addSubview(status)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func nextSection() { move(to: scroll.contentView.bounds.minY + 120) }
    @objc private func resetPosition() { move(to: 0) }
    private func move(to y: CGFloat) {
        scroll.contentView.scroll(to: CGPoint(x: 0, y: min(5300, max(0, y))))
        scroll.reflectScrolledClipView(scroll.contentView)
        status.stringValue = "Position: \(Int(scroll.contentView.bounds.minY)) pt"
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor final class FixturePage: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        for row in 0..<50 {
            let rect = CGRect(x: 0, y: row * 120, width: 660, height: 120)
            guard rect.intersects(dirtyRect) else { continue }
            NSColor(calibratedHue: CGFloat((row * 71 + 33) % 360) / 360, saturation: 0.16, brightness: 0.98, alpha: 1).setFill(); rect.fill()
            let title = "Abschnitt \(row + 1) · Kennung \(row * 7919 + 2311)"
            title.draw(at: CGPoint(x: 20, y: row * 120 + 12), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.black])
            let text = "Nur synthetische Daten für Aufnahme, Editor und Autosave."
            text.draw(at: CGPoint(x: 20, y: row * 120 + 47), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
            for column in 0..<9 {
                NSColor(calibratedHue: CGFloat((row * 97 + column * 43) % 360) / 360, saturation: 0.8, brightness: 0.65, alpha: 1).setFill()
                CGRect(x: 20 + column * 66, y: row * 120 + 80, width: 15 + (row * 17 + column * 7) % 45, height: 16).fill()
            }
            NSColor.darkGray.setFill(); CGRect(x: 0, y: row * 120 + 118, width: 660, height: 2).fill()
        }
    }
}

@main struct FixtureApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = FixtureDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

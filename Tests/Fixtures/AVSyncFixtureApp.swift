import AppKit
import AVKit

/// Playback only: no capture, microphone access, user files or automation APIs.
@MainActor final class AVSyncFixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var player: AVPlayer!
    private var observer: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let media = Bundle.main.url(forResource: "AVSync", withExtension: "mp4")!
        player = AVPlayer(url: media)
        player.volume = 1
        window = NSWindow(contentRect: CGRect(x: 40, y: 100, width: 680, height: 440),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Snaprivo A/V-Synchronität – synthetische Testquelle"
        window.level = .floating; window.isReleasedWhenClosed = false
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 680, height: 440))
        let video = AVSyncSignalView(frame: CGRect(x: 20, y: 20, width: 640, height: 360))
        video.setAccessibilityIdentifier("avsync.video")
        root.addSubview(video)
        let start = NSButton(title: "Testsignal starten (32 s)", target: self, action: #selector(startSignal))
        start.frame = CGRect(x: 20, y: 394, width: 250, height: 32); start.bezelStyle = .rounded
        start.setAccessibilityIdentifier("avsync.start"); root.addSubview(start)
        let pause = NSButton(title: "Pause", target: self, action: #selector(pauseSignal))
        pause.frame = CGRect(x: 285, y: 394, width: 100, height: 32); pause.bezelStyle = .rounded
        root.addSubview(pause)
        let info = NSTextField(labelWithString: "Bildblitz + 1-kHz-Ton alle 2 s")
        info.frame = CGRect(x: 400, y: 399, width: 260, height: 22); root.addSubview(info)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { time in
            Task { @MainActor in
                video.seconds = time.seconds
                video.needsDisplay = true
                video.displayIfNeeded()
            }
        }
        window.contentView = root
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func startSignal() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.player.play() }
        }
    }
    @objc private func pauseSignal() { player.pause() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor final class AVSyncSignalView: NSView {
    var seconds = 0.0
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let position = seconds.truncatingRemainder(dividingBy: 2)
        if position >= 0.5 && position < 0.7 {
            NSColor.white.setFill()
            CGRect(x: 160, y: 90, width: 320, height: 180).fill()
        }
        String(format: "SYNTHETIC A/V · %.3f s", seconds).draw(at: CGPoint(x: 20, y: 20),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.green])
    }
}

@main struct AVSyncFixtureApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AVSyncFixtureDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

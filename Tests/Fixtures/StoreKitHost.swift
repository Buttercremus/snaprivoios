import AppKit

/// Isolated StoreKit test host. It never opens the user's Snaprivo data or captures a screen.
@main struct StoreKitHost {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Snaprivo · Local StoreKit Tests"
        window.contentView = NSTextField(labelWithString: "Synthetic StoreKit test. No real purchase.")
        window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        app.run()
    }
}

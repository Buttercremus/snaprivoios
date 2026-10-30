import AppKit
import SwiftUI
import Observation
import SnagForgeDomain

@MainActor @Observable private final class ToolbarState {
    var tool: AnnotationTool = .crop
    var selections = 0
}

private struct ToolbarFixture: View {
    let state: ToolbarState
    let size: EditorToolbarSize
    let tools: [AnnotationTool]
    let actions: [EditorToolbarAction]
    var body: some View {
        EditorAdaptiveToolPalette(selection: Binding(get: { state.tool }, set: { state.tool = $0 }),
            size: size, order: tools, actions: actions, hasPro: true,
            onSelect: { state.selections += 1 }) { action in
                Button {} label: {
                    EditorToolbarLabel(title: action.title, symbol: action.symbol, size: size,
                        extraWidth: action == .insertImage ? 18 : 0)
                }.accessibilityIdentifier("accessory.\(action.id)")
            } overflowAction: { action in
                Button(action.title, systemImage: action.symbol) {}
            }
            .buttonStyle(EditorToolbarButtonStyle())
            .padding(8)
            .background(.background)
    }
}

@main struct EditorToolbarChecks {
    @MainActor static func containsScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains { containsScrollView($0) }
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let state = ToolbarState(), tools = EditorToolItem.all.map(\.tool)
        let actions: [EditorToolbarAction] = [.colorPicker, .insertImage]
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 80),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Snaprivo · Synthetic Toolbar Checks"
        window.orderFront(nil)
        defer { window.close() }
        if CommandLine.arguments.contains("--interactive") {
            let host = NSHostingView(rootView: ToolbarFixture(state: state, size: .standard, tools: tools, actions: actions))
            window.contentView = host; window.setContentSize(CGSize(width: 800, height: 80))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            NSApp.run(); return
        }
        for size in EditorToolbarSize.allCases {
            let host = NSHostingView(rootView: ToolbarFixture(state: state, size: size, tools: tools, actions: actions))
            window.contentView = host
            for width: CGFloat in [1400, 960, 640, 400, 160, 400, 640, 960, 1400] {
                window.setContentSize(CGSize(width: width, height: size.buttonHeight + 16))
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
                host.layoutSubtreeIfNeeded()
                precondition(!containsScrollView(host), "Toolbar contains a scroll view")
                let layout = EditorToolOverflowLayout(width: width - 16, tools: tools, actions: actions, size: size)
                precondition(abs(host.bounds.width - width) < 0.1)
                if width == 1400 {
                    precondition(!layout.hasOverflow && layout.visibleToolCount == tools.count && layout.visibleActionCount == actions.count)
                } else if width == 640 {
                    let expected = size == .compact ? 11 : size == .standard ? 9 : 7
                    precondition(layout.hasOverflow && layout.visibleToolCount == expected && layout.visibleActionCount == 0)
                } else if width == 160 {
                    precondition(layout.hasOverflow && layout.visibleToolCount == (size == .large ? 0 : 1))
                }
                if width == 640 && size == .standard,
                   let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Toolbar-\(Locale.current.language.languageCode?.identifier ?? "unknown").png")
                    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
                }
            }
        }
        // A short customized toolbar must stay fully visible at its exact fit.
        let custom: [AnnotationTool] = [.pen, .selection, .magnifier]
        let exact = EditorToolbarLabel.requiredWidth(title: String(localized: "Stift"), size: .standard) +
            EditorToolbarLabel.requiredWidth(title: String(localized: "Auswahl"), size: .standard) +
            EditorToolbarLabel.requiredWidth(title: String(localized: "Lupe"), size: .standard)
        let fitting = EditorToolOverflowLayout(width: exact, tools: custom, actions: [], size: .standard)
        precondition(fitting.visibleToolCount == custom.count && !fitting.hasOverflow)
        let narrow = EditorToolOverflowLayout(width: exact - 1, tools: custom, actions: [], size: .standard)
        precondition(narrow.visibleToolCount == 1 && narrow.hasOverflow)
        print("Toolbar checks passed: native rendering/resizing, no scroller, expected narrow/wide/re-expanded allocations, exact-fit boundary, customized tools and three sizes.")
    }
}

import SwiftUI
import AppKit
import SnagForgeDomain

struct EditorToolPalette: View {
    @Binding var selection: AnnotationTool
    var size: EditorToolbarSize = .standard
    var showsBackground = true
    var order: [AnnotationTool] = EditorToolItem.all.map(\.tool)
    let onSelect: () -> Void

    @ViewBuilder
    var body: some View {
        if showsBackground {
            tools.padding(5).glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            tools
        }
    }

    private var tools: some View {
        HStack(spacing: 0) {
            ForEach(order, id: \.rawValue) { tool in
                if let item = EditorToolItem.all.first(where: { $0.tool == tool }) {
                    EditorToolButton(item: item, size: size, isSelected: selection == item.tool) {
                        selection = item.tool
                        onSelect()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Editorwerkzeuge"))
    }
}


private struct EditorToolButton: View {
    let item: EditorToolItem
    let size: EditorToolbarSize
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EditorToolbarLabel(title: item.title, symbol: item.symbol, size: size,
                               extraWidth: item.tool == .crop ? 18 : 0, isSelected: isSelected)
        }
        .buttonStyle(EditorToolbarButtonStyle(isSelected: isSelected))
        .help(item.hint)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.hint)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("editor.tool.\(item.id)")
    }
}

/// Tools and document actions share a single visual language and hit area.
struct EditorToolbarLabel: View {
    let title: String
    let symbol: String
    let size: EditorToolbarSize
    var extraWidth: CGFloat = 0
    var isSelected = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: size.iconSize, weight: isSelected ? .semibold : .regular))
                .frame(height: size.iconSize + 3)
            Text(title).font(.system(size: size.labelSize, weight: isSelected ? .medium : .regular))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: size.buttonWidth + extraWidth)
        .frame(height: size.buttonHeight)
        .contentShape(.rect(cornerRadius: 8))
    }
}

struct EditorToolbarButtonStyle: ButtonStyle {
    var isSelected = false
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(isSelected ? Color.accentColor.opacity(configuration.isPressed ? 0.24 : 0.16)
                        : Color.primary.opacity(configuration.isPressed ? 0.12 : isHovered && isEnabled ? 0.07 : 0),
                        in: .rect(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}

/// SwiftUI's macOS Menu flattens a custom toolbar label into a horizontal title.
/// A regular button preserves the shared icon-above-title layout and opens a native menu.
struct EditorOpenWithButton: View {
    let model: EditorModel
    let size: EditorToolbarSize
    @State private var presentation = EditorOpenWithMenuPresentation()

    var body: some View {
        Button { presentation.show(for: model) } label: {
            EditorToolbarLabel(title: String(localized: "Öffnen mit …"), symbol: "arrow.up.forward.app", size: size, extraWidth: 20)
        }
        .buttonStyle(EditorToolbarButtonStyle())
        .background(EditorOpenWithMenuAnchor(presentation: presentation).allowsHitTesting(false).accessibilityHidden(true))
        .disabled(!model.hasConfirmedImageForToolbar || model.isExportingPNG)
        .help(String(localized: "Bearbeitetes PNG in Vorschau oder einer anderen App öffnen"))
        .accessibilityLabel(String(localized: "Bild öffnen mit"))
        .accessibilityIdentifier("editor.openWith")
    }
}

@MainActor
private final class EditorOpenWithMenuPresentation: NSObject {
    weak var anchor: NSView?
    private var model: EditorModel?

    func show(for model: EditorModel) {
        guard let anchor, anchor.window != nil, self.model == nil,
              model.hasExportableImage, !model.isExportingPNG else { return }
        self.model = model
        defer { self.model = nil }
        let menu = NSMenu(title: String(localized: "Öffnen mit"))
        // Discover on each opening, so newly installed applications appear immediately.
        for app in EditorPNGApplication.available() {
            let item = NSMenuItem(title: app.name, action: #selector(openApplication(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = app.url
            let icon = NSWorkspace.shared.icon(forFile: app.url.path).copy() as? NSImage
            icon?.size = CGSize(width: 16, height: 16); item.image = icon
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: String(localized: "Andere App …"), action: #selector(chooseApplication(_:)), keyEquivalent: "")
        other.target = self; menu.addItem(other)
        menu.popUp(positioning: nil, at: CGPoint(x: anchor.bounds.minX, y: anchor.bounds.minY), in: anchor)
    }

    @objc private func openApplication(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        model?.openPNG(with: app)
    }
    @objc private func chooseApplication(_ sender: NSMenuItem) { model?.choosePNGApplication() }
}

private struct EditorOpenWithMenuAnchor: NSViewRepresentable {
    let presentation: EditorOpenWithMenuPresentation
    func makeCoordinator() -> EditorOpenWithMenuPresentation { presentation }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); view.setAccessibilityElement(false)
        presentation.anchor = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { presentation.anchor = view }
    static func dismantleNSView(_ view: NSView, coordinator: EditorOpenWithMenuPresentation) {
        if coordinator.anchor === view { coordinator.anchor = nil }
    }
}

#Preview("Werkzeuge · Pfeil") {
    EditorToolPalette(selection: .constant(.arrow), onSelect: {})
        .padding().frame(width: 720)
}

#Preview("Schmal · Unschärfe") {
    EditorToolPalette(selection: .constant(.blur), onSelect: {})
        .padding(8).frame(width: 488)
}

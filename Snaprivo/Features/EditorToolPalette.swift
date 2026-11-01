import SwiftUI
import AppKit
import SnagForgeDomain

struct EditorToolPalette: View {
    @Binding var selection: AnnotationTool
    var size: EditorToolbarSize = .standard
    var showsBackground = true
    var order: [AnnotationTool] = EditorToolItem.all.map(\.tool)
    var hasPro = true
    var toolsAreActive = true
    let onSelect: () -> Void
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    EditorToolButton(item: item, size: size, isSelected: toolsAreActive && selection.toolbarTool == item.tool, isProLocked: !hasPro && ProFeature.required(for: tool) != nil,
                                     selectionNamespace: selectionNamespace) {
                        if selection.toolbarTool != item.tool { selection = item.tool }
                        onSelect()
                    }
                    .overlay(alignment: .topTrailing) {
                        if !hasPro, ProFeature.required(for: tool) != nil {
                            Text("Pro").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tint)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        // Only the highlight glides, and only after a click; shortcuts switch immediately.
        .animation(EditorMotion.selection(reduceMotion: reduceMotion), value: toolsAreActive ? selection.toolbarTool : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Editorwerkzeuge"))
    }
}

/// Motion for editor chrome. Pointer actions animate; keyboard, VoiceOver and
/// programmatic changes stay immediate. The canvas never takes part.
@MainActor enum EditorMotion {
    static func panel(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion, isPointerEvent else { return nil }
        return .smooth(duration: 0.18, extraBounce: 0)
    }
    static func selection(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion, isPointerEvent else { return nil }
        return .spring(response: 0.24, dampingFraction: 1)
    }
    private static var isPointerEvent: Bool {
        guard let event = NSApp.currentEvent?.type else { return false }
        return event == .leftMouseDown || event == .leftMouseUp
    }
}


/// Uses the same label metrics as the buttons. No scroll position or delayed
/// measurement state is needed when the window changes size.
struct EditorToolOverflowLayout {
    let visibleToolCount: Int
    let visibleActionCount: Int
    let hasOverflow: Bool
    let contentWidth: CGFloat

    @MainActor init(width: CGFloat, tools: [AnnotationTool], actions: [EditorToolbarAction], size: EditorToolbarSize) {
        self.init(width: width, itemWidths: Self.itemWidths(tools: tools, actions: actions, size: size), toolCount: tools.count, moreWidth: Self.moreWidth(size: size))
    }
    @MainActor static func itemWidths(tools: [AnnotationTool], actions: [EditorToolbarAction], size: EditorToolbarSize) -> [CGFloat] {
        tools.compactMap { tool in
            EditorToolItem.all.first { $0.tool == tool }.map {
                EditorToolbarLabel.requiredWidth(title: $0.title, size: size, extraWidth: tool == .crop ? 18 : 0)
            }
        } + actions.map {
            EditorToolbarLabel.requiredWidth(title: $0.title, size: size, extraWidth: $0 == .insertImage ? 18 : 0)
        }
    }
    init(width: CGFloat, itemWidths widths: [CGFloat], toolCount: Int, moreWidth: CGFloat) {
        hasOverflow = widths.reduce(0, +) > max(0, width)
        let menuWidth = hasOverflow ? moreWidth + 4 : 0
        let budget = max(0, width - menuWidth)
        var used: CGFloat = 0, count = 0
        for item in widths {
            guard used + item <= budget else { break }
            used += item; count += 1
        }
        visibleToolCount = min(toolCount, count)
        visibleActionCount = max(0, count - toolCount)
        contentWidth = used + menuWidth
    }
    @MainActor static func moreWidth(size: EditorToolbarSize) -> CGFloat {
        max(size.buttonWidth, EditorToolbarLabel.requiredWidth(title: String(localized: "Mehr"), size: size) + 16)
    }
}

/// Give overflow tools their actual occupied width; spare space belongs after the image actions.
struct EditorToolbarGroupsLayout: Layout {
    let itemWidths: [CGFloat]
    let toolCount: Int
    let moreWidth: CGFloat
    let minimumToolWidth: CGFloat
    let height: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let actions = subviews[2].sizeThatFits(.unspecified)
        let minimum = minimumToolWidth + 11 + actions.width
        return CGSize(width: max(minimum, proposal.width ?? minimum), height: max(height, actions.height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let actions = subviews[2].sizeThatFits(.unspecified)
        let budget = max(0, bounds.width - actions.width - 11)
        let tools = EditorToolOverflowLayout(width: budget, itemWidths: itemWidths, toolCount: toolCount, moreWidth: moreWidth)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: tools.contentWidth, height: height))
        subviews[1].place(at: CGPoint(x: bounds.minX + tools.contentWidth + 4, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: 3, height: height))
        subviews[2].place(at: CGPoint(x: bounds.minX + tools.contentWidth + 11, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(actions))
    }
}

struct EditorAdaptiveToolPalette<Action: View, OverflowAction: View>: View {
    @Binding var selection: AnnotationTool
    let size: EditorToolbarSize
    let order: [AnnotationTool]
    let actions: [EditorToolbarAction]
    let hasPro: Bool
    var toolsAreActive = true
    var activeAction: EditorToolbarAction? = nil
    let onSelect: () -> Void
    @ViewBuilder let action: (EditorToolbarAction) -> Action
    @ViewBuilder let overflowAction: (EditorToolbarAction) -> OverflowAction

    var body: some View {
        GeometryReader { geometry in
            let layout = EditorToolOverflowLayout(width: geometry.size.width, tools: order, actions: actions, size: size)
            let hiddenTools = Array(order.dropFirst(layout.visibleToolCount))
            let hiddenActions = Array(actions.dropFirst(layout.visibleActionCount))
            let activeIsHidden = (toolsAreActive && hiddenTools.contains(selection.toolbarTool)) || activeAction.map(hiddenActions.contains) == true
            HStack(spacing: 0) {
                EditorToolPalette(selection: $selection, size: size, showsBackground: false,
                    order: Array(order.prefix(layout.visibleToolCount)), hasPro: hasPro, toolsAreActive: toolsAreActive, onSelect: onSelect)
                ForEach(Array(actions.prefix(layout.visibleActionCount))) { action($0) }
                if layout.hasOverflow {
                    Menu {
                        ForEach(hiddenTools, id: \.rawValue) { tool in
                            if let item = EditorToolItem.all.first(where: { $0.tool == tool }) {
                                EditorToolMenuItem(item: item, selection: $selection, hasPro: hasPro, onSelect: onSelect)
                            }
                        }
                        if !hiddenTools.isEmpty && !hiddenActions.isEmpty { Divider() }
                        ForEach(hiddenActions) { overflowAction($0) }
                    } label: {
                        Label(String(localized: "Mehr"), systemImage: "chevron.down")
                            .font(.system(size: size.labelSize))
                            .foregroundStyle(activeIsHidden ? Color.accentColor : Color.primary)
                            .frame(height: size.buttonHeight)
                            .contentShape(.rect)
                    }
                    .menuIndicator(.hidden).menuStyle(.borderlessButton)
                    .frame(width: EditorToolOverflowLayout.moreWidth(size: size), height: size.buttonHeight)
                    .foregroundStyle(activeIsHidden ? Color.accentColor : Color.primary)
                    .background(activeIsHidden ? Color.accentColor.opacity(0.16) : Color.clear, in: .rect(cornerRadius: 8))
                    .padding(.leading, 4)
                    .help(String(localized: "Weitere Werkzeuge"))
                    .accessibilityLabel(String(localized: "Weitere Werkzeuge"))
                    .accessibilityValue(activeIsHidden ? (activeAction?.title ?? EditorToolItem.all.first { $0.tool == selection.toolbarTool }?.title ?? "") : "")
                    .accessibilityIdentifier("editor.tools.more")
                }
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: size.buttonHeight, alignment: .leading)
        }
        .frame(height: size.buttonHeight)
    }
}

private struct EditorToolMenuItem: View {
    let item: EditorToolItem
    @Binding var selection: AnnotationTool
    let hasPro: Bool
    let onSelect: () -> Void
    private var isLocked: Bool { !hasPro && ProFeature.required(for: item.tool) != nil }
    var body: some View {
        Toggle(isOn: Binding(get: { selection.toolbarTool == item.tool }, set: { _ in
            if selection.toolbarTool != item.tool { selection = item.tool }
            onSelect()
        })) {
            Label(isLocked ? item.title + " · Pro" : item.title, systemImage: item.symbol)
        }
        .help(isLocked ? String(localized: "Dieses Werkzeug gehört zu Snaprivo Pro.") : item.hint)
        .accessibilityIdentifier("editor.tool.\(item.id)")
    }
}


private struct EditorToolButton: View {
    let item: EditorToolItem
    let size: EditorToolbarSize
    let isSelected: Bool
    var isProLocked = false
    var selectionNamespace: Namespace.ID? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EditorToolbarLabel(title: item.title, symbol: item.symbol, size: size,
                               extraWidth: item.tool == .crop ? 18 : 0, isSelected: isSelected)
        }
        .buttonStyle(EditorToolbarButtonStyle(isSelected: isSelected, selectionNamespace: selectionNamespace))
        .help(isProLocked ? String(localized: "Dieses Werkzeug gehört zu Snaprivo Pro.") : item.hint)
        .accessibilityLabel(item.title)
        .accessibilityHint(isProLocked ? String(localized: "Dieses Werkzeug gehört zu Snaprivo Pro.") : item.hint)
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

    static func requiredWidth(title: String, size: EditorToolbarSize, extraWidth: CGFloat = 0) -> CGFloat {
        let textWidth = [NSFont.Weight.regular, .medium].map { weight in
            (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size.labelSize, weight: weight)]).width
        }.max() ?? 0
        return ceil(max(size.buttonWidth + extraWidth, textWidth + 4, size.iconSize))
    }
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: size.iconSize, weight: isSelected ? .semibold : .regular))
                .frame(height: size.iconSize + 3)
            Text(title).font(.system(size: size.labelSize, weight: isSelected ? .medium : .regular))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: Self.requiredWidth(title: title, size: size, extraWidth: extraWidth))
        .frame(height: size.buttonHeight)
        .contentShape(.rect(cornerRadius: 8))
    }
}

struct EditorToolbarButtonStyle: ButtonStyle {
    var isSelected = false
    /// Buttons sharing a namespace move one highlight instead of swapping two.
    var selectionNamespace: Namespace.ID? = nil
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(Color.primary.opacity(isSelected ? 0 : configuration.isPressed ? 0.12 : isHovered && isEnabled ? 0.07 : 0),
                        in: .rect(cornerRadius: 8))
            .background { if isSelected { selectionHighlight(pressed: configuration.isPressed) } }
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }

    @ViewBuilder private func selectionHighlight(pressed: Bool) -> some View {
        let highlight = RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(pressed ? 0.24 : 0.16))
        if let selectionNamespace { highlight.matchedGeometryEffect(id: "selection", in: selectionNamespace) }
        else { highlight }
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

/// Match the image-action buttons while retaining a native keyboard-accessible menu.
struct EditorTransformButton: View {
    let model: EditorModel
    let size: EditorToolbarSize
    @State private var presentation = EditorTransformMenuPresentation()
    var body: some View {
        Button { presentation.show(for: model) } label: {
            EditorToolbarLabel(title: String(localized: "Drehen"), symbol: "rotate.right", size: size)
        }
        .buttonStyle(EditorToolbarButtonStyle())
        .background(EditorTransformMenuAnchor(presentation: presentation).allowsHitTesting(false).accessibilityHidden(true))
        .disabled(!model.canSwitchEditingTool)
        .help(String(localized: "Bild und Markierungen drehen oder spiegeln"))
        .accessibilityIdentifier("editor.transform")
    }
}

struct EditorTransformCommands: View {
    let model: EditorModel
    var body: some View {
        Button(String(localized: "Frei drehen …"), systemImage: "rotate.3d") {
            model.beginFreeRotation()
        }
        Divider()
        Button(String(localized: "90° nach rechts drehen"), systemImage: "rotate.right") { model.transformImage(model.history.transform.rotated()) }
        Button(String(localized: "90° nach links drehen"), systemImage: "rotate.left") { model.transformImage(model.history.transform.rotated(clockwise: false)) }
        Button(String(localized: "Horizontal spiegeln")) { model.transformImage(model.history.transform.flippedHorizontally()) }
        Button(String(localized: "Vertikal spiegeln")) { model.transformImage(model.history.transform.flippedVertically()) }
        Button(String(localized: "Ausrichtung zurücksetzen")) { model.transformImage(.identity) }.disabled(model.history.transform == .identity)
    }
}

@MainActor private final class EditorTransformMenuPresentation: NSObject {
    weak var anchor: NSView?
    private var model: EditorModel?
    func show(for model: EditorModel) {
        guard let anchor, anchor.window != nil, self.model == nil, model.canSwitchEditingTool else { return }
        self.model = model
        defer { self.model = nil }
        let menu = NSMenu(title: String(localized: "Drehen")); menu.autoenablesItems = false
        let actions: [(String, String)] = [
            (String(localized: "90° nach rechts drehen"), "rotate.right"),
            (String(localized: "90° nach links drehen"), "rotate.left"),
            (String(localized: "Horizontal spiegeln"), "arrow.left.and.right.righttriangle.left.righttriangle.right"),
            (String(localized: "Vertikal spiegeln"), "arrow.up.and.down.righttriangle.up.righttriangle.down"),
            (String(localized: "Ausrichtung zurücksetzen"), "arrow.uturn.backward")
        ]
        let free = NSMenuItem(title: String(localized: "Frei drehen …"), action: #selector(apply(_:)), keyEquivalent: "")
        free.target = self; free.tag = 5; free.image = NSImage(systemSymbolName: "rotate.3d", accessibilityDescription: nil)
        menu.addItem(free); menu.addItem(.separator())
        for (index, entry) in actions.enumerated() {
            if index == 2 || index == 4 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: entry.0, action: #selector(apply(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.image = NSImage(systemSymbolName: entry.1, accessibilityDescription: nil)
            item.isEnabled = index != 4 || model.history.transform != .identity
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: anchor.bounds.minX, y: anchor.bounds.minY), in: anchor)
    }
    @objc private func apply(_ sender: NSMenuItem) {
        guard let model else { return }
        let transform = model.history.transform
        switch sender.tag {
        case 0: model.transformImage(transform.rotated())
        case 1: model.transformImage(transform.rotated(clockwise: false))
        case 2: model.transformImage(transform.flippedHorizontally())
        case 3: model.transformImage(transform.flippedVertically())
        case 5: model.beginFreeRotation()
        default: model.transformImage(.identity)
        }
    }
}

private struct EditorTransformMenuAnchor: NSViewRepresentable {
    let presentation: EditorTransformMenuPresentation
    func makeCoordinator() -> EditorTransformMenuPresentation { presentation }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); view.setAccessibilityElement(false); presentation.anchor = view; return view
    }
    func updateNSView(_ view: NSView, context: Context) { presentation.anchor = view }
    static func dismantleNSView(_ view: NSView, coordinator: EditorTransformMenuPresentation) {
        if coordinator.anchor === view { coordinator.anchor = nil }
    }
}

#Preview("Werkzeuge · Pfeil") {
    EditorAdaptiveToolPalette(selection: .constant(.arrow), size: .standard, order: EditorToolItem.all.map(\.tool), actions: [], hasPro: true, onSelect: {}, action: { _ in EmptyView() }, overflowAction: { _ in EmptyView() })
        .padding().frame(width: 720)
}

#Preview("Schmal · Unschärfe") {
    EditorAdaptiveToolPalette(selection: .constant(.blur), size: .standard, order: EditorToolItem.all.map(\.tool), actions: [], hasPro: true, onSelect: {}, action: { _ in EmptyView() }, overflowAction: { _ in EmptyView() })
        .padding(8).frame(width: 488)
}

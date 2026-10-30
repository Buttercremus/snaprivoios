import SwiftUI
import AppKit
import ImageIO
import SnagForgeDomain

/// Modifier handling is kept separate so interaction tests can exercise synthetic AppKit events.
enum EditorFilmstripInteraction {
    static func extendsSelection(for modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.command) || modifiers.contains(.control)
    }
}

/// A transparent native hit-test surface is needed because AppKit turns Ctrl-click into
/// a contextual click before SwiftUI's Button action runs. It only claims modified clicks;
/// ordinary clicks and real right-clicks continue to the SwiftUI button/context menu.
final class FilmstripModifierClickView: NSView, NSUserInterfaceValidations {
    var onToggleSelection: (() -> Void)?
    var onCopySelection: (() -> Bool)?
    var canCopySelection: (() -> Bool)?
    var isEnabled: (() -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    /// Testable without relying on NSApp.currentEvent (which is commonly nil in unit tests).
    func shouldIntercept(event: NSEvent, at point: NSPoint) -> Bool {
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard isEnabled?() ?? true,
              bounds.contains(localPoint),
              !trashExclusionRect.contains(localPoint),
              event.type == .leftMouseDown || event.type == .leftMouseUp
                  || event.type == .rightMouseDown || event.type == .rightMouseUp,
              EditorFilmstripInteraction.extendsSelection(for: event.modifierFlags)
        else { return false }
        return true
    }

    private var trashExclusionRect: NSRect {
        NSRect(x: bounds.maxX - 32, y: bounds.maxY - 32, width: 32, height: 32)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, shouldIntercept(event: event, at: point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled?() ?? true,
              EditorFilmstripInteraction.extendsSelection(for: event.modifierFlags) else { return }
        window?.makeFirstResponder(self)
        onToggleSelection?()
    }

    override func rightMouseDown(with event: NSEvent) {
        // Ctrl-click is delivered as rightMouseDown by some AppKit controls. A plain
        // right click is deliberately not consumed, so SwiftUI can show its context menu.
        if isEnabled?() ?? true, EditorFilmstripInteraction.extendsSelection(for: event.modifierFlags) {
            window?.makeFirstResponder(self)
            onToggleSelection?()
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.type == .keyDown,
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control),
              event.charactersIgnoringModifiers?.lowercased() == "c",
              canCopySelection?() ?? true
        else { return super.performKeyEquivalent(with: event) }
        copy(nil)
        return true
    }

    @objc func copy(_ sender: Any?) {
        guard window?.firstResponder === self, canCopySelection?() ?? true else { return }
        _ = onCopySelection?()
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(copy(_:)) else { return true }
        return window?.firstResponder === self && (canCopySelection?() ?? true)
    }
}

private struct FilmstripModifierClickInterceptor: NSViewRepresentable {
    let onToggleSelection: () -> Void
    let onCopySelection: () -> Bool
    let canCopySelection: () -> Bool
    let isEnabled: () -> Bool

    func makeNSView(context: Context) -> FilmstripModifierClickView {
        let view = FilmstripModifierClickView()
        view.onToggleSelection = onToggleSelection
        view.onCopySelection = onCopySelection
        view.canCopySelection = canCopySelection
        view.isEnabled = isEnabled
        view.postsFrameChangedNotifications = false
        return view
    }

    func updateNSView(_ nsView: FilmstripModifierClickView, context: Context) {
        nsView.onToggleSelection = onToggleSelection
        nsView.onCopySelection = onCopySelection
        nsView.canCopySelection = canCopySelection
        nsView.isEnabled = isEnabled
    }
}

/// Navigation uses the saved, flattened thumbnail cache; no original pixels are decoded here.
struct EditorFilmstripView: View {
    let workspace: WorkspaceModel
    private var selected: UUID? { workspace.editor?.document.id }
    private var items: [ProjectLibraryItem] { workspace.editorQuickSwitchItems }
    private var selectedForCopyCount: Int { workspace.editorFilmstripSelectedIDs.count }
    private var showsMultiCopyHint: Bool {
        items.count >= 2 && !workspace.preferences.dismissedEditorHints.contains("filmstripMultiCopy")
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(String(localized: "Letzte 7 Tage")).font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "\(items.count) Bilder")).font(.caption).foregroundStyle(.secondary)
                    if showsMultiCopyHint {
                        HStack(spacing: 4) {
                            Image(systemName: "command")
                                .accessibilityHidden(true)
                            Text(String(localized: "Mehrere Bilder: ⌘- oder Strg-Klick"))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(String(localized: "⌘- oder Strg-Klick wählt mehrere Bilder. Danach Auswahl kopieren."))
                            Button {
                                workspace.preferences.dismissedEditorHints.insert("filmstripMultiCopy")
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Hinweis zur Mehrfachauswahl ausblenden"))
                            .accessibilityLabel(String(localized: "Hinweis zur Mehrfachauswahl ausblenden"))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 290, alignment: .leading)
                        .layoutPriority(-1)
                    }
                    Spacer()
                    if selectedForCopyCount > 1 {
                        Text(String(localized: "\(selectedForCopyCount) ausgewählt"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Auswahl kopieren"), systemImage: "doc.on.doc") {
                            _ = workspace.copySelectedEditorImages()
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderless)
                        .disabled(!workspace.canCopySelectedEditorImages || workspace.isCopyingSelectedEditorImages)
                        .help(String(localized: "Auswahl kopieren"))
                    }
                    if let notice = workspace.editorFilmstripCopyNotice {
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 180, alignment: .trailing)
                            .accessibilityLabel(notice)
                    }
                    Button(String(localized: "Vorheriges Bild"), systemImage: "chevron.left") { workspace.switchEditorImage(by: -1) }
                        .keyboardShortcut(workspace.captureShortcuts.editorNavigationShortcut(-1))
                        .disabled(!workspace.canSwitchEditorImageForToolbar || workspace.adjacentEditorImage(-1) == nil)
                        .allowsHitTesting(!workspace.isLoading)
                        .help(workspace.captureShortcuts.editorNavigationShortcut(-1) == nil ? String(localized: "Vorheriges Bild") : String(localized: "Vorheriges Bild (⌥⌘←)"))
                    Button(String(localized: "Nächstes Bild"), systemImage: "chevron.right") { workspace.switchEditorImage(by: 1) }
                        .keyboardShortcut(workspace.captureShortcuts.editorNavigationShortcut(1))
                        .disabled(!workspace.canSwitchEditorImageForToolbar || workspace.adjacentEditorImage(1) == nil)
                        .allowsHitTesting(!workspace.isLoading)
                        .help(workspace.captureShortcuts.editorNavigationShortcut(1) == nil ? String(localized: "Nächstes Bild") : String(localized: "Nächstes Bild (⌥⌘→)"))
                }
                .lineLimit(1)
                .labelStyle(.iconOnly).buttonStyle(.borderless).padding(.horizontal, 12)
                .frame(height: 26)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(items) { item in
                                let active = selected == item.id
                                let title = active ? workspace.editor?.name ?? item.document.title : item.document.title
                                FilmstripItem(workspace: workspace, item: item, title: title, active: active,
                                              selectedForCopy: workspace.editorFilmstripSelectedIDs.contains(item.id))
                                .id(item.id)
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    .scrollIndicators(.visible)
                    .frame(height: 102)
                    .onAppear {
                        // Reveal once on entry; subsequent selections leave the strip under the pointer.
                        if let selected { proxy.scrollTo(selected, anchor: .leading) }
                    }
                }.frame(width: geometry.size.width)
            }
            .padding(.top, 6)
            .frame(width: geometry.size.width)
        }
        .frame(height: 138)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Bildvorschauleiste"))
        .accessibilityIdentifier("editor.quickSwitch")
    }
}

private struct FilmstripItem: View {
    let workspace: WorkspaceModel
    let item: ProjectLibraryItem
    let title: String
    let active: Bool
    let selectedForCopy: Bool
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func trash() {
        Task { await workspace.trashEditorImage(item.id) }
    }

    private func activate() {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let extending = EditorFilmstripInteraction.extendsSelection(for: modifiers)
        if extending {
            workspace.selectEditorFilmstripImage(item.id, extending: true)
        } else {
            workspace.switchEditorImage(to: item.id)
        }
    }

    var body: some View {
        Button(action: activate) {
            VStack(spacing: 4) {
                ProjectThumbnail(data: item.thumbnail)
                    .frame(width: 112, height: 64)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: 4))
                Text(title).font(.caption2).lineLimit(1).truncationMode(.middle)
                    .frame(width: 112)
            }
            .padding(4)
            .background(selectedForCopy ? Color.accentColor.opacity(0.16) : (active ? Color.accentColor.opacity(0.12) : .clear), in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selectedForCopy ? Color.accentColor : (active ? Color.accentColor : Color.secondary.opacity(0.25)),
                                  lineWidth: selectedForCopy || active ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(FilmstripThumbnailButtonStyle())
        .disabled(!workspace.canSwitchEditorImage)
        .focused($isFocused)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(selectedForCopy
            ? String(localized: "Ausgewählt")
            : (active ? String(localized: "Aktuelles Bild") : ""))
        .accessibilityHint(String(localized: "Bild direkt im Editor öffnen"))
        .accessibilityAddTraits(selectedForCopy ? .isSelected : [])
        .accessibilityIdentifier("editor.quickSwitch.\(item.id)")
        .accessibilityAction(named: Text(String(localized: "In den Papierkorb")), trash)
        .accessibilityAction(named: Text(String(localized: "Auswahl umschalten"))) {
            workspace.selectEditorFilmstripImage(item.id, extending: true)
        }
        .contextMenu {
            Button(String(localized: "Auswahl umschalten"), systemImage: selectedForCopy ? "checkmark.circle.fill" : "circle") {
                workspace.selectEditorFilmstripImage(item.id, extending: true)
            }
            .disabled(!workspace.canSwitchEditorImage)
            if workspace.editorFilmstripSelectedIDs.count > 1 {
                Button(String(localized: "Auswahl kopieren"), systemImage: "doc.on.doc") {
                    _ = workspace.copySelectedEditorImages()
                }
                .disabled(!workspace.canCopySelectedEditorImages || workspace.isCopyingSelectedEditorImages)
            }
            Button(String(localized: "In den Papierkorb"), systemImage: "trash", action: trash)
                .disabled(!workspace.canSwitchEditorImage)
        }
        .overlay {
            FilmstripModifierClickInterceptor(
                onToggleSelection: { workspace.selectEditorFilmstripImage(item.id, extending: true) },
                onCopySelection: { workspace.copySelectedEditorImages() != nil },
                canCopySelection: { workspace.canCopySelectedEditorImages && !workspace.isCopyingSelectedEditorImages },
                isEnabled: { workspace.canSwitchEditorImage }
            )
            .allowsHitTesting(true)
        }
        .overlay(alignment: .topLeading) {
            if selectedForCopy {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(radius: 1)
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: trash) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(.regularMaterial, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(!workspace.canSwitchEditorImage)
            .help(String(localized: "In den Papierkorb"))
            .accessibilityLabel(String(localized: "In den Papierkorb"))
            .accessibilityIdentifier("editor.quickSwitch.trash.\(item.id)")
            .opacity(isHovered || isFocused ? 1 : 0)
            .allowsHitTesting(isHovered || isFocused)
            .accessibilityHidden(!isHovered && !isFocused)
            .padding(4)
        }
        .onHover { hovering in
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.08 : 0.1)) {
                isHovered = hovering
            }
        }
    }
}

/// Keep image pixels unchanged when navigation is temporarily disabled during a switch.
private struct FilmstripThumbnailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Small views share the flattened project cache, never the immutable original.
struct ProjectThumbnail: View {
    let data: Data?
    var maximumDimension = 224
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .accessibilityHidden(true)
        .task(id: data) {
            // Replace an updated thumbnail only after decoding, without a placeholder flash.
            guard let data else { image = nil; return }
            let maximumDimension = maximumDimension
            let decoded = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            image = decoded
        }
    }
}

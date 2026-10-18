import SwiftUI
import ImageIO
import SnagForgeDomain

/// Navigation uses the saved, flattened thumbnail cache; no original pixels are decoded here.
struct EditorFilmstripView: View {
    let workspace: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: UUID? { workspace.editor?.document.id }
    private var items: [ProjectLibraryItem] { workspace.editorQuickSwitchItems }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(String(localized: "Bilder schnell wechseln")).font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "\(items.count) Bilder")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
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
                }.labelStyle(.iconOnly).buttonStyle(.borderless).padding(.horizontal, 12)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(items) { item in
                                let active = selected == item.id
                                let title = active ? workspace.editor?.name ?? item.document.title : item.document.title
                                Button { workspace.switchEditorImage(to: item.id) } label: {
                                    VStack(spacing: 4) {
                                        ProjectThumbnail(data: item.thumbnail)
                                            .frame(width: 112, height: 64)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .clipShape(.rect(cornerRadius: 4))
                                        Text(title).font(.caption2).lineLimit(1).truncationMode(.middle)
                                            .frame(width: 112)
                                    }
                                    .padding(4)
                                    .background(active ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 7))
                                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(active ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: active ? 2 : 1) }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(FilmstripThumbnailButtonStyle())
                                .disabled(!workspace.canSwitchEditorImage)
                                .help(title)
                                .accessibilityLabel(title)
                                .accessibilityValue(active ? String(localized: "Aktuelles Bild") : "")
                                .accessibilityHint(String(localized: "Bild direkt im Editor öffnen"))
                                .accessibilityAddTraits(active ? .isSelected : [])
                                .accessibilityIdentifier("editor.quickSwitch.\(item.id)")
                                .id(item.id)
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    .scrollIndicators(.visible)
                    .frame(height: 102)
                    .onChange(of: selected, initial: true) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: items.map(\.id)) { _, _ in
                        if let selected { proxy.scrollTo(selected, anchor: .center) }
                    }
                }.frame(width: geometry.size.width)
            }
            .padding(.top, 6)
            .frame(width: geometry.size.width)
        }
        .frame(height: 128)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Bildvorschauleiste"))
        .accessibilityIdentifier("editor.quickSwitch")
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

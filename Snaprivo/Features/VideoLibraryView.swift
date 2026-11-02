import SwiftUI
import SnagForgeDomain

struct VideoLibraryView: View {
    @Bindable var model: VideoLibraryModel
    var allBackup: (() -> Void)?
    var allRestore: (() -> Void)?
    @State private var query = ""
    @State private var renaming: VideoDocument?
    @State private var showsTrash = false
    @State private var deleting: VideoDocument?
    @State private var nameOrder = false
    private var displayed: [VideoRecordingFiles.Item] { model.items.filter { ($0.document.trashedAt != nil) == showsTrash } }
    private var filtered: [VideoRecordingFiles.Item] {
        let terms = LibrarySearch.terms(query)
        return model.items.filter { item in (item.document.trashedAt != nil) == showsTrash && terms.allSatisfy { LibrarySearch.fold(item.document.title).contains($0) } }
            .sorted { nameOrder ? $0.document.title.localizedStandardCompare($1.document.title) == .orderedAscending : $0.document.createdAt > $1.document.createdAt }
    }
    var body: some View {
        VStack(spacing: 0) {
            // Same button and menu family as the image library header.
            HStack(spacing: 8) {
                Text(String(localized: "\(displayed.count) Videos")).font(.headline)
                Spacer()
                Menu {
                    Picker(String(localized: "Sortieren"), selection: $nameOrder) {
                        Text(String(localized: "Neueste zuerst")).tag(false)
                        Text(String(localized: "Name")).tag(true)
                    }.pickerStyle(.inline).labelsHidden()
                } label: { Label(nameOrder ? String(localized: "Name") : String(localized: "Neueste zuerst"), systemImage: "arrow.up.arrow.down") }
                    .fixedSize().accessibilityLabel(String(localized: "Sortieren"))
                Toggle(String(localized: "Papierkorb"), systemImage: "trash", isOn: $showsTrash).toggleStyle(.button).fixedSize()
                Menu(String(localized: "Dateien"), systemImage: "folder") {
                    if let allBackup { Button(String(localized: "Alles sichern …"), action: allBackup) }
                    if let allRestore { Button(String(localized: "Alles wiederherstellen …"), action: allRestore) }
                    Divider()
                    Button(String(localized: "Videos sichern …")) { model.chooseBackup(restoring: false) }
                    Button(String(localized: "Videosicherung wiederherstellen …")) { model.chooseBackup(restoring: true) }
                }.fixedSize()
                Button(String(localized: "Erneut laden"), systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .labelStyle(.iconOnly).help(String(localized: "Erneut laden"))
            }.padding(16)
            Text(ByteCountFormatter.string(fromByteCount: model.items.filter { ($0.document.trashedAt != nil) == showsTrash }.reduce(0) { $0 + $1.bytes }, countStyle: .file))
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.bottom, 12)
            if !model.issues.isEmpty {
                DisclosureGroup(String(localized: "Videobibliothek prüfen")) {
                    ForEach(model.issues, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.didLoad { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if displayed.isEmpty {
                ContentUnavailableView(showsTrash ? String(localized: "Papierkorb ist leer") : String(localized: "Noch keine Videos"), systemImage: showsTrash ? "trash" : "video",
                    description: Text(String(localized: "Starte im Menü Aufnahme eine Videoaufnahme. Nach erfolgreichem Stop bleibt das Original hier erhalten.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(String(localized: "Keine passenden Videos"), systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 20)], spacing: 20) {
                        ForEach(filtered) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                if item.document.state == .finished && !showsTrash {
                                    Button { Task { await model.showPreview(item.id) } } label: { VideoLibraryCard(item: item) }
                                        .buttonStyle(.plain).accessibilityIdentifier("video.library.open.\(item.id)")
                                } else {
                                    VideoLibraryCard(item: item).accessibilityIdentifier("video.library.unfinished.\(item.id)")
                                }
                                HStack {
                                    if showsTrash {
                                        Button(String(localized: "Wiederherstellen"), systemImage: "arrow.uturn.backward") { Task { _ = await model.changeTrash(item.id, action: .restore) } }
                                        Spacer()
                                        Button(String(localized: "Endgültig löschen …"), systemImage: "trash", role: .destructive) { deleting = item.document }
                                    } else {
                                    Button(String(localized: "Umbenennen …"), systemImage: "pencil") { renaming = item.document }
                                        .labelStyle(.iconOnly).help(String(localized: "Umbenennen …"))
                                    Spacer()
                                    Button(String(localized: "In den Papierkorb"), systemImage: "trash") { Task { _ = await model.changeTrash(item.id, action: .trash) } }.labelStyle(.iconOnly)
                                    Menu {
                                        Button(String(localized: "Video ansehen")) { Task { await model.showPreview(item.id) } }
                                        Button(String(localized: "Original extern öffnen")) { Task { await model.open(item.id) } }
                                        Button(String(localized: "MP4 speichern …")) { model.chooseExport(item.id) }
                                        Button(String(localized: "Im Finder zeigen")) { Task { await model.reveal(item.id) } }
                                    } label: { Image(systemName: "ellipsis.circle") }
                                    .menuStyle(.borderlessButton).fixedSize().disabled(item.document.state != .finished)
                                    .accessibilityLabel(String(localized: "Videoaktionen"))
                                    }
                                }.padding(.horizontal, 8)
                                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView(String(localized: "Videos verarbeiten …")).padding(24).background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .searchable(text: $query, prompt: String(localized: "Videos durchsuchen"))
        .sheet(item: $renaming) { document in
            ProjectRenameSheet(title: document.title, heading: String(localized: "Video umbenennen"), prompt: String(localized: "Videoname")) { await model.rename(document.id, title: $0) }
        }
        .sheet(item: $model.preview) { preview in VideoReviewView(model: preview) }
        .alert(String(localized: "Videoaktion fehlgeschlagen"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert(String(localized: "Dateiaktion abgeschlossen"), isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .alert(String(localized: "Video endgültig löschen?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "Endgültig löschen"), role: .destructive) {
                if let id = deleting?.id { Task { _ = await model.changeTrash(id, action: .delete) } }; deleting = nil
            }
            Button(String(localized: "Abbrechen"), role: .cancel) { deleting = nil }
        } message: { Text(String(localized: "Das Originalvideo und seine Schnittdaten werden dauerhaft von diesem Mac entfernt.")) }
        .task { await model.refresh() }
    }
}

private struct VideoLibraryCard: View {
    let item: VideoRecordingFiles.Item
    private var stateTitle: String {
        switch item.document.state {
        case .finished: String(localized: "Video ansehen")
        case .recording: String(localized: "Aufnahme läuft")
        case .interrupted: String(localized: "Aufnahme unterbrochen")
        case .failed: String(localized: "Aufnahme fehlgeschlagen")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let data = item.thumbnail, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().padding(8) }
                Image(systemName: item.document.state == .finished ? "play.circle.fill" : "exclamationmark.triangle")
                    .font(.largeTitle).symbolRenderingMode(.hierarchical).foregroundStyle(item.document.state == .finished ? Color.accentColor : Color.secondary)
            }.frame(height: 160).clipShape(.rect(cornerRadius: 12))
            Text(item.document.title).font(.headline).lineLimit(1)
            Text(item.document.createdAt, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(.secondary)
            if item.document.state == .finished, let seconds = item.document.duration, let size = item.document.pixelSize {
                Text(String(format: "%02d:%02d · %d × %d", Int(seconds) / 60, Int(seconds) % 60, size.width, size.height)).font(.caption.monospacedDigit())
                Text(item.document.hasAudio ? String(localized: "Mit Ton") : String(localized: "ohne Ton")).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(stateTitle).font(.caption.bold())
                Text(item.document.failure ?? String(localized: "Nicht fertiggestellt. Es wird kein abspielbares Video angeboten."))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.quaternary) }
            .accessibilityElement(children: .combine).accessibilityLabel(item.document.title + ", " + stateTitle)
    }
}

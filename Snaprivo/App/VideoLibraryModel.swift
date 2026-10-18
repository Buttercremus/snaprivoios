import AppKit
import Observation
import SnagForgeDomain

@MainActor @Observable final class VideoLibraryModel {
    let files: VideoRecordingFiles
    private(set) var items: [VideoRecordingFiles.Item] = []
    private(set) var issues: [String] = []
    private(set) var didLoad = false
    private(set) var isBusy = false
    var isSuspended = false
    var error: String?
    var notice: String?
    var preview: VideoEditorModel?
    @ObservationIgnored private var operation: Task<Bool, Never>?
    @ObservationIgnored private var panel: NSSavePanel?
    @ObservationIgnored private let openURL: @MainActor (URL) -> Bool

    init(root: URL? = nil, openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        files = VideoRecordingFiles(root: root); self.openURL = openURL
    }
    func refresh() async {
        do { let listing = try await files.list(); items = listing.items; issues = listing.issues }
        catch { issues = [error.localizedDescription] }
        didLoad = true
    }
    @discardableResult func open(_ id: UUID) async -> Bool {
        do {
            let url = try await files.movieURL(id)
            guard openURL(url) else { throw CocoaError(.fileReadUnknown) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func showPreview(_ id: UUID) async {
        guard preview == nil, !isBusy else { return }
        do {
            let document = try await files.document(id), url = try await files.movieURL(id)
            guard preview == nil else { return }
            preview = VideoEditorModel(document: document, url: url, files: files) { [weak self] in await self?.refresh() }
        } catch { self.error = error.localizedDescription }
    }
    func showPreview(recording url: URL) async {
        await refresh()
        guard url.deletingLastPathComponent().standardizedFileURL == files.root.standardizedFileURL,
              let item = items.first(where: { $0.document.state == .finished && $0.document.fileName == url.lastPathComponent }) else {
            error = VideoRecordingError.invalidMovie.localizedDescription; return
        }
        await showPreview(item.id)
    }
    func reveal(_ id: UUID) async {
        do { NSWorkspace.shared.activateFileViewerSelecting([try await files.movieURL(id)]) }
        catch { self.error = error.localizedDescription }
    }
    func rename(_ id: UUID, title: String) async -> Bool {
        await perform { [files] in try await files.rename(id, title: title) }
    }
    enum TrashAction { case trash, restore, delete }
    func changeTrash(_ id: UUID, action: TrashAction) async -> Bool {
        guard preview == nil else { error = String(localized: "Schließe zuerst die Videovorschau."); return false }
        return await perform { [files] in
            switch action {
            case .trash: try await files.moveToTrash(id)
            case .restore: try await files.restoreFromTrash(id)
            case .delete: try await files.permanentlyDelete(id)
            }
        }
    }
    func backup(to target: URL) async -> Bool {
        await perform { [self] in
            try await files.backup(to: target)
            notice = String(localized: "Videosicherung erstellt. Sie enthält Originale, Schnittdaten, Papierkorb und unterbrochene Aufnahmen.")
        }
    }
    func restore(from source: URL) async -> Bool {
        await perform { [self] in
            let count = try await files.restore(from: source)
            notice = String(localized: "\(count) Videos als neue Kopien wiederhergestellt.")
        }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) async -> Bool {
        guard !isBusy, !isSuspended else { return false }
        isBusy = true
        let task = Task { [self] in
            do { try await action(); await refresh(); return true }
            catch { self.error = error.localizedDescription; await refresh(); return false }
        }
        operation = task
        let result = await task.value; operation = nil; isBusy = false
        return result
    }
    func chooseBackup(restoring: Bool) {
        guard panel == nil, !isBusy, !isSuspended else { return }
        let dialog = NSOpenPanel(); dialog.canChooseFiles = false; dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false
        dialog.message = restoring ? String(localized: "Wähle den Ordner einer Snaprivo-Videosicherung. Bestehende Videos bleiben erhalten.") : String(localized: "Wähle einen Zielordner. Darin wird eine neue Videosicherung angelegt.")
        panel = dialog
        dialog.begin { [weak self] response in
            guard let self else { return }; panel = nil
            guard response == .OK, let url = dialog.url else { return }
            Task {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                if restoring { _ = await restore(from: url) }
                else { _ = await backup(to: url.appendingPathComponent("Snaprivo-Videos-\(UUID())", isDirectory: true)) }
            }
        }
    }
    func chooseExport(_ id: UUID) {
        guard panel == nil, !isBusy, !isSuspended else { return }
        let dialog = NSSavePanel(); dialog.allowedContentTypes = [.mpeg4Movie]
        dialog.nameFieldStringValue = "Snaprivo-Video.mp4"; panel = dialog
        dialog.begin { [weak self] response in
            guard let self else { return }; panel = nil
            guard response == .OK, let target = dialog.url else { return }
            Task {
                let access = target.startAccessingSecurityScopedResource(); defer { if access { target.stopAccessingSecurityScopedResource() } }
                _ = await perform { [files] in try await files.exportEdited(id, to: target) }
            }
        }
    }
    @discardableResult func finishPendingWork() async -> Bool {
        panel?.cancel(nil); panel = nil
        if let operation { _ = await operation.value }
        if let preview { return await preview.finishPendingWork() }
        return true
    }
}

import AppKit
import SnagForgeDomain

/// Combined „Alle“ library: synthetic projects and video documents only, no files or capture.
enum LibraryEntryChecks {
    @MainActor static func run() async throws {
        let size = PixelSize(width: 20, height: 20)!
        let invoice = ProjectDocument(title: "Beta Bild", pixelSize: size, createdAt: Date(timeIntervalSince1970: 30), tags: ["Rechnung"])
        let older = ProjectDocument(title: "Zeta", pixelSize: size, createdAt: Date(timeIntervalSince1970: 10))
        let clip = VideoDocument(title: "Alpha Video", fileName: "a.mp4", state: .finished, createdAt: Date(timeIntervalSince1970: 20))
        var trashed = VideoDocument(title: "Alpha gelöscht", fileName: "b.mp4", state: .finished, createdAt: Date(timeIntervalSince1970: 40))
        trashed.trashedAt = Date(timeIntervalSince1970: 50)
        let images = [ProjectLibraryItem(document: older, thumbnail: nil), ProjectLibraryItem(document: invoice, thumbnail: nil)]
        let videos = [VideoRecordingFiles.Item(document: trashed), VideoRecordingFiles.Item(document: clip)]
        func ids(_ query: String = "", matches: Set<UUID>? = nil, pro: Bool = true, byName: Bool = false) -> [UUID] {
            LibraryEntry.combined(images: images, videos: videos, query: query, imageMatches: matches, includesOrganization: pro, byName: byName).map(\.id)
        }
        check(ids() == [invoice.id, clip.id, older.id], "Images and videos are not interleaved by capture time or trash leaked in")
        check(ids(byName: true) == [clip.id, invoice.id, older.id], "Name order differs across media")
        check(ids("video") == [clip.id] && ids("ALPHA") == [clip.id], "Video titles are not searched or trashed videos matched")
        check(ids("rechnung") == [invoice.id] && ids("rechnung", pro: false).isEmpty, "Tags searched without Pro")
        check(ids("inhalt", matches: [older.id]) == [older.id], "Finished content search was ignored for images")
        check(ids(matches: []) == ids(), "An empty query filtered by stale content matches")
        let twin = VideoDocument(title: "Gleich", fileName: "c.mp4", state: .finished, createdAt: Date(timeIntervalSince1970: 30))
        let tie = LibraryEntry.combined(images: images, videos: [.init(document: twin)], query: "", includesOrganization: true, byName: false).map(\.id)
        check(tie == LibraryEntry.combined(images: images.reversed(), videos: [.init(document: twin)], query: "", includesOrganization: true, byName: false).map(\.id),
              "Equal capture times do not order deterministically")

        // A finished recording keeps „Alle“ (which presents the video itself) and leaves only the image tab.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryEntries-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "LibraryEntries-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        check(workspace.libraryMedia == .images, "Default library tab changed")
        workspace.libraryMedia = .all; workspace.section = .editor
        await workspace.screenshot.onVideoLibraryChange?()
        check(workspace.libraryMedia == .all && workspace.section == .library, "Finished video left the combined library")
        workspace.libraryMedia = .images
        await workspace.screenshot.onVideoLibraryChange?()
        check(workspace.libraryMedia == .videos, "Finished video stayed hidden in the image tab")
        print("Library entry checks passed: combined capture-time and name order, trash exclusion, title/tag/content search with Pro boundary, deterministic ties and video handoff per tab.")
    }
}

private func check(_ value: Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) {
    precondition(value, message, file: file, line: line)
}

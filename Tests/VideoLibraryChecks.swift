import AppKit
import SnagForgeDomain

@MainActor enum VideoLibraryChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoLibrary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("Fixture.mp4"); try await VideoRecordingChecks.movie(at: fixture)
        let folder = root.appendingPathComponent("Videos"), files = VideoRecordingFiles(root: folder)
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        require(try await files.list().items.first?.document.state == .recording)
        try FileManager.default.copyItem(at: fixture, to: partial)
        let ready = try await files.finalize(partial)
        let first = try await files.list().items.first!
        require(first.document.state == .finished && first.thumbnail != nil && first.document.duration! > 0)
        let before = try FileManager.default.attributesOfItem(atPath: ready.path), bytes = try Data(contentsOf: ready)
        try await files.rename(first.id, title: "Renamed video")
        let after = try FileManager.default.attributesOfItem(atPath: ready.path)
        require(try Data(contentsOf: ready) == bytes)
        require((before[.systemFileNumber] as? NSNumber) == (after[.systemFileNumber] as? NSNumber) && (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date), "Rename rewrote the movie")
        let restarted = VideoRecordingFiles(root: folder)
        require(try await restarted.list().items.first?.document.title == "Renamed video")
        require(try await restarted.movieURL(first.id) == ready)

        let failed = try await files.prepare(availableBytes: 1_000_000_000)
        try Data("incomplete synthetic movie".utf8).write(to: failed)
        try await files.markFailed(failed, message: "Synthetic writer error")
        await files.discardPartial(failed)
        let interrupted = try await files.prepare(availableBytes: 1_000_000_000)
        try FileManager.default.copyItem(at: fixture, to: interrupted)
        let recovered = try await restarted.list()
        require(recovered.items.filter { $0.document.state == .finished }.count == 1)
        require(recovered.items.filter { $0.document.state == .failed }.count == 1)
        require(recovered.items.filter { $0.document.state == .interrupted }.count == 1)
        for item in recovered.items where item.document.state != .finished {
            do { _ = try await restarted.movieURL(item.id); preconditionFailure("Incomplete movie opened") } catch { }
        }
        require(try await restarted.completed() == [ready])

        let legacy = folder.appendingPathComponent("Legacy.mp4"); try FileManager.default.copyItem(at: fixture, to: legacy)
        let broken = folder.appendingPathComponent("Broken.mp4"); try Data("broken".utf8).write(to: broken)
        async let listingA = restarted.list()
        async let listingB = restarted.list()
        let (migrated, simultaneous) = try await (listingA, listingB)
        require(migrated.items.map(\.id) == simultaneous.items.map(\.id), "Concurrent legacy adoption created duplicate identities")
        require(migrated.items.filter { $0.document.state == .finished }.count == 2)
        require(migrated.items.first { $0.document.fileName == "Broken.mp4" }?.document.state == .failed)
        require(try Data(contentsOf: legacy) == Data(contentsOf: fixture), "Legacy adoption changed original")
        let backup = root.appendingPathComponent("Backup")
        try await restarted.backup(to: backup)
        let manifest = backup.appendingPathComponent("manifest.json")
        let snapshot = try Data(contentsOf: manifest)
        let archive = try JSONDecoder().decode(VideoBackup.self, from: snapshot).validated()
        require(archive.entries.count == 2, "Backup included incomplete recordings")
        do { try await restarted.backup(to: backup); preconditionFailure("Backup replaced an existing target") } catch { }
        require(try Data(contentsOf: manifest) == snapshot)
        let destination = VideoRecordingFiles(root: root.appendingPathComponent("Restored"))
        require(try await destination.restore(from: backup) == 2)
        let copies = try await destination.list().items
        require(Set(copies.map(\.id)).isDisjoint(with: Set(archive.entries.map { $0.document.id })))
        require(copies.allSatisfy { $0.document.state == .finished && $0.thumbnail != nil })
        require(try await destination.restore(from: backup) == 2)
        require(try await destination.list().items.count == 4)
        try Data("corrupted second source".utf8).write(to: backup.appendingPathComponent(archive.entries[1].document.fileName))
        do { _ = try await destination.restore(from: backup); preconditionFailure("Corrupt backup accepted") } catch { }
        require(try await destination.list().items.count == 4, "Invalid backup partially changed library")

        let unknown = root.appendingPathComponent("Unknown"), unknownStore = VideoRecordingFiles(root: unknown)
        let pending = try await unknownStore.prepare(availableBytes: 1_000_000_000)
        let entry = try await unknownStore.list().items.first!
        let metadata = unknown.appendingPathComponent(".library/\(entry.id).json")
        var newer = entry.document; newer.schemaVersion = 999
        let unknownData = try JSONEncoder().encode(newer); try unknownData.write(to: metadata)
        try FileManager.default.copyItem(at: fixture, to: unknown.appendingPathComponent("Unindexed.mp4"))
        let unknownListing = try await unknownStore.list()
        require(unknownListing.items.isEmpty && unknownListing.issues.count == 1)
        require(try Data(contentsOf: metadata) == unknownData)
        require(!FileManager.default.fileExists(atPath: pending.path))

        let committingRoot = root.appendingPathComponent("Committing"), committing = VideoRecordingFiles(root: committingRoot)
        _ = try await committing.prepare(availableBytes: 1_000_000_000)
        var journal = try await committing.list().items.first!.document
        journal.fileName = "Moved-but-not-committed.mp4"
        try JSONEncoder().encode(journal).write(to: committingRoot.appendingPathComponent(".library/\(journal.id).json"))
        try FileManager.default.copyItem(at: fixture, to: committingRoot.appendingPathComponent(journal.fileName))
        let afterCrash = try await VideoRecordingFiles(root: committingRoot).list()
        require(afterCrash.items.count == 1 && afterCrash.items[0].document.state == .interrupted, "Pending finalization became an adopted finished movie")

        var opened: URL?
        let model = VideoLibraryModel(root: folder, openURL: { opened = $0; return true })
        await model.refresh()
        require(await model.open(first.id) && opened == ready)
        let issue = model.items.first { $0.document.state == .failed }!
        opened = nil; require(!(await model.open(issue.id)) && opened == nil && model.error != nil)
        require(await model.rename(first.id, title: "Model title"))
        let modelRestart = VideoLibraryModel(root: folder, openURL: { _ in true })
        await modelRestart.refresh()
        require(modelRestart.items.first { $0.id == first.id }?.document.title == "Model title")
        opened = nil
        await model.showPreview(recording: ready)
        let preview = model.preview!
        require(preview.id == first.id && opened == nil, "Internal preview opened an external app")
        preview.start = 0.1; preview.end = 0.9
        require(!(await model.finishPendingWork()), "Library quit discarded a pending video edit")
        preview.error = nil
        require(await preview.apply())
        require(model.items.first { $0.id == first.id }?.document.trim == VideoTrim(start: 0.1, end: 0.9), "Saved preview did not refresh the library")
        require(await model.finishPendingWork())
        preview.stopPreview(); model.preview = nil
        print("Video library passed: finalized-only opening, thumbnail/duration/dimensions, rename preserves movie bytes/inode/date, restart, failed/interrupted journal, legacy adoption, invalid/newer metadata, backup checksums, new-copy restore, duplicate import, invalid backup atomicity and model opening.")
    }
    static func restart(write: Bool, key: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VideoRestart-\(key)")
        let files = VideoRecordingFiles(root: folder)
        if write {
            let partial = try await files.prepare(availableBytes: 1_000_000_000)
            try await VideoRecordingChecks.movie(at: partial); _ = try await files.finalize(partial)
            let item = try await files.list().items.first!
            try await files.rename(item.id, title: "Persistent synthetic video")
            let unfinished = try await files.prepare(availableBytes: 1_000_000_000)
            try Data("unfinished".utf8).write(to: unfinished)
        } else {
            defer { try? FileManager.default.removeItem(at: folder) }
            let listing = try await files.list()
            let ready = listing.items.first { $0.document.state == .finished }!
            require(ready.document.title == "Persistent synthetic video" && ready.thumbnail != nil)
            _ = try await files.movieURL(ready.id)
            require(listing.items.filter { $0.document.state == .interrupted }.count == 1)
        }
        print("Video process restart \(write ? "write" : "read") passed.")
    }
}

#if VIDEO_LIBRARY_CHECKS
@main struct VideoLibraryRunner {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3 { try await VideoLibraryChecks.restart(write: CommandLine.arguments[1] == "--write", key: CommandLine.arguments[2]) }
        else { try await VideoLibraryChecks.run() }
    }
}
#endif

private func require(_ value: Bool, _ message: String = "Video library check failed", file: StaticString = #fileID, line: UInt = #line) { precondition(value, message, file: file, line: line) }

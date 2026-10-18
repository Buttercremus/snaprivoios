import Foundation
import CryptoKit
import SnagForgeDomain

/// One portable package. Every component is validated in an isolated library before
/// any user library is touched. Restoration is additive with operation-scoped rollback.
actor CompleteBackup {
    struct Entry: Codable { let path: String; let bytes: Int64; let sha256: String }
    struct Manifest: Codable { var version = 1; let createdAt: Date; let sourceLibrary: String; let files: [Entry] }
    struct Counts: Sendable { let images: Int; let videos: Int; let guides: Int }
    private let images: ProjectStore
    private let videos: VideoRecordingFiles
    private let guides: GuideStore
    init(images: ProjectStore, videos: VideoRecordingFiles, guides: GuideStore) {
        self.images = images; self.videos = videos; self.guides = guides
    }
    struct Usage: Sendable { let images: Int64; let videos: Int64; let guides: Int64; let available: Int64? }
    func usage() throws -> Usage {
        func bytes(_ root: URL, excluding: Set<URL> = []) throws -> Int64 {
            guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { return 0 }
            var total: Int64 = 0
            for case let file as URL in iterator {
                if excluding.contains(file) { iterator.skipDescendants(); continue }
                let info = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                if info.isSymbolicLink == true { iterator.skipDescendants(); continue }
                if info.isRegularFile == true { total += Int64(info.fileSize ?? 0) }
            }
            return total
        }
        let imageBytes = try bytes(images.root, excluding: [videos.root, guides.root])
        return try Usage(images: imageBytes, videos: bytes(videos.root), guides: bytes(guides.root),
                         available: images.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage)
    }
    private func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func entries(in root: URL) throws -> [Entry] {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        var traversalError: Error?
        guard let iterator = FileManager.default.enumerator(at: canonicalRoot, includingPropertiesForKeys: keys,
            errorHandler: { _, error in traversalError = error; return false }) else { throw ProjectError.invalidDocument }
        var result: [Entry] = []
        for case let file as URL in iterator {
            let info = try file.resourceValues(forKeys: Set(keys))
            guard info.isSymbolicLink != true else { throw ProjectError.invalidDocument }
            if info.isDirectory == true { continue }
            guard info.isRegularFile == true, let size = info.fileSize else { throw ProjectError.invalidDocument }
            let path = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropFirst(canonicalRoot.pathComponents.count).joined(separator: "/")
            guard path != "complete.json" else { continue }
            guard result.count < 50_000 else { throw ProjectError.documentTooLarge }
            result.append(Entry(path: path, bytes: Int64(size), sha256: try checksum(file)))
        }
        if let traversalError { throw traversalError }
        return result.sorted { $0.path < $1.path }
    }
    func importLegacy(from folder: URL) async throws -> Counts {
        let fm = FileManager.default
        let nested = folder.appendingPathComponent("Data/Library/Application Support")
        let support = fm.fileExists(atPath: nested.path) ? nested : folder
        let imageRoot = support.appendingPathComponent("SnagForge/Projects")
        let videoRoot = support.appendingPathComponent("Snaprivo/VideoRecordings")
        let guideRoot = support.appendingPathComponent("SnagForge/Guides")
        guard [imageRoot, videoRoot, guideRoot].contains(where: { fm.fileExists(atPath: $0.path) }) else { throw ProjectError.invalidDocument }
        let scratch = fm.temporaryDirectory.appendingPathComponent("Snaprivo-Legacy-\(UUID())")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let old = CompleteBackup(images: ProjectStore(root: fm.fileExists(atPath: imageRoot.path) ? imageRoot : scratch.appendingPathComponent("empty-images")), videos: VideoRecordingFiles(root: fm.fileExists(atPath: videoRoot.path) ? videoRoot : scratch.appendingPathComponent("empty-videos")), guides: GuideStore(root: fm.fileExists(atPath: guideRoot.path) ? guideRoot : scratch.appendingPathComponent("empty-guides")))
        let backup = scratch.appendingPathComponent("Legacy.snaprivoall")
        _ = try await old.backup(to: backup)
        return try await restore(from: backup)
    }
    func backup(to target: URL) async throws -> Counts {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { throw CocoaError(.fileWriteFileExists) }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".\(UUID()).complete")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        let count = try await images.backup(to: stage.appendingPathComponent("images"))
        try await videos.backup(to: stage.appendingPathComponent("videos"))
        let folder = stage.appendingPathComponent("guides")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let listing = try await guides.list()
        guard listing.issues.isEmpty else { throw ProjectError.invalidDocument }
        for summary in listing.documents {
            let value = try await guides.load(summary.id).document
            try GuideExporter.validateImages(value)
            try value.encoded().write(to: folder.appendingPathComponent("\(value.id).snaprivoguide"), options: .atomic)
        }
        let all = try entries(in: stage)
        let data = try JSONEncoder().encode(Manifest(createdAt: .now, sourceLibrary: ProjectArchive.hash(Data(images.root.standardizedFileURL.resolvingSymlinksInPath().path.utf8)), files: all))
        guard data.count <= 16_777_216 else { throw ProjectError.documentTooLarge }
        try data.write(to: stage.appendingPathComponent("complete.json"), options: .atomic)
        try fm.moveItem(at: stage, to: target)
        let videoIndex = try JSONDecoder().decode(VideoBackup.self, from: ProjectArchive.readRegularFile(target.appendingPathComponent("videos/manifest.json"), limit: 16_777_216))
        return Counts(images: count, videos: videoIndex.entries.count, guides: listing.documents.count)
    }
    func restore(from source: URL) async throws -> Counts {
        let fm = FileManager.default
        let manifest = try JSONDecoder().decode(Manifest.self, from: ProjectArchive.readRegularFile(source.appendingPathComponent("complete.json"), limit: 16_777_216))
        guard manifest.version == 1 else { throw ProjectError.unsupportedVersion }
        guard manifest.files.count <= 50_000, Set(manifest.files.map(\.path)).count == manifest.files.count else { throw ProjectError.invalidDocument }
        let temporary = fm.temporaryDirectory.appendingPathComponent("Snaprivo-Restore-\(UUID())")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let staged = temporary.appendingPathComponent("source")
        try fm.createDirectory(at: staged, withIntermediateDirectories: false)
        for entry in manifest.files {
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, ["images", "videos", "guides"].contains(String(parts[0])),
                  parts.allSatisfy({ VideoDocument.isSafeFileName(String($0)) }), entry.bytes >= 0 else { throw ProjectError.invalidDocument }
            let folder = source.appendingPathComponent(String(parts[0]))
            let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { throw ProjectError.invalidDocument }
            let file = source.appendingPathComponent(entry.path)
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  Int64(properties.fileSize ?? -1) == entry.bytes else { throw ProjectError.invalidDocument }
            let copy = staged.appendingPathComponent(entry.path)
            try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: copy)
            guard try checksum(copy) == entry.sha256 else { throw ProjectError.invalidDocument }
        }
        for name in ["images", "videos", "guides"] { try fm.createDirectory(at: staged.appendingPathComponent(name), withIntermediateDirectories: true) }
        // Full validation, including image decoding and MP4 media facts, happens here.
        let testImages = ProjectStore(root: temporary.appendingPathComponent("validated-images"))
        _ = try await testImages.restoreBackup(from: staged.appendingPathComponent("images"), thumbnail: WorkspaceModel.archiveThumbnail)
        let testVideos = VideoRecordingFiles(root: temporary.appendingPathComponent("validated-videos"))
        _ = try await testVideos.restore(from: staged.appendingPathComponent("videos"))
        var values: [GuideDocument] = []
        for file in try fm.contentsOfDirectory(at: staged.appendingPathComponent("guides"), includingPropertiesForKeys: nil) {
            guard file.pathExtension == "snaprivoguide" else { throw ProjectError.invalidDocument }
            var value = try GuideDocument.read(file)
            try GuideExporter.validateImages(value)
            value.id = UUID(); value.revision = 0
            values.append(value)
        }
        var imageIDs: [UUID] = [], videoIDs: [UUID] = [], guideIDs: [UUID] = []
        do {
            let mapping = try await images.restoreBackupMapped(from: staged.appendingPathComponent("images"), alwaysCopy: true, thumbnail: WorkspaceModel.archiveThumbnail)
            imageIDs = Array(mapping.values)
            videoIDs = try await videos.restoreIDs(from: staged.appendingPathComponent("videos"))
            let targetLibrary = ProjectArchive.hash(Data(images.root.standardizedFileURL.resolvingSymlinksInPath().path.utf8))
            for var value in values {
                for i in value.steps.indices {
                    if value.steps[i].sourceLibrary == manifest.sourceLibrary,
                       let old = value.steps[i].sourceProjectID, let next = mapping[old] {
                        value.steps[i].sourceProjectID = next; value.steps[i].sourceLibrary = targetLibrary
                    } else { value.steps[i].sourceProjectID = nil; value.steps[i].sourceLibrary = nil }
                }
                try await guides.create(value); guideIDs.append(value.id)
            }
        } catch {
            let original = error
            // Attempt every rollback even when one component cannot be reached.
            var rollbackFailed = false
            if !guideIDs.isEmpty { do { try await guides.removeImported(guideIDs) } catch { rollbackFailed = true } }
            if !videoIDs.isEmpty { do { try await videos.removeImported(videoIDs) } catch { rollbackFailed = true } }
            if !imageIDs.isEmpty { do { try await images.removeImported(imageIDs) } catch { rollbackFailed = true } }
            if rollbackFailed {
                throw NSError(domain: "SnaprivoBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Wiederherstellung unterbrochen. Einige vollständige Kopien können bereits vorhanden sein. Bestehende Inhalte wurden nicht überschrieben.")])
            }
            throw original
        }
        return Counts(images: imageIDs.count, videos: videoIDs.count, guides: guideIDs.count)
    }
}

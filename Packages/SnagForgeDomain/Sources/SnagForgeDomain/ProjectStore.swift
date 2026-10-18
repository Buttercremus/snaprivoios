import Foundation
import Darwin

public struct ProjectLibraryItem: Identifiable, Sendable {
    public let document: ProjectDocument
    public let thumbnail: Data?
    public let recovered: Bool
    public var id: UUID { document.id }
}

public struct LibraryListing: Sendable {
    public let items: [ProjectLibraryItem]
    public let issues: [String]
}

public struct LoadedProject: Sendable {
    public let document: ProjectDocument
    public let original: Data
    public let generation: Int
    public let recovered: Bool
}

/// Serializes all file writes away from the UI. A revision becomes current only after its
/// complete JSON file exists. The immutable original is never rewritten by annotation edits.
public actor ProjectStore {
    private static let maximumDocumentBytes = 32_000_000
    public nonisolated let root: URL
    private let files = FileManager.default

    private struct Manifest: Codable {
        var schemaVersion = 1
        let id: UUID
        let generation: Int
        let previous: Int?
    }

    public init(root: URL) { self.root = root }
    // Multiple local builds may share a container. Coordinate their read/check/commit sequence.
    private func withLibraryLock<T>(_ operation: () throws -> T) throws -> T {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = Darwin.open(root.appendingPathComponent(".library-lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func package(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("snagforge") }
    private func revisionURL(_ generation: Int, in package: URL) -> URL {
        package.appendingPathComponent("Revisions/\(generation).json")
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func encodeDocument(_ value: ProjectDocument) throws -> Data {
        var json = try JSONSerialization.jsonObject(with: encode(value)) as! [String: Any]
        var objects = json["objects"] as! [[String: Any]]
        for i in objects.indices {
            if var asset = objects[i]["imageAsset"] as? [String: Any] { asset.removeValue(forKey: "png"); objects[i]["imageAsset"] = asset }
        }
        json["objects"] = objects
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        guard data.count <= Self.maximumDocumentBytes else { throw ProjectError.documentTooLarge }
        return data
    }
    private func writeAssets(_ document: ProjectDocument, in folder: URL) throws {
        let directory = folder.appendingPathComponent("Assets")
        for asset in document.objects.compactMap(\.imageAsset) {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(asset.digest + ".png")
            if files.fileExists(atPath: url.path) {
                guard try ProjectArchive.readRegularFile(url, limit: 8_000_000) == asset.png else { throw ProjectError.invalidDocument }
            } else { try asset.png.write(to: url, options: .atomic) }
        }
    }
    private func hydrateAssets(_ data: Data, in folder: URL) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var objects = json["objects"] as? [[String: Any]] else { throw ProjectError.invalidDocument }
        guard let version = json["schemaVersion"] as? Int, (1...ProjectDocument.currentVersion).contains(version) else { throw ProjectError.unsupportedVersion }
        var total = 0
        for i in objects.indices {
            if var asset = objects[i]["imageAsset"] as? [String: Any], asset["png"] == nil {
                guard let digest = asset["digest"] as? String, digest.count == 64,
                      digest.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw ProjectError.invalidDocument }
                let png = try ProjectArchive.readRegularFile(folder.appendingPathComponent("Assets/" + digest + ".png"), limit: 8_000_000)
                total += png.count; guard total <= 16_000_000 else { throw ProjectError.documentTooLarge }
                asset["png"] = png.base64EncodedString(); objects[i]["imageAsset"] = asset
            }
        }
        json["objects"] = objects
        return try JSONSerialization.data(withJSONObject: json)
    }
    private func manifest(in package: URL) throws -> Manifest {
        let value = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        guard value.schemaVersion == 1 else { throw ProjectError.unsupportedVersion }
        guard value.generation >= 0, value.generation < Int.max - 1,
              value.previous == nil || (value.previous! >= 0 && value.previous! < value.generation) else { throw ProjectError.invalidDocument }
        return value
    }
    private func document(in package: URL, manifest: Manifest) throws -> (ProjectDocument, Bool) {
        func read(_ generation: Int) throws -> ProjectDocument {
            let url = revisionURL(generation, in: package)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumDocumentBytes else { throw ProjectError.documentTooLarge }
            let value = try ProjectDocument.decode(hydrateAssets(Data(contentsOf: url), in: package))
            guard value.id == manifest.id, value.revision == generation else { throw ProjectError.invalidDocument }
            return value
        }
        do { return (try read(manifest.generation), false) }
        catch ProjectError.unsupportedVersion { throw ProjectError.unsupportedVersion }
        catch {
            guard let previous = manifest.previous else { throw error }
            return (try read(previous), true)
        }
    }

    public func create(_ document: ProjectDocument, original: Data, thumbnail: Data?) throws {
        try withLibraryLock { try createUnlocked(document, original: original, thumbnail: thumbnail) }
    }
    private func createUnlocked(_ document: ProjectDocument, original: Data, thumbnail: Data?) throws {
        let document = try document.validated()
        guard document.revision == 0, !original.isEmpty else { throw ProjectError.invalidDocument }
        let encoded = try encodeDocument(document)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".creating-\(UUID().uuidString)")
        try files.createDirectory(at: staging.appendingPathComponent("Revisions"), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        try writeAssets(document, in: staging)
        try original.write(to: staging.appendingPathComponent("original.png"), options: .atomic)
        try encoded.write(to: revisionURL(0, in: staging), options: .atomic)
        try encode(Manifest(id: document.id, generation: 0, previous: nil)).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        if let thumbnail { try? thumbnail.write(to: staging.appendingPathComponent("thumbnail.png"), options: .atomic) }
        try files.moveItem(at: staging, to: package(document.id))
    }

    public func save(_ document: ProjectDocument, expectedGeneration: Int, thumbnail: Data?) throws {
        try withLibraryLock { try saveUnlocked(document, expectedGeneration: expectedGeneration, thumbnail: thumbnail) }
    }
    private func saveUnlocked(_ document: ProjectDocument, expectedGeneration: Int, thumbnail: Data?) throws {
        let document = try document.validated(), folder = package(document.id)
        let encoded = try encodeDocument(document)
        let old = try manifest(in: folder)
        guard old.id == document.id else { throw ProjectError.invalidDocument }
        guard old.generation == expectedGeneration, document.revision > old.generation else { throw ProjectError.staleRevision }
        // Preserve the last readable revision when recovering a broken current revision.
        let (readable, _) = try self.document(in: folder, manifest: old)
        try writeAssets(document, in: folder)
        try encoded.write(to: revisionURL(document.revision, in: folder), options: .atomic)
        let next = Manifest(id: document.id, generation: document.revision, previous: readable.revision)
        try encode(next).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        // Thumbnail is only a disposable cache; it cannot invalidate a committed project.
        if let thumbnail { try? thumbnail.write(to: folder.appendingPathComponent("thumbnail.png"), options: .atomic) }
        if let revisions = try? files.contentsOfDirectory(at: folder.appendingPathComponent("Revisions"), includingPropertiesForKeys: nil) {
            let keep = Set(["\(document.revision).json", "\(readable.revision).json"])
            for url in revisions where !keep.contains(url.lastPathComponent) { try? files.removeItem(at: url) }
        }
    }

    /// Change only metadata under the same cross-process lock as editor saves.
    public func updateMetadata(_ id: UUID, title: String? = nil, favorite: Bool? = nil, tags: [String]? = nil, collections: [String]? = nil) throws {
        try withLibraryLock {
            let folder = package(id), current = try manifest(in: folder)
            var (document, _) = try self.document(in: folder, manifest: current)
            guard document.id == id else { throw ProjectError.invalidDocument }
            let before = document
            if let title {
                let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 1024 else { throw ProjectError.invalidDocument }
                document.title = title
            }
            if let favorite { document.isFavorite = favorite }
            if let tags { document.tags = try ProjectOrganization.normalized(tags, limit: ProjectOrganization.maximumTags) }
            if let collections { document.collections = try ProjectOrganization.normalized(collections, limit: ProjectOrganization.maximumCollections) }
            guard document != before else { return }
            document.revision = current.generation + 1; document.modifiedAt = .now
            try saveUnlocked(document, expectedGeneration: current.generation, thumbnail: nil)
        }
    }

    public func load(_ id: UUID) throws -> LoadedProject {
        try withLibraryLock { try loadUnlocked(id) }
    }
    public func readDocument(_ id: UUID) throws -> ProjectDocument {
        try withLibraryLock {
            let folder = package(id), manifest = try manifest(in: folder)
            guard manifest.id == id else { throw ProjectError.invalidDocument }
            return try document(in: folder, manifest: manifest).0
        }
    }
    private func loadUnlocked(_ id: UUID) throws -> LoadedProject {
        let folder = package(id), manifest = try manifest(in: folder)
        guard manifest.id == id else { throw ProjectError.invalidDocument }
        let (document, recovered) = try self.document(in: folder, manifest: manifest)
        let url = folder.appendingPathComponent("original.png")
        guard files.fileExists(atPath: url.path) else { throw ProjectError.missingOriginal }
        return LoadedProject(document: document, original: try Data(contentsOf: url), generation: manifest.generation, recovered: recovered)
    }

    public func exportProject(_ id: UUID, to destination: URL) throws {
        try withLibraryLock {
            let loaded = try loadUnlocked(id)
            let data = try ProjectArchive(document: loaded.document, original: loaded.original).encoded()
            try data.write(to: destination, options: .atomic)
        }
    }

    /// Always import a separate project; imports never overwrite active or trashed work.
    public func importProject(_ archive: ProjectArchive, thumbnail: Data?) throws -> UUID {
        try withLibraryLock {
            let document = try archive.validatedDocument()
            let id = UUID()
            try createUnlocked(ProjectArchive.copy(document, id: id), original: archive.original, thumbnail: thumbnail)
            return id
        }
    }

    public func backup(to destination: URL) throws -> Int {
        try withLibraryLock {
            guard !files.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
            let parent = destination.deletingLastPathComponent()
            let staging = parent.appendingPathComponent(".snaprivo-backup-" + UUID().uuidString)
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? files.removeItem(at: staging) }
            var entries: [LibraryBackupIndex.Entry] = []
            for (directory, trashed) in [(root, false), (trashRoot, true)] {
                guard files.fileExists(atPath: directory.path) else { continue }
                let listing = try listUnlocked(in: directory)
                // Never report an incomplete backup as successful.
                guard listing.issues.isEmpty else { throw ProjectError.invalidDocument }
                for item in listing.items {
                    let folder = directory.appendingPathComponent(item.id.uuidString + ".snagforge")
                    let original = try Data(contentsOf: folder.appendingPathComponent("original.png"))
                    let data = try ProjectArchive(document: item.document, original: original).encoded()
                    let file = UUID().uuidString + ".snaprivo"
                    try data.write(to: staging.appendingPathComponent(file), options: .atomic)
                    entries.append(.init(file: file, isTrashed: trashed, digest: ProjectArchive.hash(data)))
                }
            }
            try encode(LibraryBackupIndex(entries: entries)).write(to: staging.appendingPathComponent("index.json"), options: .atomic)
            try movePackage(from: staging, to: destination)
            return entries.count
        }
    }

    /// Validate and stage everything before publishing. Existing IDs are preserved unless occupied.
    /// The caller validates image decoding and produces a fresh thumbnail for each entry.
    public func restoreBackup(from source: URL, thumbnail: @Sendable (ProjectArchive) throws -> Data) throws -> Int {
        try withLibraryLock {
            let index = try LibraryBackupIndex.read(from: source)
            let staging = root.appendingPathComponent(".restoring-" + UUID().uuidString)
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? files.removeItem(at: staging) }
            var destinations: [(URL, URL)] = []
            var allocated = Set<UUID>()
            for entry in index.entries {
                let data = try ProjectArchive.readRegularFile(source.appendingPathComponent(entry.file), limit: ProjectArchive.maximumBytes)
                guard ProjectArchive.hash(data) == entry.digest else { throw ProjectError.invalidDocument }
                let archive = try PropertyListDecoder().decode(ProjectArchive.self, from: data)
                let document = try archive.validatedDocument()
                var id = document.id
                if allocated.contains(id) || files.fileExists(atPath: package(id).path) || files.fileExists(atPath: trashedPackage(id).path) { id = UUID() }
                allocated.insert(id)
                let folder = staging.appendingPathComponent(id.uuidString + ".snagforge")
                try files.createDirectory(at: folder.appendingPathComponent("Revisions"), withIntermediateDirectories: true)
                try archive.original.write(to: folder.appendingPathComponent("original.png"))
                try writeAssets(document, in: folder)
                try encodeDocument(ProjectArchive.copy(document, id: id)).write(to: revisionURL(0, in: folder))
                try encode(Manifest(id: id, generation: 0, previous: nil)).write(to: folder.appendingPathComponent("manifest.json"))
                try thumbnail(archive).write(to: folder.appendingPathComponent("thumbnail.png"))
                destinations.append((folder, entry.isTrashed ? trashedPackage(id) : package(id)))
            }
            try files.createDirectory(at: trashRoot, withIntermediateDirectories: true)
            var published: [(URL, URL)] = []
            do {
                for (folder, target) in destinations { try movePackage(from: folder, to: target); published.append((folder, target)) }
            } catch {
                // Roll back this operation only; no pre-existing package is ever touched.
                for (folder, target) in published.reversed() { try? movePackage(from: target, to: folder) }
                throw error
            }
            return destinations.count
        }
    }

    private var trashRoot: URL { root.appendingPathComponent(".Trash", isDirectory: true) }
    private func trashedPackage(_ id: UUID) -> URL { trashRoot.appendingPathComponent(id.uuidString).appendingPathExtension("snagforge") }
    public func moveToTrash(_ id: UUID) throws {
        try withLibraryLock {
            try files.createDirectory(at: trashRoot, withIntermediateDirectories: true)
            try movePackage(from: package(id), to: trashedPackage(id))
        }
    }
    public func restore(_ id: UUID) throws {
        try withLibraryLock { try movePackage(from: trashedPackage(id), to: package(id)) }
    }
    private func movePackage(from source: URL, to destination: URL) throws {
        guard !files.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        // Both directories live on the same volume. A single rename keeps the whole package intact.
        guard Darwin.rename(source.path, destination.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    public func permanentlyDelete(_ id: UUID) throws {
        try withLibraryLock {
            // Only trash entries may be destroyed. A durable deletion intent permits retry after interruption.
            let source = trashedPackage(id), pending = trashRoot.appendingPathComponent(id.uuidString + ".deleting")
            if files.fileExists(atPath: source.path) { try movePackage(from: source, to: pending) }
            guard files.fileExists(atPath: pending.path) else { throw CocoaError(.fileNoSuchFile) }
            try files.removeItem(at: pending)
        }
    }
    public func listTrash() throws -> LibraryListing {
        try withLibraryLock {
            guard files.fileExists(atPath: trashRoot.path) else { return LibraryListing(items: [], issues: []) }
            var issues: [String] = []
            for entry in try files.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil) where entry.pathExtension == "deleting" {
                guard UUID(uuidString: entry.deletingPathExtension().lastPathComponent) != nil else { continue }
                do { try files.removeItem(at: entry) }
                catch { issues.append(String(localized: "Endgültiges Löschen noch nicht abgeschlossen: \(entry.lastPathComponent): \(error.localizedDescription)", bundle: DomainLocalization.bundle)) }
            }
            let listing = try listUnlocked(in: trashRoot)
            return LibraryListing(items: listing.items, issues: issues + listing.issues)
        }
    }

    public func list() throws -> LibraryListing {
        guard files.fileExists(atPath: root.path) else { return LibraryListing(items: [], issues: []) }
        return try withLibraryLock { try listUnlocked() }
    }
    /// Copy, verify, then atomically publish a new library without changing the source.
    /// An existing destination is never overwritten, even when empty.
    public func copyLibrary(to destination: URL) throws -> Int {
        try withLibraryLock {
            let source = root.standardizedFileURL.resolvingSymlinksInPath()
            let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
            guard destination.isFileURL, destination != source,
                  !destination.path.hasPrefix(source.path + "/"), !source.path.hasPrefix(destination.path + "/") else {
                throw ProjectError.invalidDocument
            }
            guard !files.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
            let active = try listUnlocked(), trash = try listUnlocked(in: trashRoot)
            guard active.issues.isEmpty, trash.issues.isEmpty else { throw ProjectError.invalidDocument }
            let staging = destination.deletingLastPathComponent().appendingPathComponent(".snaprivo-library-\(UUID())", isDirectory: true)
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? files.removeItem(at: staging) }
            for entry in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                guard entry.pathExtension == "snagforge" || entry.lastPathComponent == ".Trash" else { continue }
                let copy = staging.appendingPathComponent(entry.lastPathComponent)
                try files.copyItem(at: entry, to: copy)
                try verifyCopy(entry, copy)
            }
            try files.moveItem(at: staging, to: destination)
            return active.items.count + trash.items.count
        }
    }
    private func verifyCopy(_ source: URL, _ copy: URL, depth: Int = 0) throws {
        guard depth < 32 else { throw ProjectError.invalidDocument }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ProjectError.invalidDocument }
        if values.isDirectory == true {
            let children = try files.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            let copied = try files.contentsOfDirectory(at: copy, includingPropertiesForKeys: nil)
            guard Set(children.map(\.lastPathComponent)) == Set(copied.map(\.lastPathComponent)) else { throw ProjectError.invalidDocument }
            for child in children { try verifyCopy(child, copy.appendingPathComponent(child.lastPathComponent), depth: depth + 1) }
        } else {
            guard values.isRegularFile == true, files.contentsEqual(atPath: source.path, andPath: copy.path) else { throw ProjectError.invalidDocument }
        }
    }
    private func listUnlocked(in directory: URL? = nil) throws -> LibraryListing {
        let directory = directory ?? root
        guard files.fileExists(atPath: directory.path) else { return LibraryListing(items: [], issues: []) }
        let folders = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var items: [ProjectLibraryItem] = [], issues: [String] = []
        for folder in folders where folder.pathExtension == "snagforge" {
            do {
                let manifest = try manifest(in: folder)
                guard folder.deletingPathExtension().lastPathComponent == manifest.id.uuidString else { throw ProjectError.invalidDocument }
                let (document, recovered) = try document(in: folder, manifest: manifest)
                guard files.fileExists(atPath: folder.appendingPathComponent("original.png").path) else { throw ProjectError.missingOriginal }
                // A recovered document must not show a thumbnail from the broken revision.
                let thumbnail = recovered ? nil : try? Data(contentsOf: folder.appendingPathComponent("thumbnail.png"))
                items.append(ProjectLibraryItem(document: document, thumbnail: thumbnail, recovered: recovered))
            } catch { issues.append("\(folder.lastPathComponent): \(error.localizedDescription)") }
        }
        return LibraryListing(items: items.sorted { $0.document.modifiedAt > $1.document.modifiedAt }, issues: issues)
    }
}

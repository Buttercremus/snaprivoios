import Foundation
import Darwin

public struct GuideSummary: Identifiable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let modifiedAt: Date
    public let stepCount: Int
    public let trashedAt: Date?
    public init(_ value: GuideDocument, trashedAt: Date? = nil) {
        id = value.id; title = value.title; modifiedAt = value.modifiedAt; stepCount = value.steps.count; self.trashedAt = trashedAt
    }
}
public struct GuideListing: Sendable {
    public let documents: [GuideSummary]
    public let issues: [String]
}

/// Local manifests reference immutable PNGs. Portable documents still embed every image.
/// Both durable generations and trash markers remain protected by the same process lock.
public actor GuideStore {
    public nonisolated let root: URL
    private let files = FileManager.default
    private struct Stored: Codable {
        var storageVersion = 1
        var document: GuideDocument
        var digests: [String]
    }
    private struct Generation { var document: GuideDocument; var data: Data; var digests: [String]? }
    private struct TrashMarker: Codable { let id: UUID; let date: Date }
    private var digestCache: [UUID: (Data, String)] = [:]
    public init(root: URL) { self.root = root }
    private func url(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("snaprivoguide") }
    private func previous(_ id: UUID) -> URL { url(id).appendingPathExtension("previous") }
    private func marker(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("trashed") }
    private func assets(_ id: UUID) -> URL { root.appendingPathComponent(".assets", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true) }
    private func directory(_ path: URL, create: Bool) throws {
        if create { try files.createDirectory(at: path, withIntermediateDirectories: true) }
        let info = try path.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw ProjectError.invalidDocument }
    }
    private func checkedAssets(_ id: UUID, create: Bool) throws -> URL {
        try directory(root.appendingPathComponent(".assets"), create: create)
        let path = assets(id); try directory(path, create: create); return path
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = Darwin.open(root.appendingPathComponent(".guide-lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        // A competing live app must not leave save/quit waiting indefinitely.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY)) }
            Thread.sleep(forTimeInterval: 0.02)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
    private func generation(_ path: URL, id: UUID) throws -> Generation {
        let data = try ProjectArchive.readRegularFile(path, limit: GuideDocument.maximumBytes)
        let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        if dictionary?["storageVersion"] != nil {
            let stored = try PropertyListDecoder().decode(Stored.self, from: data)
            guard stored.storageVersion == 1 else { throw ProjectError.unsupportedVersion }
            let value = try stored.document.validatedMetadata()
            guard value.id == id, value.steps.allSatisfy({ $0.png.isEmpty }), stored.digests.count == value.steps.count,
                  stored.digests.allSatisfy({ $0.count == 64 && $0.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) } }) else { throw ProjectError.invalidDocument }
            return Generation(document: value, data: data, digests: stored.digests)
        }
        let value = try PropertyListDecoder().decode(GuideDocument.self, from: data).validated()
        guard value.id == id else { throw ProjectError.invalidDocument }
        return Generation(document: value, data: data, digests: nil)
    }
    private func hydrate(_ generation: Generation) throws -> GuideDocument {
        var value = generation.document
        var nextCache: [UUID: (Data, String)] = [:]
        if let digests = generation.digests, !digests.isEmpty {
            let folder = try checkedAssets(value.id, create: false)
            var total = 0
            var decoded: [String: Data] = [:]
            for i in value.steps.indices {
                try Task.checkCancellation()
                let data: Data
                if let cached = decoded[digests[i]] { data = cached }
                else {
                    data = try ProjectArchive.readRegularFile(folder.appendingPathComponent(digests[i] + ".png"), limit: 32_000_000)
                    guard ProjectArchive.hash(data) == digests[i] else { throw ProjectError.invalidDocument }
                    decoded[digests[i]] = data
                }
                total += data.count
                guard total <= GuideDocument.maximumBytes - 8_000_000 else { throw ProjectError.fileTooLarge }
                value.steps[i].png = data
                nextCache[value.steps[i].id] = (data, digests[i])
            }
        }
        let validated = try value.validated(); digestCache = nextCache
        return validated
    }
    private func loadGeneration(_ id: UUID, hydrateImages: Bool) throws -> (Generation, Bool) {
        do {
            let current = try generation(url(id), id: id)
            if hydrateImages { _ = try hydrate(current) }
            return (current, false)
        } catch ProjectError.unsupportedVersion { throw ProjectError.unsupportedVersion }
        catch {
            let old = try generation(previous(id), id: id)
            if hydrateImages { _ = try hydrate(old) }
            return (old, true)
        }
    }
    private func trashDate(_ id: UUID) throws -> Date? {
        guard files.fileExists(atPath: marker(id).path) else { return nil }
        let value = try PropertyListDecoder().decode(TrashMarker.self, from: ProjectArchive.readRegularFile(marker(id), limit: 4096))
        guard value.id == id, value.date.timeIntervalSince1970.isFinite else { throw ProjectError.invalidDocument }
        return value.date
    }
    public func load(_ id: UUID, includingTrashed: Bool = false) throws -> (document: GuideDocument, recovered: Bool) {
        try locked {
            let removed = try trashDate(id)
            guard includingTrashed || removed == nil else { throw ProjectError.invalidDocument }
            // Decode each generation once; failed image validation may recover the prior one.
            do { return (try hydrate(generation(url(id), id: id)), false) }
            catch ProjectError.unsupportedVersion { throw ProjectError.unsupportedVersion }
            catch { return (try hydrate(generation(previous(id), id: id)), true) }
        }
    }
    public func list() throws -> GuideListing { try listing(trashed: false) }
    public func listTrash() throws -> GuideListing { try listing(trashed: true) }
    private func listing(trashed: Bool) throws -> GuideListing {
        try locked {
            var documents: [GuideSummary] = [], issues: [String] = []
            for file in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "snaprivoguide" {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
                do {
                    let date = try trashDate(id)
                    guard (date != nil) == trashed else { continue }
                    let value = try loadGeneration(id, hydrateImages: false).0.document
                    documents.append(GuideSummary(value, trashedAt: date))
                } catch { issues.append("\(file.lastPathComponent): \(error.localizedDescription)") }
            }
            return GuideListing(documents: documents.sorted { ($0.trashedAt ?? $0.modifiedAt) > ($1.trashedAt ?? $1.modifiedAt) }, issues: issues)
        }
    }
    /// Reads text from local manifests without hydrating image assets or changing the image cache.
    public func search(_ query: String) throws -> [GuideSearchMatch] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try locked {
            var values: [GuideDocument] = []
            for file in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "snaprivoguide" {
                try Task.checkCancellation()
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      (try? trashDate(id)) == nil,
                      let value = try? loadGeneration(id, hydrateImages: false).0.document else { continue }
                // A malformed trash marker must not expose a trashed guide in search.
                guard !files.fileExists(atPath: marker(id).path) else { continue }
                values.append(value)
            }
            return values.sorted { $0.modifiedAt > $1.modifiedAt }.flatMap { GuideSearchMatch.matches(in: $0, query: query) }
        }
    }
    private func storageData(_ document: GuideDocument) throws -> Data {
        var value = try document.validated()
        var digests: [String] = []
        let folder = try checkedAssets(value.id, create: true)
        var nextCache: [UUID: (Data, String)] = [:]
        for i in value.steps.indices {
            try Task.checkCancellation()
            let step = value.steps[i]
            let cached = digestCache[step.id]
            let digest = cached?.0 == step.png ? cached!.1 : ProjectArchive.hash(step.png)
            let file = folder.appendingPathComponent(digest + ".png")
            if files.fileExists(atPath: file.path) {
                // The filename is content-addressed, but a damaged file can still have
                // the same length. Read the opened regular file and repair only when
                // its digest is wrong; healthy assets are not rewritten on autosave.
                let existing = try ProjectArchive.readRegularFile(file, limit: 32_000_000)
                if ProjectArchive.hash(existing) != digest {
                    try step.png.write(to: file, options: .atomic)
                }
            } else {
                try step.png.write(to: file, options: .atomic)
            }
            nextCache[step.id] = (step.png, digest); digests.append(digest); value.steps[i].png = Data()
        }
        digestCache = nextCache
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(Stored(document: value, digests: digests))
        guard data.count <= 8_000_000 else { throw ProjectError.documentTooLarge }
        return data
    }
    public func create(_ document: GuideDocument) throws {
        try locked {
            guard document.revision == 0, !files.fileExists(atPath: url(document.id).path), !files.fileExists(atPath: marker(document.id).path) else { throw ProjectError.staleRevision }
            try storageData(document).write(to: url(document.id), options: .atomic)
        }
    }
    public func moveToTrash(_ id: UUID, expectedRevision: Int) throws {
        try locked {
            let value = try loadGeneration(id, hydrateImages: false).0.document
            guard value.revision == expectedRevision, try trashDate(id) == nil else { throw ProjectError.staleRevision }
            try PropertyListEncoder().encode(TrashMarker(id: id, date: .now)).write(to: marker(id), options: .atomic)
        }
    }
    public func restore(_ id: UUID) throws {
        try locked {
            guard try trashDate(id) != nil else { throw ProjectError.invalidDocument }
            _ = try loadGeneration(id, hydrateImages: true)
            try files.removeItem(at: marker(id))
        }
    }
    public func permanentlyDelete(_ id: UUID) throws {
        try locked {
            guard try trashDate(id) != nil else { throw ProjectError.invalidDocument }
            try remove(id)
        }
    }
    private func remove(_ id: UUID) throws {
        if files.fileExists(atPath: assets(id).path) { _ = try checkedAssets(id, create: false) }
        for file in [previous(id), url(id), assets(id), marker(id)] where files.fileExists(atPath: file.path) { try files.removeItem(at: file) }
        digestCache.removeAll()
    }
    public func removeImported(_ ids: [UUID]) throws { try locked { for id in ids { try remove(id) } } }
    public func save(_ document: GuideDocument, expectedRevision: Int) throws -> GuideDocument {
        try locked {
            guard try trashDate(document.id) == nil else { throw ProjectError.staleRevision }
            let current = try loadGeneration(document.id, hydrateImages: false).0
            guard current.document.revision == expectedRevision, document.revision == expectedRevision else { throw ProjectError.staleRevision }
            var next = document; next.revision += 1; next.modifiedAt = .now
            let bytes = try storageData(next)
            try current.data.write(to: previous(document.id), options: .atomic)
            try bytes.write(to: url(document.id), options: .atomic)
            // Only assets referenced by either durable generation must remain on disk.
            let retained = Set((current.digests ?? []) + (try PropertyListDecoder().decode(Stored.self, from: bytes)).digests)
            if let folder = try? checkedAssets(document.id, create: false), let assets = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                for file in assets where file.pathExtension == "png" && !retained.contains(file.deletingPathExtension().lastPathComponent) { try? files.removeItem(at: file) }
            }
            return next
        }
    }
}

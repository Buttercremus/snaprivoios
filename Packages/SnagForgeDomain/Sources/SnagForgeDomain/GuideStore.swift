import Foundation
import Darwin

public struct GuideSummary: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let modifiedAt: Date
    public let stepCount: Int
    public init(_ value: GuideDocument) {
        id = value.id; title = value.title; modifiedAt = value.modifiedAt; stepCount = value.steps.count
    }
}
public struct GuideListing: Sendable {
    public let documents: [GuideSummary]
    public let issues: [String]
}

/// Standalone working documents, separate from the image-project library. Atomic generations
/// preserve a readable previous save; flock prevents competing app processes losing edits.
public actor GuideStore {
    public nonisolated let root: URL
    public init(root: URL) { self.root = root }
    private func url(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("snaprivoguide") }
    private func previous(_ id: UUID) -> URL { url(id).appendingPathExtension("previous") }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = Darwin.open(root.appendingPathComponent(".guide-lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
    private func loadUnlocked(_ id: UUID) throws -> (document: GuideDocument, recovered: Bool) {
        do {
            let value = try GuideDocument.read(url(id))
            guard value.id == id else { throw ProjectError.invalidDocument }
            return (value, false)
        } catch ProjectError.unsupportedVersion { throw ProjectError.unsupportedVersion }
        catch {
            let value = try GuideDocument.read(previous(id))
            guard value.id == id else { throw ProjectError.invalidDocument }
            return (value, true)
        }
    }
    public func load(_ id: UUID) throws -> (document: GuideDocument, recovered: Bool) { try locked { try loadUnlocked(id) } }
    public func list() throws -> GuideListing {
        try locked {
            var documents: [GuideSummary] = [], issues: [String] = []
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "snaprivoguide" {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
                do {
                    let value = try loadUnlocked(id).document
                    documents.append(GuideSummary(value))
                }
                catch { issues.append("\(file.lastPathComponent): \(error.localizedDescription)") }
            }
            return GuideListing(documents: documents.sorted { $0.modifiedAt > $1.modifiedAt }, issues: issues)
        }
    }
    public func create(_ document: GuideDocument) throws {
        try locked {
            guard document.revision == 0, !FileManager.default.fileExists(atPath: url(document.id).path) else { throw ProjectError.staleRevision }
            try document.encoded().write(to: url(document.id), options: .atomic)
        }
    }
    public func save(_ document: GuideDocument, expectedRevision: Int) throws -> GuideDocument {
        try locked {
            let current = try loadUnlocked(document.id).document
            guard current.revision == expectedRevision, document.revision == expectedRevision else { throw ProjectError.staleRevision }
            var next = document; next.revision += 1; next.modifiedAt = .now
            let bytes = try next.encoded()
            try current.encoded().write(to: previous(document.id), options: .atomic)
            try bytes.write(to: url(document.id), options: .atomic)
            return next
        }
    }
}

import Foundation

public enum VideoState: String, Codable, Sendable { case recording, finished, interrupted, failed }

/// Small sidecar only. The original movie is immutable after finalization.
public struct VideoDocument: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion = 3
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var fileName: String
    public var state: VideoState
    public var duration: Double?
    public var pixelSize: PixelSize?
    public var hasAudio: Bool
    public var failure: String?
    public var trim: VideoTrim?
    public var revision: Int = 0
    public var trashedAt: Date?
    public var effectiveTrim: VideoTrim { trim ?? VideoTrim(start: 0, end: duration ?? 0) }
    private enum CodingKeys: String, CodingKey {
        case trashedAt, schemaVersion, id, title, createdAt, modifiedAt, fileName, state, duration, pixelSize, hasAudio, failure, trim, revision
    }

    public init(id: UUID = UUID(), title: String, fileName: String, state: VideoState = .recording,
                createdAt: Date = .now, duration: Double? = nil, pixelSize: PixelSize? = nil, hasAudio: Bool = false) {
        self.id = id; self.title = title; self.fileName = fileName; self.state = state
        self.createdAt = createdAt; modifiedAt = createdAt
        self.duration = duration; self.pixelSize = pixelSize; self.hasAudio = hasAudio
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard (1...3).contains(version) else { throw ProjectError.unsupportedVersion }
        id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt); modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        fileName = try c.decode(String.self, forKey: .fileName); state = try c.decode(VideoState.self, forKey: .state)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration); pixelSize = try c.decodeIfPresent(PixelSize.self, forKey: .pixelSize)
        hasAudio = try c.decode(Bool.self, forKey: .hasAudio); failure = try c.decodeIfPresent(String.self, forKey: .failure)
        trim = try c.decodeIfPresent(VideoTrim.self, forKey: .trim)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        trashedAt = try c.decodeIfPresent(Date.self, forKey: .trashedAt)
        guard version != 1 || (trim == nil && revision == 0) else { throw ProjectError.invalidDocument }
    }
    public func validated() throws -> Self {
        guard schemaVersion == 3 else { throw ProjectError.unsupportedVersion }
        guard trashedAt?.timeIntervalSince1970.isFinite != false else { throw ProjectError.invalidDocument }
        guard (0..<Int.max).contains(revision) else { throw ProjectError.invalidDocument }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 1024, title.utf8.count <= 65_536,
              Self.isSafeFileName(fileName), fileName.lowercased().hasSuffix(".mp4"),
              createdAt.timeIntervalSince1970.isFinite, modifiedAt.timeIntervalSince1970.isFinite,
              failure.map({ $0.utf8.count <= 4096 }) ?? true else { throw ProjectError.invalidDocument }
        if let duration { guard duration.isFinite, duration > 0, duration <= 31_536_000 else { throw ProjectError.invalidDocument } }
        if let size = pixelSize { guard size.width <= 32768, size.height <= 32768 else { throw ProjectError.invalidDocument } }
        if state == .finished {
            guard duration != nil, pixelSize != nil, !fileName.hasPrefix(".") else { throw ProjectError.invalidDocument }
        }
        if let trim {
            guard state == .finished, let duration else { throw ProjectError.invalidDocument }
            _ = try trim.validated(duration: duration)
        }
        return self
    }
    public static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.contains(":" ) && !name.contains("\0")
    }
}

public struct VideoBackup: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let document: VideoDocument
        public let sha256: String
        public var hasFile: Bool?
        public init(document: VideoDocument, sha256: String, hasFile: Bool = true) { self.document = document; self.sha256 = sha256; self.hasFile = hasFile }
    }
    public var schemaVersion = 2
    public var entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }
    public func validated() throws -> Self {
        guard (1...2).contains(schemaVersion) else { throw ProjectError.unsupportedVersion }
        guard entries.count <= 10_000, Set(entries.map { $0.document.id }).count == entries.count,
              Set(entries.map { $0.document.fileName.lowercased() }).count == entries.count else { throw ProjectError.invalidDocument }
        for entry in entries {
            _ = try entry.document.validated()
            guard schemaVersion >= 2 || (entry.document.state == .finished && entry.document.trashedAt == nil) else { throw ProjectError.invalidDocument }
            guard entry.document.state != .recording else { throw ProjectError.invalidDocument }
            if entry.hasFile != false {
                guard entry.sha256.count == 64, entry.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw ProjectError.invalidDocument }
            } else {
                guard entry.document.state != .finished, entry.sha256.isEmpty else { throw ProjectError.invalidDocument }
            }
        }
        return self
    }
}

import Foundation
import CryptoKit
import Darwin

/// A portable, self-contained project. Previous revisions are deliberately not exported.
public struct ProjectArchive: Codable, Sendable {
    public let format: String
    public let version: Int
    public let document: Data
    public let original: Data
    public let digest: String
    public static let maximumBytes = 550_000_000
    public static let maximumOriginalBytes = 512_000_000
    public static let maximumThumbnailBytes = 8_000_000

    public init(document: ProjectDocument, original: Data) throws {
        format = "com.snaprivo.project"; version = 1
        self.document = try JSONEncoder().encode(document.validated())
        self.original = original
        digest = Self.hash(original)
        _ = try validatedDocument()
    }
    public func validatedDocument() throws -> ProjectDocument {
        guard format == "com.snaprivo.project" else { throw ProjectError.invalidDocument }
        guard version == 1 else { throw ProjectError.unsupportedVersion }
        guard document.count <= 32_000_000 else { throw ProjectError.documentTooLarge }
        guard original.count <= Self.maximumOriginalBytes else { throw ProjectError.fileTooLarge }
        let value = try ProjectDocument.decode(document)
        guard digest == Self.hash(original), Self.pngSize(original) == value.pixelSize else { throw ProjectError.invalidDocument }
        return value
    }
    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        return try encoder.encode(self)
    }
    public static func read(from url: URL) throws -> Self {
        let data = try readRegularFile(url, limit: maximumBytes)
        let archive: Self
        do { archive = try PropertyListDecoder().decode(Self.self, from: data) }
        catch { throw ProjectError.invalidDocument }
        _ = try archive.validatedDocument()
        return archive
    }
    public static func readRegularFile(_ url: URL, limit: Int) throws -> Data {
        guard limit >= 0 else { throw ProjectError.invalidDocument }
        // Check the opened file, not a pathname that may change between stat/read.
        // Nonblocking open also avoids waiting on a substituted pipe/device.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw ProjectError.invalidDocument }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { throw ProjectError.invalidDocument }
        guard info.st_size <= limit else { throw ProjectError.fileTooLarge }
        var data = Data()
        while true {
            // Read at most one byte over the limit, even if the file grows after fstat.
            let count = min(1_048_576, limit - data.count) + 1
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { return data }
            guard chunk.count <= limit - data.count else { throw ProjectError.fileTooLarge }
            data.append(chunk)
        }
    }
    public static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func pngSize(_ data: Data) -> PixelSize? {
        guard data.count >= 33, Array(data.prefix(8)) == [137,80,78,71,13,10,26,10],
              Array(data[12..<16]) == [73,72,68,82] else { return nil }
        func integer(_ start: Int) -> Int { data[start..<start+4].reduce(0) { ($0 << 8) | Int($1) } }
        return PixelSize(width: integer(16), height: integer(20))
    }
    public static func copy(_ source: ProjectDocument, id: UUID) -> ProjectDocument {
        ProjectDocument(id: id, title: source.title, pixelSize: source.pixelSize, objects: source.objects,
                        createdAt: source.createdAt, modifiedAt: source.modifiedAt, crop: source.crop,
                        resizedSize: source.resizedSize, isFavorite: source.isFavorite, tags: source.tags, collections: source.collections, canvasRect: source.canvasRect, transform: source.transform, presentation: source.presentation)
    }
}

public struct LibraryBackupIndex: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let file: String
        public let isTrashed: Bool
        public let digest: String
        public init(file: String, isTrashed: Bool, digest: String) { self.file = file; self.isTrashed = isTrashed; self.digest = digest }
    }
    public var format = "com.snaprivo.backup"
    public var version = 1
    public let entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }
    public static func read(from url: URL) throws -> Self {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw ProjectError.invalidDocument }
        let index = try JSONDecoder().decode(Self.self, from: ProjectArchive.readRegularFile(url.appendingPathComponent("index.json"), limit: 8_000_000))
        guard index.format == "com.snaprivo.backup" else { throw ProjectError.invalidDocument }
        guard index.version == 1 else { throw ProjectError.unsupportedVersion }
        guard index.entries.count <= 100_000, Set(index.entries.map(\.file)).count == index.entries.count,
              index.entries.allSatisfy({ $0.file.hasSuffix(".snaprivo") && UUID(uuidString: String($0.file.dropLast(9))) != nil }) else { throw ProjectError.invalidDocument }
        return index
    }
}

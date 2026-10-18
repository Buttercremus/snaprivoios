import Foundation
import SQLite3

public enum LibraryIndexError: Error { case database(Int32), oversizedContent, staleSession }

/// Disposable local OCR cache. Project metadata remains authoritative in project packages.
public actor LibraryContentIndex {
    public nonisolated let url: URL
    private var epoch = UUID()
    private var enabled = false
    public private(set) var recoveredCache = false
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(url: URL) { self.url = url }

    /// Revokes older writers before deleting or pruning any cached text.
    public func configure(library: String, enabled: Bool, documents: [ProjectDocument], rebuild: Bool = false) throws -> UUID {
        try Task.checkCancellation()
        guard Set(documents.map(\.id)).count == documents.count else { throw ProjectError.invalidDocument }
        epoch = UUID(); self.enabled = enabled
        if !enabled || rebuild { try removeCache() }
        guard enabled else { return epoch }
        let scope = ProjectArchive.hash(Data(library.utf8))
        let previous = try connection { db -> String? in
            let statement = try prepare(db, "SELECT library FROM scope LIMIT 1"); defer { sqlite3_finalize(statement) }
            return try row(statement) ? string(statement, 0) : nil
        }
        if let previous, previous != scope { try removeCache() }
        let keys = try Dictionary(uniqueKeysWithValues: documents.map { ($0.id.uuidString, try LibrarySearch.imageKey($0)) })
        try connection { db in
            try execute(db, "BEGIN IMMEDIATE")
            do {
                let scopeStatement = try prepare(db, "INSERT OR REPLACE INTO scope (singleton, library) VALUES (1, ?)")
                defer { sqlite3_finalize(scopeStatement) }
                try bind(scope, to: scopeStatement, at: 1); try step(scopeStatement)
                let select = try prepare(db, "SELECT id, image_key FROM content"); defer { sqlite3_finalize(select) }
                var obsolete: [String] = []
                while try row(select) {
                    let id = string(select, 0)
                    if keys[id] != string(select, 1) { obsolete.append(id) }
                }
                for id in obsolete {
                    let delete = try prepare(db, "DELETE FROM content WHERE id = ?"); defer { sqlite3_finalize(delete) }
                    try bind(id, to: delete, at: 1); try step(delete)
                }
                try execute(db, "COMMIT")
            } catch { try? execute(db, "ROLLBACK"); throw error }
        }
        return epoch
    }

    public func missing(_ documents: [ProjectDocument], epoch: UUID) throws -> [ProjectDocument] {
        guard enabled, epoch == self.epoch else { throw LibraryIndexError.staleSession }
        return try connection { db in
            try documents.filter { document in
                let statement = try prepare(db, "SELECT 1 FROM content WHERE id = ? AND image_key = ?")
                defer { sqlite3_finalize(statement) }
                try bind(document.id.uuidString, to: statement, at: 1)
                try bind(LibrarySearch.imageKey(document), to: statement, at: 2)
                return try !row(statement)
            }
        }
    }
    public func record(_ text: String, for document: ProjectDocument, epoch: UUID) throws {
        try Task.checkCancellation()
        guard enabled, epoch == self.epoch else { throw LibraryIndexError.staleSession }
        guard text.utf8.count <= 1_000_000 else { throw LibraryIndexError.oversizedContent }
        let key = try LibrarySearch.imageKey(document), normalized = LibrarySearch.fold(text)
        guard normalized.utf8.count <= 1_000_000 else { throw LibraryIndexError.oversizedContent }
        try connection { db in
            let statement = try prepare(db, "INSERT OR REPLACE INTO content (id, image_key, text) VALUES (?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            try bind(document.id.uuidString, to: statement, at: 1)
            try bind(key, to: statement, at: 2); try bind(normalized, to: statement, at: 3); try step(statement)
        }
    }

    public func search(_ query: String, documents: [ProjectDocument], includeOCR: Bool) throws -> Set<UUID> {
        let terms = LibrarySearch.terms(query)
        guard !terms.isEmpty else { return Set(documents.map(\.id)) }
        func metadataMatches() -> Set<UUID> { Set(documents.filter { LibrarySearch.matches($0, query: query) }.map(\.id)) }
        guard enabled, includeOCR else { return metadataMatches() }
        return try connection { db in
            var result = Set<UUID>()
            for document in documents {
                try Task.checkCancellation()
                let metadata = LibrarySearch.metadata(document)
                if terms.allSatisfy(metadata.contains) { result.insert(document.id); continue }
                let statement = try prepare(db, "SELECT text FROM content WHERE id = ? AND image_key = ?")
                defer { sqlite3_finalize(statement) }
                try bind(document.id.uuidString, to: statement, at: 1)
                try bind(LibrarySearch.imageKey(document), to: statement, at: 2)
                if try row(statement) {
                    let text = string(statement, 0)
                    if terms.allSatisfy({ metadata.contains($0) || text.contains($0) }) { result.insert(document.id) }
                }
            }
            return result
        }
    }

    private func removeCache() throws {
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true || values.isSymbolicLink == true else { throw LibraryIndexError.database(SQLITE_CANTOPEN) }
                try FileManager.default.removeItem(at: file)
            }
        }
    }
    private func connection<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        do { return try openConnection(operation) }
        catch LibraryIndexError.database(let code) where code == SQLITE_CORRUPT || code == SQLITE_NOTADB || code == SQLITE_SCHEMA {
            try removeCache(); recoveredCache = true
            return try openConnection(operation)
        }
    }
    private func openConnection<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw LibraryIndexError.database(SQLITE_CANTOPEN) }
        var pointer: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        guard let db = pointer else { throw LibraryIndexError.database(opened) }
        defer { sqlite3_close(db) }
        guard opened == SQLITE_OK else { throw LibraryIndexError.database(opened) }
        sqlite3_busy_timeout(db, 1000)
        try execute(db, "PRAGMA secure_delete = ON")
        try execute(db, "PRAGMA journal_mode = DELETE")
        try execute(db, "PRAGMA max_page_count = 32768") // At most 128 MiB with 4 KiB pages.
        let versionStatement = try prepare(db, "PRAGMA user_version")
        let version = sqlite3_step(versionStatement) == SQLITE_ROW ? sqlite3_column_int(versionStatement, 0) : -1
        sqlite3_finalize(versionStatement)
        guard version == 0 || version == 1 else { throw LibraryIndexError.database(SQLITE_SCHEMA) }
        try execute(db, "CREATE TABLE IF NOT EXISTS content (id TEXT PRIMARY KEY, image_key TEXT NOT NULL, text TEXT NOT NULL)")
        try execute(db, "CREATE TABLE IF NOT EXISTS scope (singleton INTEGER PRIMARY KEY CHECK (singleton = 1), library TEXT NOT NULL)")
        try execute(db, "PRAGMA user_version = 1")
        return try operation(db)
    }
    private func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw LibraryIndexError.database(code) }
        return statement
    }
    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw LibraryIndexError.database(code) }
    }
    private func bind(_ value: String, to statement: OpaquePointer, at column: Int32) throws {
        let code = value.withCString { sqlite3_bind_text(statement, column, $0, Int32(value.utf8.count), transient) }
        guard code == SQLITE_OK else { throw LibraryIndexError.database(code) }
    }
    private func step(_ statement: OpaquePointer) throws {
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw LibraryIndexError.database(code) }
    }
    private func row(_ statement: OpaquePointer) throws -> Bool {
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW || code == SQLITE_DONE else { throw LibraryIndexError.database(code) }
        return code == SQLITE_ROW
    }
    private func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }
}

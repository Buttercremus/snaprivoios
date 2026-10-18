import Foundation
import Observation

/// Public bookmark APIs are isolated here so denial, stale grants and restart are testable.
@MainActor struct FolderBookmarkClient {
    struct Resolved { let url: URL; let stale: Bool }
    var create: (URL) throws -> Data
    var resolve: (Data) throws -> Resolved
    var start: (URL) -> Bool
    var stop: (URL) -> Void
    static var live: Self {
        Self(create: { try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) },
             resolve: { data in
                 var stale = false
                 let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
                 return Resolved(url: url, stale: stale)
             }, start: { $0.startAccessingSecurityScopedResource() }, stop: { $0.stopAccessingSecurityScopedResource() })
    }
}

@MainActor @Observable
final class StorageLocations {
    enum Kind: String { case png, library }
    struct Prepared { let url: URL; let bookmark: Data }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: FolderBookmarkClient
    private var grants: [Kind: Prepared] = [:]
    private(set) var errors: [Kind: String] = [:]
    var pngFolder: URL? { grants[.png]?.url }
    var libraryFolder: URL? { grants[.library]?.url }
    var libraryError: String? { errors[.library] }
    var libraryURL: URL? { libraryFolder.map(Self.libraryURL(in:)) }
    var storedLibraryURL: URL? { path(for: .library).map { Self.libraryURL(in: URL(fileURLWithPath: $0)) } }

    init(defaults: UserDefaults = .standard, client: FolderBookmarkClient = .live) {
        self.defaults = defaults; self.client = client
        for kind in [Kind.png, .library] {
            guard let data = defaults.data(forKey: key(kind, "bookmark")) else {
                if defaults.object(forKey: key(kind, "bookmark")) != nil || defaults.string(forKey: key(kind, "path")) != nil {
                    errors[kind] = String(localized: "Die gespeicherte Ordnerfreigabe ist beschädigt. Bitte den bisherigen Ordner erneut auswählen.")
                }
                continue
            }
            do {
                let resolved = try client.resolve(data)
                guard client.start(resolved.url) else { throw CocoaError(.fileReadNoPermission) }
                do {
                    try Self.validateDirectory(resolved.url)
                    if kind == .library { try Self.validateDirectory(Self.libraryURL(in: resolved.url)) }
                    let refreshed = resolved.stale ? try client.create(resolved.url) : data
                    grants[kind] = Prepared(url: resolved.url, bookmark: refreshed)
                    defaults.set(refreshed, forKey: key(kind, "bookmark"))
                    defaults.set(resolved.url.path, forKey: key(kind, "path"))
                } catch { client.stop(resolved.url); throw error }
            } catch {
                errors[kind] = String(localized: "Der gespeicherte Ordner ist nicht erreichbar oder nicht freigegeben. Bitte erneut auswählen. \(error.localizedDescription)")
            }
        }
    }
    static func libraryURL(in folder: URL) -> URL {
        folder.lastPathComponent == "Snaprivo-Bibliothek" ? folder : folder.appendingPathComponent("Snaprivo-Bibliothek", isDirectory: true)
    }
    private func key(_ kind: Kind, _ field: String) -> String { "storage.\(kind.rawValue).\(field)" }
    func path(for kind: Kind) -> String? { grants[kind]?.url.path ?? defaults.string(forKey: key(kind, "path")) }
    private static func validateDirectory(_ url: URL) throws {
        guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadNoSuchFile) }
    }
    func prepare(_ folder: URL) throws -> Prepared {
        guard folder.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let initialAccess = client.start(folder)
        defer { if initialAccess { client.stop(folder) } }
        let data = try client.create(folder), resolved = try client.resolve(data)
        guard client.start(resolved.url) else { throw CocoaError(.fileReadNoPermission) }
        do {
            try Self.validateDirectory(resolved.url)
            return Prepared(url: resolved.url, bookmark: data)
        } catch { client.stop(resolved.url); throw error }
    }
    /// Called only after a library copy is completely verified, or a PNG folder is selected.
    func commit(_ prepared: Prepared, for kind: Kind) {
        if let old = grants[kind] { client.stop(old.url) }
        grants[kind] = prepared; errors[kind] = nil
        defaults.set(prepared.bookmark, forKey: key(kind, "bookmark"))
        defaults.set(prepared.url.path, forKey: key(kind, "path"))
    }
    func discard(_ prepared: Prepared) { client.stop(prepared.url) }
    func clearPNGFolder() {
        if let old = grants.removeValue(forKey: .png) { client.stop(old.url) }
        errors[.png] = nil
        defaults.removeObject(forKey: key(.png, "bookmark")); defaults.removeObject(forKey: key(.png, "path"))
    }
    func endAccess() {
        for grant in grants.values { client.stop(grant.url) }
        grants.removeAll()
    }
}

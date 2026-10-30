import Foundation
import Observation

/// Public bookmark APIs are isolated here so denial, stale grants and restart are testable.
@MainActor struct FolderBookmarkClient {
    struct Resolved { let url: URL; let stale: Bool }
    var create: (URL) throws -> Data
    var resolve: (Data) throws -> Resolved
    var start: (URL) -> Bool
    var stop: (URL) -> Void
    let isLive: Bool
    let restoreGate: (@Sendable () async -> Void)?
    init(create: @escaping (URL) throws -> Data, resolve: @escaping (Data) throws -> Resolved,
         start: @escaping (URL) -> Bool, stop: @escaping (URL) -> Void, isLive: Bool = false,
         restoreGate: (@Sendable () async -> Void)? = nil) {
        self.create = create; self.resolve = resolve; self.start = start; self.stop = stop; self.isLive = isLive; self.restoreGate = restoreGate
    }
    static var live: Self {
        Self(create: { try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) },
             resolve: { data in
                 var stale = false
                 let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
                 return Resolved(url: url, stale: stale)
             }, start: { $0.startAccessingSecurityScopedResource() }, stop: { $0.stopAccessingSecurityScopedResource() }, isLive: true)
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
    private(set) var isReady: Bool
    @ObservationIgnored private let liveRestore: Bool
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var restoreGeneration: UInt = 0
    var pngFolder: URL? { grants[.png]?.url }
    var libraryFolder: URL? { grants[.library]?.url }
    var libraryError: String? { isReady ? errors[.library] : String(localized: "Speicher wird vorbereitet …") }
    var libraryURL: URL? { libraryFolder.map(Self.libraryURL(in:)) }
    var storedLibraryURL: URL? { path(for: .library).map { Self.libraryURL(in: URL(fileURLWithPath: $0)) } }

    init(defaults: UserDefaults = .standard, client: FolderBookmarkClient = .live) {
        self.defaults = defaults; self.client = client; self.liveRestore = client.isLive
        let hasPersistedStorageState = [Kind.png, .library].contains { kind in
            let prefix = "storage.\(kind.rawValue)."
            return defaults.object(forKey: prefix + "bookmark") != nil || defaults.object(forKey: prefix + "path") != nil
        }
        self.isReady = !client.isLive || !hasPersistedStorageState
        if client.isLive { return }
        for kind in [Kind.png, .library] {
            guard let data = defaults.data(forKey: key(kind, "bookmark")) else {
                if defaults.object(forKey: key(kind, "bookmark")) != nil || defaults.object(forKey: key(kind, "path")) != nil {
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
        isReady = true
    }

    /// Resolves the live bookmark and directory metadata off the main actor. Test clients retain
    /// their synchronous setup so existing injected lifecycle tests remain deterministic.
    func restoreIfNeeded() async {
        guard liveRestore, !isReady else { return }
        if let restoreTask { await restoreTask.value; return }
        let generation = restoreGeneration
        let defaults = self.defaults
        let pngData = defaults.data(forKey: key(.png, "bookmark"))
        let libraryData = defaults.data(forKey: key(.library, "bookmark"))
        let pngHasState = defaults.object(forKey: key(.png, "bookmark")) != nil || defaults.object(forKey: key(.png, "path")) != nil
        let libraryHasState = defaults.object(forKey: key(.library, "bookmark")) != nil || defaults.object(forKey: key(.library, "path")) != nil
        let restoreGate = client.restoreGate
        restoreTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                if let restoreGate { await restoreGate() }
                return Self.resolveLiveBookmarks(png: pngData, library: libraryData,
                                                 pngHasState: pngHasState, libraryHasState: libraryHasState)
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.restoreGeneration == generation else {
                Self.releaseLive(result)
                return
            }
            defer { self.restoreTask = nil; self.isReady = true }
            self.applyLiveRestore(result)
        }
        await restoreTask?.value
    }

    private struct LiveResult: Sendable {
        let png: (URL, Bool, Data)?
        let library: (URL, Bool, Data)?
        let errors: [Kind: String]
    }

    private nonisolated static func resolveLiveBookmarks(png: Data?, library: Data?, pngHasState: Bool, libraryHasState: Bool) -> LiveResult {
        var errors: [Kind: String] = [:]
        func resolve(_ data: Data?, hasState: Bool, kind: Kind) -> (URL, Bool, Data)? {
            guard !Task.isCancelled else { return nil }
            guard let data else {
                if hasState { errors[kind] = String(localized: "Die gespeicherte Ordnerfreigabe ist beschädigt. Bitte den bisherigen Ordner erneut auswählen.") }
                return nil
            }
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
                try Task.checkCancellation()
                guard url.isFileURL, url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                do {
                    try Task.checkCancellation()
                    guard try Self.directoryExists(url) else { throw CocoaError(.fileReadNoSuchFile) }
                    if kind == .library { guard try Self.directoryExists(Self.libraryURL(in: url)) else { throw CocoaError(.fileReadNoSuchFile) } }
                    let bookmark = stale ? try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) : data
                    return (url, stale, bookmark)
                } catch {
                    url.stopAccessingSecurityScopedResource()
                    throw error
                }
            } catch {
                errors[kind] = String(localized: "Der gespeicherte Ordner ist nicht erreichbar oder nicht freigegeben. Bitte erneut auswählen. \(error.localizedDescription)")
                return nil
            }
        }
        return LiveResult(png: resolve(png, hasState: pngHasState, kind: .png),
                          library: resolve(library, hasState: libraryHasState, kind: .library), errors: errors)
    }

    private nonisolated static func releaseLive(_ result: LiveResult) {
        result.png?.0.stopAccessingSecurityScopedResource()
        result.library?.0.stopAccessingSecurityScopedResource()
    }

    private nonisolated static func directoryExists(_ url: URL) throws -> Bool {
        guard url.isFileURL else { return false }
        return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    private struct LivePrepared: Sendable {
        let url: URL
        let bookmark: Data
    }

    private nonisolated static func prepareLive(_ folder: URL) throws -> LivePrepared {
        guard folder.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let initialAccess = folder.startAccessingSecurityScopedResource()
        defer { if initialAccess { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try folder.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark,
                               options: [.withSecurityScope, .withoutUI, .withoutMounting],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        guard resolved.isFileURL, resolved.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
        do {
            guard try directoryExists(resolved) else { throw CocoaError(.fileReadNoSuchFile) }
            return LivePrepared(url: resolved, bookmark: bookmark)
        } catch {
            resolved.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    private func applyLiveRestore(_ result: LiveResult) {
        errors = result.errors
        for (kind, value) in [(Kind.png, result.png), (.library, result.library)] {
            guard let (url, _, bookmark) = value else { continue }
            grants[kind] = Prepared(url: url, bookmark: bookmark)
            defaults.set(bookmark, forKey: key(kind, "bookmark")); defaults.set(url.path, forKey: key(kind, "path"))
        }
    }
    nonisolated static func libraryURL(in folder: URL) -> URL {
        folder.lastPathComponent == "Snaprivo-Bibliothek" ? folder : folder.appendingPathComponent("Snaprivo-Bibliothek", isDirectory: true)
    }
    private func key(_ kind: Kind, _ field: String) -> String { "storage.\(kind.rawValue).\(field)" }
    func path(for kind: Kind) -> String? { grants[kind]?.url.path ?? defaults.string(forKey: key(kind, "path")) }
    private static func validateDirectory(_ url: URL) throws {
        guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadNoSuchFile) }
    }
    func prepare(_ folder: URL) throws -> Prepared {
        // The live path is asynchronous so bookmark and metadata work never blocks the MainActor.
        guard !client.isLive else { throw CocoaError(.featureUnsupported) }
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

    func prepareAsync(_ folder: URL) async throws -> Prepared {
        guard client.isLive else { return try prepare(folder) }
        let generation = restoreGeneration
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let prepared = try Self.prepareLive(folder)
            do { try Task.checkCancellation() }
            catch { prepared.url.stopAccessingSecurityScopedResource(); throw error }
            return prepared
        }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, generation == restoreGeneration else {
            prepared.url.stopAccessingSecurityScopedResource()
            throw CancellationError()
        }
        return Prepared(url: prepared.url, bookmark: prepared.bookmark)
    }
    private func release(_ url: URL) {
        if liveRestore { url.stopAccessingSecurityScopedResource() }
        else { client.stop(url) }
    }
    /// Called only after a library copy is completely verified, or a PNG folder is selected.
    func commit(_ prepared: Prepared, for kind: Kind) {
        if let old = grants[kind] { release(old.url) }
        grants[kind] = prepared; errors[kind] = nil
        defaults.set(prepared.bookmark, forKey: key(kind, "bookmark"))
        defaults.set(prepared.url.path, forKey: key(kind, "path"))
    }
    func discard(_ prepared: Prepared) { release(prepared.url) }
    func clearPNGFolder() {
        if let old = grants.removeValue(forKey: .png) { release(old.url) }
        errors[.png] = nil
        defaults.removeObject(forKey: key(.png, "bookmark")); defaults.removeObject(forKey: key(.png, "path"))
    }
    func endAccess() {
        restoreGeneration &+= 1
        restoreTask?.cancel()
        restoreTask = nil
        for grant in grants.values { release(grant.url) }
        grants.removeAll()
    }
}

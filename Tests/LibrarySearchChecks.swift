import AppKit
import SnagForgeDomain

@MainActor private final class LibrarySearchProStore: ProStoreClient {
    func offer() async throws -> ProOffer? { nil }
    func entitled() async throws -> Bool { true }
    func purchase() async throws -> ProPurchaseOutcome { .cancelled }
    func restore() async throws {}
    func updates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

actor SearchGate {
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var started = false
    func recognize() async -> String {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(returning: "Late synthetic secret"); continuation = nil }
}

actor RefreshSearchGate {
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var calls = 0
    func recognize() async -> String {
        calls += 1
        if calls > 1 { return "Visible refreshed content" }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(returning: "Cancelled stale secret"); continuation = nil }
}

enum LibrarySearchChecks {
    @MainActor static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SearchChecks-" + UUID().uuidString)
        let suite = "SearchChecks-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let entitlement = ProPurchaseModel(client: LibrarySearchProStore())
        await entitlement.start()
        defer { entitlement.stop() }
        let workspace = WorkspaceModel(root: root, defaults: defaults, purchases: entitlement)
        let context = CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        func label(_ text: String, y: CGFloat) -> EditorObject {
            var label = EditorObject(kind: .text, start: CGPoint(x: 60, y: y), text: text, fontSize: 44)
            label.color = EditorColor(red: 0, green: 0, blue: 0); return label
        }
        let pixels = try EditorRenderer.render(image: context.makeImage()!, objects: [label("SYNTHETIC PRIVATE CODE", y: 80), label("VISIBLE PUBLIC CONTENT", y: 330)])
        let png = try EditorRenderer.png(image: pixels, objects: [])
        let document = ProjectDocument(title: "Metadata title", pixelSize: PixelSize(width: 1200, height: 600)!, tags: ["Support"], collections: ["Inbox"])
        try await workspace.store.create(document, original: png, thumbnail: nil)
        await workspace.refreshLibrary(); await workspace.search.finish()
        precondition(!workspace.preferences.ocrIndexingEnabled)
        let offMatches = try await workspace.search.matches(query: "PRIVATE", documents: [document], includeOCR: false)
        precondition(offMatches.isEmpty)
        workspace.preferences.ocrIndexingEnabled = true
        await workspace.search.finish()
        if workspace.search.failures > 0 {
            do {
                let loaded = try await workspace.store.load(document.id)
                FileHandle.standardOutput.write(Data("Synthetic OCR diagnostic: project package loaded; checking Vision.\n".utf8))
                _ = try await LibrarySearchModel.recognizeProject(loaded)
                FileHandle.standardOutput.write(Data("Synthetic OCR diagnostic: direct recognition passed; index operation failed.\n".utf8))
            } catch {
                let value = error as NSError
                let path = value.userInfo[NSFilePathErrorKey] ?? value.userInfo[NSURLErrorKey] ?? "no file path"
                FileHandle.standardOutput.write(Data("Synthetic OCR diagnostic: \(value.domain) / \(value.code): \(value.localizedDescription); \(path)\n".utf8))
            }
        }
        precondition(!workspace.search.isIndexing && workspace.search.failures == 0 && workspace.search.completed == 1,
                     "OCR index state: running=\(workspace.search.isIndexing), failures=\(workspace.search.failures), completed=\(workspace.search.completed)")
        let textMatch = try await workspace.search.matches(query: "support private", documents: [document], includeOCR: true)
        precondition(textMatch == [document.id], "Real OCR was not searchable with metadata")
        let restartedCache = LibrarySearchModel(cacheURL: root.appendingPathComponent(".library-search.sqlite"), recognize: { _ in
            preconditionFailure("A valid persisted OCR result was unnecessarily recognized again")
        })
        restartedCache.synchronize(documents: [document], store: workspace.store, enabled: true)
        await restartedCache.finish()
        let persisted = try await restartedCache.matches(query: "private", documents: [document], includeOCR: true)
        precondition(persisted == [document.id])
        // A returning Pro user must retain the valid cache until receipt loading
        // and the initial document listing have both finished.
        let checking = ProPurchaseModel(client: LibrarySearchProStore())
        let pending = WorkspaceModel(root: root, defaults: defaults, purchases: checking)
        await pending.refreshLibrary(); await pending.search.finish()
        precondition(!checking.hasCheckedEntitlement && !pending.search.isIndexing)
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent(".library-search.sqlite").path))
        await checking.start(); await pending.search.finish()
        let afterReceipt = try await pending.search.matches(query: "private", documents: [document], includeOCR: true)
        precondition(afterReceipt == [document.id])
        checking.stop(); pending.search.cancel()
        let metadataSaved = await workspace.updateProjectMetadata(document.id, tags: ["  Bug ", "BUG"], collections: ["Support Cases", "Inbox"])
        precondition(metadataSaved)
        await workspace.search.finish()
        workspace.openProject(document.id)
        for _ in 0..<1000 where workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        let editor = workspace.editor!
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 30, y: 50), end: CGPoint(x: 1100, y: 190))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        editor.commit([mask])
        let stale = try await workspace.search.matches(query: "private", documents: [editor.document], includeOCR: true)
        precondition(stale.isEmpty, "Unsaved redaction still matched an old OCR result")
        let saved = await editor.flush(); precondition(saved)
        await workspace.refreshLibrary(); await workspace.search.finish()
        let hidden = try await workspace.search.matches(query: "private", documents: [editor.document], includeOCR: true)
        let visible = try await workspace.search.matches(query: "bug public", documents: [editor.document], includeOCR: true)
        precondition(hidden.isEmpty && visible == [document.id], "Redacted source leaked or visible content was lost")
        editor.undo()
        precondition(editor.document.tags == ["Bug"] && editor.document.collections == ["Support Cases", "Inbox"])
        let copied = await editor.saveCopy(); precondition(copied)
        let copy = try await workspace.store.load(editor.document.id)
        precondition(copy.document.tags == ["Bug"] && copy.document.collections == ["Support Cases", "Inbox"])
        workspace.preferences.ocrIndexingEnabled = false
        await workspace.search.finish()
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".library-search.sqlite").path))
        precondition(!AppPreferences(defaults: UserDefaults(suiteName: suite)!).ocrIndexingEnabled)
        let fresh = WorkspaceModel(root: root, defaults: defaults)
        await fresh.refreshLibrary(); await fresh.search.finish()
        precondition(fresh.items.allSatisfy { $0.document.tags == ["Bug"] && $0.document.collections == ["Support Cases", "Inbox"] })
        try await checkLateCancellation(document: document, store: workspace.store, root: root)
        try await checkRefreshSerialization(document: document, store: workspace.store, root: root)
        _ = await workspace.flushBeforeQuitting()
        print("Library search checks passed: real visible-image OCR, metadata plus image-content search, opt-in/restart/disable/cache removal, open-editor organization, unsaved and saved redaction invalidation, Undo and save-copy metadata, late cancelled job after disabling. Synthetic fixtures only; no OCR contents logged.")
    }

    @MainActor private static func checkLateCancellation(document: ProjectDocument, store: ProjectStore, root: URL) async throws {
        let gate = SearchGate(), cache = root.appendingPathComponent("delayed.sqlite")
        let latest = try await store.readDocument(document.id)
        let model = LibrarySearchModel(cacheURL: cache, recognize: { _ in await gate.recognize() })
        model.synchronize(documents: [latest], store: store, enabled: true)
        for _ in 0..<1000 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await gate.started; precondition(started)
        let oldJob = model.cancel()
        model.synchronize(documents: [latest], store: store, enabled: false)
        for _ in 0..<1000 where FileManager.default.fileExists(atPath: cache.path) { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!FileManager.default.fileExists(atPath: cache.path), "Disabling waited for a late Vision result before removing its cache")
        await gate.release(); await oldJob?.value
        await model.finish()
        precondition(!FileManager.default.fileExists(atPath: cache.path) && !model.isIndexing && model.failures == 0)
        let late = try await model.matches(query: "secret", documents: [latest], includeOCR: true)
        precondition(late.isEmpty)
    }
    @MainActor private static func checkRefreshSerialization(document: ProjectDocument, store: ProjectStore, root: URL) async throws {
        let gate = RefreshSearchGate(), latest = try await store.readDocument(document.id)
        let model = LibrarySearchModel(cacheURL: root.appendingPathComponent("refresh.sqlite"), recognize: { _ in await gate.recognize() })
        model.synchronize(documents: [latest], store: store, enabled: true)
        for _ in 0..<1000 {
            if await gate.calls == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        var updated = latest; updated.revision += 1; updated.tags = ["Changed"]
        model.synchronize(documents: [updated], store: store, enabled: true)
        await gate.release(); await model.finish()
        let calls = await gate.calls
        precondition(calls == 2 && model.failures == 0 && model.completed == 1)
        let refreshed = try await model.matches(query: "changed refreshed", documents: [updated], includeOCR: true)
        let stale = try await model.matches(query: "secret", documents: [updated], includeOCR: true)
        precondition(refreshed == [document.id] && stale.isEmpty)
        model.synchronize(documents: [updated], store: store, enabled: true, rebuild: true)
        await model.finish()
        let rebuiltCalls = await gate.calls
        precondition(rebuiltCalls == 3 && model.failures == 0)
    }
}

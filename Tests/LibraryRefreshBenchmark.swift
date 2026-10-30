import Foundation
import SnagForgeDomain

/// Synthetic metadata/thumbnail refresh workload; no capture or user library access.
@main struct LibraryRefreshBenchmark {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryRefreshBenchmark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let size = PixelSize(width: 20, height: 20)!
        let thumbnail = Data(repeating: 42, count: 16_384)
        var edited: ProjectDocument!
        for index in 0..<600 {
            let document = ProjectDocument(title: "Synthetic \(index)", pixelSize: size,
                objects: [EditorObject(kind: .text, start: .zero, text: "Synthetic text \(index)")])
            try await store.create(document, original: Data([1]), thumbnail: thumbnail)
            if index == 0 { edited = document }
            if index >= 500 { try await store.moveToTrash(document.id) }
        }
        var milliseconds: [Double] = [], focused: [Double] = []
        var cached = try await store.list().items
        for iteration in 1...12 {
            edited.revision = iteration; edited.modifiedAt = .now
            try await store.save(edited, expectedGeneration: iteration - 1, thumbnail: thumbnail)
            let start = ContinuousClock.now
            let active = try await store.list(), trash = try await store.listTrash()
            precondition(active.items.count == 500 && trash.items.count == 100)
            precondition(active.items.first { $0.id == edited.id }?.document == edited)
            let elapsed = start.duration(to: .now).components
            milliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            let focusedStart = ContinuousClock.now
            cached = ProjectLibraryItem(document: edited, thumbnail: thumbnail).updating(cached)
            let focusedElapsed = focusedStart.duration(to: .now).components
            focused.append(Double(focusedElapsed.seconds) * 1000 + Double(focusedElapsed.attoseconds) / 1e15)
            precondition(cached.count == 500 && cached.first { $0.id == edited.id }?.document == edited)
            precondition(cached.allSatisfy { item in active.items.contains { $0.document == item.document && $0.thumbnail == item.thumbnail } })
        }
        print("Full refresh: 500 active + 100 trash; median \(milliseconds.sorted()[milliseconds.count / 2]) ms (12 saves)")
        print("Committed-item update: same 500 active + untouched 100 trash; median \(focused.sorted()[focused.count / 2]) ms (12 saves)")
    }
}

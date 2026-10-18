import Foundation
import Testing
@testable import SnagForgeDomain

private let sourceSize = PixelSize(width: 640, height: 480)!
private let cropRect = CGRect(x: 60, y: 40, width: 320, height: 200)

@Test func cropRoundsEdgesAndClampsInBothDirections() {
    #expect(EditorCrop.normalized(CGRect(x: 380.4, y: 240.4, width: -320.2, height: -200.2), in: sourceSize) == cropRect)
    #expect(EditorCrop.normalized(CGRect(x: -50, y: -40, width: 900, height: 700), in: sourceSize) == EditorCrop.fullRect(sourceSize))
    #expect(EditorCrop.normalized(CGRect(x: 639.8, y: 479.8, width: 5, height: 5), in: sourceSize) == CGRect(x: 639, y: 479, width: 1, height: 1))
    #expect(EditorCrop.normalized(.zero, in: sourceSize) == nil)
    #expect(EditorCrop.normalized(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), in: sourceSize) == nil)
}

@Test func cropMovePreservesSizeAtAllBoundaries() {
    #expect(EditorCrop.moved(cropRect, by: CGSize(width: -1000, height: -1000), in: sourceSize) == CGRect(origin: .zero, size: cropRect.size))
    #expect(EditorCrop.moved(cropRect, by: CGSize(width: 1000, height: 1000), in: sourceSize) == CGRect(x: 320, y: 280, width: 320, height: 200))
    #expect(EditorCrop.moved(cropRect, by: CGSize(width: 1.6, height: -2.7), in: sourceSize) == cropRect.offsetBy(dx: 2, dy: -3))
    #expect(EditorCrop.moved(cropRect, by: CGSize(width: CGFloat.infinity, height: 0), in: sourceSize) == cropRect)
}

@Test func cropAllHandlesKeepOppositeEdgeAndMinimumPixel() {
    for handle in EditorResizeHandle.allCases {
        for delta in [CGSize(width: -1000, height: -1000), CGSize(width: 1000, height: 1000), CGSize(width: 14, height: 23)] {
            let result = EditorCrop.resized(cropRect, handle: handle, by: delta, in: sourceSize)
            #expect(EditorCrop.isValid(result, in: sourceSize))
            if handle.movesLeft { #expect(result.maxX == cropRect.maxX) }
            if handle.movesRight { #expect(result.minX == cropRect.minX) }
            if handle.movesTop { #expect(result.maxY == cropRect.maxY) }
            if handle.movesBottom { #expect(result.minY == cropRect.minY) }
            if !handle.movesLeft && !handle.movesRight { #expect(result.minX == cropRect.minX && result.width == cropRect.width) }
            if !handle.movesTop && !handle.movesBottom { #expect(result.minY == cropRect.minY && result.height == cropRect.height) }
        }
    }
}

@Test func cropAndObjectOperationsShareOneHistory() {
    let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 90, y: 80), end: CGPoint(x: 220, y: 190))
    var history = EditorHistory(objects: [arrow])
    history.beginTransaction()
    var text = EditorObject(kind: .text, start: CGPoint(x: 100, y: 100), text: "A")
    history.updateTransaction([arrow, text]); text.text = "AB"; history.updateTransaction([arrow, text])
    history.commitCrop(cropRect)
    #expect(history.objects == [arrow, text] && history.crop == cropRect)
    history.undo(); #expect(history.objects == [arrow, text] && history.crop == nil)
    history.undo(); #expect(history.objects == [arrow] && history.crop == nil)
    history.redo(); history.redo()
    let moved = arrow.translated(by: CGSize(width: 12, height: -8))
    history.commit([moved, text]); history.undo()
    #expect(history.objects == [arrow, text] && history.crop == cropRect)
    history.commitCrop(nil); history.undo()
    #expect(history.crop == cropRect && history.objects == [arrow, text])
    history.commitCrop(cropRect) // no-op must not clear redo
    #expect(history.canRedo)
}

@Test func cropDocumentRejectsFractionalEmptyAndOutOfBoundsRectangles() throws {
    var document = ProjectDocument(title: "Crop", pixelSize: sourceSize, crop: cropRect)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)) == document)
    #expect(document.outputRect == cropRect && document.pixelSize == sourceSize)
    for rect in [CGRect.zero, CGRect(x: -1, y: 0, width: 10, height: 10), CGRect(x: 0.5, y: 1, width: 5, height: 6),
                 CGRect(x: 0, y: 0, width: 641, height: 480), CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
                 CGRect(x: 0, y: 0, width: -10, height: 20)] {
        document.crop = rect
        #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    }
}

@Test func legacyV1MigratesWithoutChangingIdentityOrObjects() throws {
    let original = ProjectDocument(title: "Altprojekt", pixelSize: sourceSize, objects: [EditorObject(kind: .text, start: .zero, text: "Alt")], revision: 7)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
    json["schemaVersion"] = 1; json.removeValue(forKey: "crop")
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated == original && migrated.schemaVersion == ProjectDocument.currentVersion && migrated.crop == nil)
    json["schemaVersion"] = ProjectDocument.currentVersion + 1
    #expect(throws: ProjectError.unsupportedVersion) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
}

@Test func cropStoreRoundtripRecoveryAndOriginalAreIndependent() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Crop-Store-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), bytes = Data("synthetic-original".utf8)
    var document = ProjectDocument(title: "Crop", pixelSize: sourceSize)
    try await store.create(document, original: bytes, thumbnail: nil)
    document.crop = cropRect; document.revision = 1
    try await store.save(document, expectedGeneration: 0, thumbnail: Data("crop-thumb".utf8))
    let loaded = try await ProjectStore(root: root).load(document.id)
    #expect(loaded.document == document && loaded.original == bytes)
    document.crop = nil; document.revision = 2
    try await store.save(document, expectedGeneration: 1, thumbnail: nil)
    try Data("broken".utf8).write(to: root.appendingPathComponent("\(document.id.uuidString).snagforge/Revisions/2.json"))
    let recovered = try await ProjectStore(root: root).load(document.id)
    #expect(recovered.recovered && recovered.document.crop == cropRect && recovered.original == bytes)
}

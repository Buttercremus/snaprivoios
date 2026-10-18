import Foundation
import Testing
@testable import SnagForgeDomain

@Test func resizeLimitsAndLinkedDimensions() {
    #expect(EditorResize.size(width: 1920, height: 1080) == PixelSize(width: 1920, height: 1080))
    for value in [Double.nan, .infinity, 0, -1, 32769, Double(Int.max)] {
        #expect(EditorResize.size(width: value, height: 100) == nil)
        #expect(EditorResize.linkedDimension(value: value, changingWidth: true, ratio: CGSize(width: 16, height: 9)) == nil)
    }
    #expect(EditorResize.size(width: 10001, height: 10000) == nil)
    #expect(EditorResize.size(width: 10000, height: 10000) != nil)
    #expect(EditorResize.linkedDimension(value: 1280, changingWidth: true, ratio: CGSize(width: 1920, height: 1080)) == 720)
    #expect(EditorResize.linkedDimension(value: 720, changingWidth: false, ratio: CGSize(width: 1920, height: 1080)) == 1280)
    #expect(EditorResize.linkedDimension(value: 1, changingWidth: true, ratio: CGSize(width: 32768, height: 1)) == 1)
    #expect(EditorResize.linkedDimension(value: 100, changingWidth: true, ratio: .zero) == nil)
}

@Test func resizedDocumentPreservesSourceAndMigratesBothLegacyFormats() throws {
    let original = PixelSize(width: 640, height: 480)!, crop = CGRect(x: 10, y: 20, width: 320, height: 240)
    var document = ProjectDocument(title: "Resize", pixelSize: original, crop: crop, resizedSize: PixelSize(width: 160, height: 120))
    #expect(document.outputPixelSize == PixelSize(width: 160, height: 120))
    #expect(document.outputRect == crop && document.pixelSize == original)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)) == document)
    document.resizedSize = PixelSize(width: 10001, height: 10000)
    #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    for version in [1, 2] {
        let old = ProjectDocument(title: "Legacy", pixelSize: original, crop: version == 2 ? crop : nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json["schemaVersion"] = version
        let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
        #expect(migrated == old && migrated.resizedSize == nil)
        json["resizedSize"] = ["width": 160, "height": 120]
        #expect(throws: ProjectError.invalidDocument) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
    }
}

@Test func resizeAndCropShareOneHistoryWithoutChangingAnnotations() {
    let arrow = EditorObject(kind: .arrow, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 100, y: 80))
    let crop = CGRect(x: 0, y: 0, width: 320, height: 240), size = PixelSize(width: 160, height: 120)!
    var history = EditorHistory(objects: [arrow])
    history.commitCrop(crop); history.commitResize(size)
    history.commit([arrow.translated(by: CGSize(width: 5, height: 7))])
    history.undo(); #expect(history.objects == [arrow] && history.crop == crop && history.resizedSize == size)
    history.undo(); #expect(history.resizedSize == nil && history.crop == crop)
    history.redo(); #expect(history.resizedSize == size)
    history.commitResize(size); #expect(history.canRedo) // A no-op retains redo.
    history.undo(); history.undo(); #expect(history.crop == nil && history.objects == [arrow])
}

@Test func croppingKeepsResizeFactorsAndRejectsExcessiveExpansion() throws {
    let from = CGRect(x: 20, y: 30, width: 320, height: 240), to = CGRect(x: 10, y: 20, width: 640, height: 480)
    #expect(try EditorResize.preservingScale(from: from, to: to, output: PixelSize(width: 160, height: 60)) == PixelSize(width: 320, height: 120))
    #expect(try EditorResize.preservingScale(from: from, to: to, output: nil) == nil)
    #expect(try EditorResize.preservingScale(from: from, to: CGRect(x: 0, y: 0, width: 1, height: 1), output: PixelSize(width: 160, height: 120)) == nil)
    #expect(throws: ProjectError.invalidDocument) {
        try EditorResize.preservingScale(from: CGRect(x: 0, y: 0, width: 1, height: 1), to: to, output: PixelSize(width: 1000, height: 1000))
    }
}

@Test func resizedProjectionRoundTripsCroppedAndStretchedCoordinates() {
    let source = CGRect(x: 200, y: 150, width: 240, height: 180)
    let projection = EditorImageProjection(source: source, destination: CGRect(x: 20, y: 40, width: 480, height: 90))
    #expect(projection.scaleX == 2 && projection.scaleY == 0.5)
    for point in [source.origin, CGPoint(x: source.maxX, y: source.maxY), CGPoint(x: 260, y: 180)] {
        #expect(projection.sourcePoint(projection.viewPoint(point)) == point)
    }
    #expect(projection.viewPoint(CGPoint(x: 260, y: 180)) == CGPoint(x: 140, y: 55))
    #expect(projection.distance(source.origin, CGPoint(x: 204, y: 150)) == 8)
    #expect(projection.distance(source.origin, CGPoint(x: 200, y: 166)) == 8)
}

@Test func resizedStoreRoundtripRecoveryAndOriginalRemainIntact() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Resize-Store-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), bytes = Data("synthetic-original".utf8)
    var document = ProjectDocument(title: "Resize", pixelSize: PixelSize(width: 640, height: 480)!)
    try await store.create(document, original: bytes, thumbnail: nil)
    document.resizedSize = PixelSize(width: 320, height: 240); document.revision = 1
    try await store.save(document, expectedGeneration: 0, thumbnail: nil)
    let loaded = try await ProjectStore(root: root).load(document.id)
    #expect(loaded.document == document && loaded.original == bytes)
    document.resizedSize = PixelSize(width: 1280, height: 960); document.revision = 2
    try await store.save(document, expectedGeneration: 1, thumbnail: nil)
    try Data("broken".utf8).write(to: root.appendingPathComponent("\(document.id.uuidString).snagforge/Revisions/2.json"))
    let recovered = try await ProjectStore(root: root).load(document.id)
    #expect(recovered.recovered && recovered.document.resizedSize == loaded.document.resizedSize && recovered.original == bytes)
}

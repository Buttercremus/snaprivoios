import Foundation
import Testing
@testable import SnagForgeDomain

private let originalCanvas = CGRect(x: 0, y: 0, width: 640, height: 480)
private let expandedCanvas = CGRect(x: -31, y: -21, width: 742, height: 552)

@Test func canvasGrowthRoundsOutwardAndNeverShrinks() {
    let ink = CGRect(x: -30.2, y: -20.8, width: 741, height: 551)
    #expect(EditorCanvasExtent.expanded(originalCanvas, including: ink) == expandedCanvas)
    #expect(EditorCanvasExtent.expanded(expandedCanvas, including: originalCanvas) == expandedCanvas)
    #expect(EditorCanvasExtent.expanded(originalCanvas, including: CGRect(x: 100, y: 100, width: 5, height: 5)) == originalCanvas)
}

@Test func canvasGrowthRejectsInvalidAndExcessiveDimensions() {
    for ink in [CGRect(x: -1, y: 0, width: 32769, height: 1), CGRect(x: 0, y: 0, width: 11000, height: 10000),
                CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1), CGRect.null] {
        #expect(EditorCanvasExtent.expanded(originalCanvas, including: ink) == nil)
    }
    #expect(EditorCanvasExtent.isValid(CGRect(x: -32767, y: 0, width: 32768, height: 1)))
    #expect(!EditorCanvasExtent.isValid(CGRect(x: -0.5, y: 0, width: 100, height: 100)))
}

@Test func canvasAndObjectsShareOneHistoryStep() {
    let shape = EditorObject(kind: .rectangle, start: CGPoint(x: 20, y: 30), end: CGPoint(x: 710, y: 530))
    var history = EditorHistory()
    let resize = PixelSize(width: 1484, height: 552)!
    history.commit([shape], canvasRect: expandedCanvas, crop: nil, resizedSize: resize)
    history.undo()
    #expect(history.objects.isEmpty && history.canvasRect == nil && history.resizedSize == nil && !history.canUndo)
    history.redo()
    #expect(history.objects == [shape] && history.canvasRect == expandedCanvas && history.resizedSize == resize)
    history.beginTransaction(); history.updateTransaction([shape.translated(by: CGSize(width: 1, height: 0))]); history.endTransaction()
    history.undo()
    #expect(history.objects == [shape] && history.canvasRect == expandedCanvas)
    history.commitCrop(CGRect(x: -10, y: 0, width: 600, height: 400))
    history.undo()
    #expect(history.canvasRect == expandedCanvas && history.crop == nil)
}

@Test func expandedProjectValidationMigrationAndCopies() throws {
    let size = PixelSize(width: 640, height: 480)!
    let document = ProjectDocument(title: "Canvas", pixelSize: size, canvasRect: expandedCanvas)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)) == document)
    #expect(document.outputRect == expandedCanvas && document.outputPixelSize == PixelSize(width: 742, height: 552))
    #expect(ProjectArchive.copy(document, id: UUID()).canvasRect == expandedCanvas)
    var invalid = document
    for rect in [CGRect(x: 1, y: 0, width: 640, height: 480), CGRect.zero, CGRect(x: 0, y: 0, width: 32769, height: 480)] {
        invalid.canvasRect = rect
        #expect(throws: ProjectError.invalidDocument) { try invalid.validated() }
    }
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    legacy["schemaVersion"] = 10
    #expect(throws: ProjectError.invalidDocument) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: legacy)) }
    legacy.removeValue(forKey: "canvasRect")
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: legacy))
    #expect(migrated.canvasRect == nil && migrated.outputRect == originalCanvas && migrated.schemaVersion == ProjectDocument.currentVersion)
}

@Test func cropAndOCRSupportNegativeCanvasCoordinates() throws {
    let crop = CGRect(x: -20, y: -10, width: 700, height: 510)
    #expect(EditorCrop.isValid(crop, in: expandedCanvas))
    #expect(EditorCrop.moved(crop, by: CGSize(width: -100, height: -100), in: expandedCanvas).origin == expandedCanvas.origin)
    let resized = EditorCrop.resized(crop, handle: .topLeft, by: CGSize(width: -100, height: -100), in: expandedCanvas)
    #expect(resized.origin == expandedCanvas.origin && resized.maxX == crop.maxX && resized.maxY == crop.maxY)
    let document = ProjectDocument(title: "Crop", pixelSize: PixelSize(width: 640, height: 480)!, crop: crop, canvasRect: expandedCanvas)
    #expect(try document.validated().outputRect == crop)
    let plan = try TextRecognitionPlan(sourceSize: document.pixelSize, crop: crop, canvasRect: expandedCanvas)
    #expect(plan.sourceArea == crop && plan.outputSize == PixelSize(width: 700, height: 510))
}

@Test func expandedCanvasSurvivesStoreReloadWithImmutableOriginal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasExtent-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root), original = Data("synthetic original".utf8)
    var document = ProjectDocument(title: "Canvas", pixelSize: PixelSize(width: 640, height: 480)!)
    try await store.create(document, original: original, thumbnail: nil)
    document.canvasRect = expandedCanvas; document.revision = 1
    try await store.save(document, expectedGeneration: 0, thumbnail: nil)
    let loaded = try await ProjectStore(root: root).load(document.id)
    #expect(loaded.document == document && loaded.original == original)
}

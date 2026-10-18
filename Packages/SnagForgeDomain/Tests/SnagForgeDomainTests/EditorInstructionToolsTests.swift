import Foundation
import Testing
@testable import SnagForgeDomain

private func instructionObjects() -> [EditorObject] {
    var marker = EditorObject(kind: .highlight, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 120, y: 60))
    marker.highlightStyle = EditorHighlightStyle()
    var freehand = EditorObject(kind: .highlight, start: CGPoint(x: 15, y: 30), end: CGPoint(x: 100, y: 80), lineWidth: 28)
    freehand.highlightStyle = EditorHighlightStyle(mode: .freehand, opacity: 0.45,
        points: [CGPoint(x: 15, y: 30), CGPoint(x: 80, y: 20), CGPoint(x: 100, y: 80)])
    let steps = EditorStepShape.allCases.enumerated().map { index, shape in
        var step = EditorObject(kind: .step, start: CGPoint(x: 30, y: 40), end: CGPoint(x: 102, y: 112))
        step.stepStyle = EditorStepStyle(index: index + 1, numbering: index.isMultiple(of: 2) ? .numbers : .letters, shape: shape,
                                        textColor: EditorColor(red: 0.1, green: 0.2, blue: 0.3))
        return step
    }
    return [marker, freehand] + steps
}

@Test func stepLabelsContinueAfterZAndRejectInvalidIndices() {
    for (index, expected) in [(1, "A"), (26, "Z"), (27, "AA"), (52, "AZ"), (53, "BA"), (702, "ZZ"), (703, "AAA"), (10000, "NTP")] {
        #expect(EditorStepNumbering.letters.label(for: index) == expected)
        #expect(EditorStepNumbering.numbers.label(for: index) == String(index))
    }
    #expect(EditorStepNumbering.letters.label(for: 0).isEmpty)
    #expect(EditorStepNumbering.numbers.label(for: 10001).isEmpty)
}

@Test func nextStepComesFromDocumentAndFollowsUndoWithoutRenumberingOthers() {
    let objects = instructionObjects()
    #expect(EditorSteps.nextIndex(in: objects, numbering: .numbers) == 4)
    #expect(EditorSteps.nextIndex(in: objects, numbering: .letters) == 5)
    var next = objects.last!; next.stepStyle?.index = 5
    var history = EditorHistory(objects: objects)
    history.commit(objects + [next.duplicated(by: .zero)])
    #expect(EditorSteps.nextIndex(in: history.objects, numbering: .letters) == 6)
    history.undo()
    #expect(history.objects == objects && EditorSteps.nextIndex(in: history.objects, numbering: .letters) == 5)
    history.redo()
    #expect(EditorSteps.nextIndex(in: history.objects, numbering: .letters) == 6)
    next.stepStyle?.index = EditorSteps.maximumIndex
    #expect(EditorSteps.nextIndex(in: [next], numbering: .letters) == nil)
    #expect(EditorSteps.nextIndex(in: [next], numbering: .numbers) == 1)
}

@Test func movingAndDuplicatingFreehandPreservesEveryPointAndStyle() {
    let object = instructionObjects()[1], delta = CGSize(width: 25, height: -10)
    let moved = object.translated(by: delta), copy = object.duplicated(by: delta)
    #expect(moved.id == object.id && copy.id != object.id)
    #expect(moved.highlightStyle?.points == object.highlightStyle?.points.map { CGPoint(x: $0.x + 25, y: $0.y - 10) })
    #expect(copy.highlightStyle == moved.highlightStyle && copy.lineWidth == object.lineWidth)
    #expect(copy.highlightStyle?.opacity == 0.45)
}

@Test func instructionFormatRoundtripAndLegacyMigrationAreStrict() throws {
    let document = ProjectDocument(title: "Anleitung", pixelSize: PixelSize(width: 640, height: 480)!, objects: instructionObjects())
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)) == document)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    json["schemaVersion"] = 5
    #expect(throws: ProjectError.invalidDocument) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
    json["objects"] = []
    for version in 1...5 {
        json["schemaVersion"] = version
        let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
        #expect(migrated.schemaVersion == ProjectDocument.currentVersion && migrated.objects.isEmpty && migrated.id == document.id)
    }
    json["schemaVersion"] = ProjectDocument.currentVersion + 1
    #expect(throws: ProjectError.unsupportedVersion) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
}

@Test func instructionValidationRejectsInvalidStylesAndOversizedPaths() {
    var document = ProjectDocument(title: "Anleitung", pixelSize: PixelSize(width: 640, height: 480)!, objects: instructionObjects())
    document.objects[0].highlightStyle?.opacity = .nan
    #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    document.objects = instructionObjects(); document.objects[1].highlightStyle?.points = []
    #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    document.objects = instructionObjects()
    document.objects[1].highlightStyle?.points = Array(repeating: .zero, count: EditorHighlightStyle.maximumPoints + 1)
    #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    document.objects = instructionObjects(); document.objects[2].stepStyle?.index = 0
    #expect(throws: ProjectError.invalidDocument) { try document.validated() }
    document.objects = instructionObjects(); document.objects[2].stepStyle?.textColor.red = 2
    #expect(throws: ProjectError.invalidDocument) { try document.validated() }
}

@Test func instructionObjectsSurviveStoreReopeningAndLayerOrder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Instructions-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let document = ProjectDocument(title: "Anleitung", pixelSize: PixelSize(width: 640, height: 480)!, objects: instructionObjects())
    try await ProjectStore(root: root).create(document, original: Data("synthetic source".utf8), thumbnail: nil)
    let loaded = try await ProjectStore(root: root).load(document.id)
    #expect(loaded.document == document)
    var redact = EditorObject(kind: .redact, start: .zero, end: CGPoint(x: 200, y: 200))
    redact.color = EditorColor(red: 0, green: 0, blue: 0)
    #expect(EditorLayers.paintOrder([redact] + document.objects).last?.id == redact.id)
}

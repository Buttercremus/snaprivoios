import Foundation
import Testing
@testable import SnagForgeDomain

@Test func duplicatePreservesAllFieldsAndUsesFreshIdentity() throws {
    for kind in [EditorObject.Kind.arrow, .text, .rectangle, .ellipse, .triangle, .diamond, .star, .callout, .blur] {
        var object = EditorObject(kind: kind, start: CGPoint(x: 90, y: 80), end: CGPoint(x: 20, y: 10), text: "Test\nText", fontSize: 37, lineWidth: 12, textWidth: 140)
        object.textHeight = 65; object.blurRadius = 19
        object.color = EditorColor(red: 0.2, green: 0.7, blue: 0.4)
        object.fill = EditorFill(isEnabled: true, color: EditorColor(red: 0.8, green: 0.3, blue: 0.2), opacity: 0.35)
        object.cornerRadius = 18; object.stroke = EditorStroke(isEnabled: false, style: .dashed)
        let delta = CGSize(width: -12, height: 17), copy = object.duplicated(by: delta)
        #expect(copy.id != object.id && copy.id != object.duplicated(by: delta).id)
        var expected = try JSONSerialization.jsonObject(with: JSONEncoder().encode(object.translated(by: delta))) as! [String: Any]
        var actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(copy)) as! [String: Any]
        expected.removeValue(forKey: "id"); actual.removeValue(forKey: "id")
        #expect(NSDictionary(dictionary: expected) == NSDictionary(dictionary: actual))
        #expect(object.start == CGPoint(x: 90, y: 80) && object.end == CGPoint(x: 20, y: 10))
    }
}

@Test func layerMovesKeepIDsAndOtherObjectsStable() {
    let a = EditorObject(kind: .rectangle, start: .zero), b = EditorObject(kind: .text, start: .zero), c = EditorObject(kind: .callout, start: .zero)
    let blur = EditorObject(kind: .blur, start: .zero), objects = [a, blur, b, c]
    #expect(EditorLayers.paintOrder(objects) == [blur, a, b, c])
    #expect(EditorLayers.moving(a.id, in: objects, direction: .forward) == [b, blur, a, c])
    #expect(EditorLayers.moving(a.id, in: objects, direction: .front) == [b, blur, c, a])
    #expect(EditorLayers.moving(c.id, in: objects, direction: .backward) == [a, blur, c, b])
    #expect(EditorLayers.moving(c.id, in: objects, direction: .back) == [c, blur, a, b])
    #expect(!EditorLayers.canMove(a.id, in: objects, direction: .back))
    #expect(!EditorLayers.canMove(c.id, in: objects, direction: .front))
    #expect(!EditorLayers.canMove(blur.id, in: objects, direction: .front))
    for id in [UUID(), a.id, blur.id] {
        #expect(EditorLayers.moving(id, in: objects, direction: .back) == objects)
    }
    let otherBlur = EditorObject(kind: .blur, start: CGPoint(x: 10, y: 20))
    let mixed = [a, blur, b, otherBlur, c]
    #expect(EditorLayers.paintOrder(EditorLayers.moving(blur.id, in: mixed, direction: .front)) == [otherBlur, blur, a, b, c])
}

@Test func duplicateOffsetStaysVisibleAndHandlesCropEdges() {
    let visible = CGRect(x: 100, y: 80, width: 200, height: 120), preferred = CGSize(width: 16, height: 16)
    #expect(EditorLayers.duplicateOffset(bounds: CGRect(x: 110, y: 90, width: 40, height: 30), visible: visible, preferred: preferred) == preferred)
    #expect(EditorLayers.duplicateOffset(bounds: CGRect(x: 260, y: 170, width: 40, height: 30), visible: visible, preferred: preferred) == CGSize(width: -16, height: -16))
    #expect(EditorLayers.duplicateOffset(bounds: visible, visible: visible, preferred: preferred) == .zero)
    #expect(EditorLayers.duplicateOffset(bounds: CGRect(x: 0, y: 0, width: 400, height: 300), visible: visible, preferred: preferred) == .zero)
    let outside = CGRect(x: 90, y: 60, width: 40, height: 30)
    let offset = EditorLayers.duplicateOffset(bounds: outside, visible: visible, preferred: preferred)
    #expect(visible.contains(outside.offsetBy(dx: offset.width, dy: offset.height)))
}

@Test func duplicateAndLayerMovesAreOneUndoStepAndNoOpsKeepRedo() {
    let a = EditorObject(kind: .rectangle, start: .zero), b = EditorObject(kind: .ellipse, start: .zero)
    let crop = CGRect(x: 10, y: 20, width: 100, height: 80), resized = PixelSize(width: 50, height: 40)!
    var history = EditorHistory(objects: [a, b], crop: crop, resizedSize: resized)
    let copy = a.duplicated(by: CGSize(width: 16, height: 16))
    history.commit([a, b, copy]); history.undo()
    #expect(history.objects == [a, b] && !history.canUndo && history.canRedo)
    history.redo(); #expect(history.objects == [a, b, copy])
    history.commit(EditorLayers.moving(copy.id, in: history.objects, direction: .back))
    #expect(history.objects == [copy, a, b] && history.crop == crop && history.resizedSize == resized)
    history.undo(); #expect(history.objects == [a, b, copy])
    history.commit(EditorLayers.moving(copy.id, in: history.objects, direction: .front))
    #expect(history.canRedo)
    history.redo(); #expect(history.objects == [copy, a, b])
}

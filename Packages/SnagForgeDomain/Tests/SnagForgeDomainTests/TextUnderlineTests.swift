import Foundation
import CoreGraphics
import Testing
@testable import SnagForgeDomain

@Test func underlinedTextPersistsMigratesAndStaysOnTextObjects() throws {
    func document(_ object: EditorObject) -> ProjectDocument { ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 400, height: 300)!, objects: [object]) }
    var text = EditorObject(kind: .text, start: CGPoint(x: 20, y: 20), text: "Hinweis")
    text.textStyle = EditorTextStyle(weight: .bold, underline: true)
    #expect(text.effectiveTextStyle.isUnderlined)
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document(text))).objects == [text])
    #expect(text.duplicated(by: CGSize(width: 10, height: 10)).effectiveTextStyle.isUnderlined)
    var callout = EditorObject(kind: .callout, start: CGPoint(x: 40, y: 40), text: "Klick")
    callout.textStyle = EditorTextStyle(underline: true)
    #expect(try document(callout).validated().objects == [callout])
    // Turning underline off restores the earlier encoding instead of storing false.
    var plain = EditorTextStyle(underline: true); plain.isUnderlined = false
    #expect(plain.underline == nil && plain == EditorTextStyle())
    var rectangle = EditorObject(kind: .rectangle, start: .zero, end: CGPoint(x: 20, y: 20))
    rectangle.textStyle = EditorTextStyle(underline: true)
    #expect(throws: ProjectError.invalidDocument) { try document(rectangle).validated() }
    // Older formats cannot carry underline; without it they migrate unchanged.
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document(text))) as! [String: Any]
    json["schemaVersion"] = 19
    #expect(throws: ProjectError.invalidDocument) { try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json)) }
    text.textStyle = EditorTextStyle(weight: .bold)
    json["objects"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([text]))
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: json))
    #expect(migrated.schemaVersion == 20 && migrated.objects == [text])
}

@Test func savedTextStylesCarryUnderline() throws {
    var text = EditorObject(kind: .text, start: .zero, text: "Hinweis")
    text.textStyle = EditorTextStyle(italic: true, underline: true)
    let saved = EditorSavedStyle(object: text)
    let other = try #require(saved.applying(to: EditorObject(kind: .text, start: CGPoint(x: 5, y: 5), text: "Andere")))
    #expect(other.effectiveTextStyle.isUnderlined && other.effectiveTextStyle.italic)
}

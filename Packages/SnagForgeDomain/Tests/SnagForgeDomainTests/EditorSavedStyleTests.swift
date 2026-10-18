import Foundation
import Testing
@testable import SnagForgeDomain

@Test func savedStylesPreserveContentIdentityAndGeometry() throws {
    for kind in [EditorObject.Kind.arrow, .text, .rectangle, .ellipse, .triangle, .diamond, .star, .callout, .blur, .redact] {
        var source = EditorObject(kind: kind, start: .zero, end: CGPoint(x: 90, y: 75), text: "PRIVATE SOURCE", fontSize: 51, lineWidth: 19)
        source.color = EditorColor(red: 0.2, green: 0.3, blue: 0.8)
        source.textStyle = EditorTextStyle(family: "Helvetica", weight: .bold, italic: true, alignment: .right)
        source.fill = EditorFill(isEnabled: true, color: source.color, opacity: 0.3)
        source.stroke = EditorStroke(isEnabled: false, style: .dashed); source.cornerRadius = 29; source.blurRadius = 31
        var target = EditorObject(kind: kind, start: CGPoint(x: 120, y: 80), end: CGPoint(x: 230, y: 180), text: "TARGET", textWidth: 150)
        target.calloutTip = CGPoint(x: 90, y: 210); target.textHeight = 75
        let style = EditorSavedStyle(object: source)
        let result = try #require(style.applying(to: target))
        #expect(result.id == target.id && result.kind == target.kind && result.text == target.text)
        #expect(result.start == target.start && result.end == target.end)
        #expect(result.textWidth == target.textWidth && result.textHeight == target.textHeight && result.calloutTip == target.calloutTip)
        if kind != .blur { #expect(result.color == source.color) }
        if kind == .text || kind == .callout { #expect(result.fontSize == 51 && result.textStyle == source.textStyle) }
        if kind.isShape { #expect(result.fill == source.fill && result.stroke == source.stroke && result.lineWidth == 19) }
        if kind == .rectangle { #expect(result.cornerRadius == 29) }
        if kind == .blur { #expect(result.blurRadius == 31 && result.color == target.color) }
        let data = try JSONEncoder().encode(style)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("PRIVATE SOURCE") && !json.contains("start") && !json.contains("calloutTip"))
        #expect(try JSONDecoder().decode(EditorSavedStyle.self, from: data) == style)
    }
}

@Test func shapeStylesCanCrossShapesButNotOtherToolFamilies() throws {
    var rectangle = EditorObject(kind: .rectangle, start: .zero)
    rectangle.cornerRadius = 23
    let style = EditorSavedStyle(object: rectangle)
    let ellipse = EditorObject(kind: .ellipse, start: .zero)
    #expect(try #require(style.applying(to: ellipse)).kind == .ellipse)
    #expect(style.applying(to: ellipse)?.cornerRadius == nil)
    #expect(style.applying(to: EditorObject(kind: .text, start: .zero)) == nil)
    #expect(EditorSavedStyle(object: ellipse).applying(to: rectangle)?.cornerRadius == 23)
    #expect(EditorSavedStyle(object: ellipse).applying(to: ellipse) == ellipse)
}

@Test func highlightStyleDoesNotCopyPathsOrChangeMode() throws {
    var source = EditorObject(kind: .highlight, start: .zero, lineWidth: 42)
    source.highlightStyle = EditorHighlightStyle(mode: .rectangle, opacity: 0.6)
    var target = EditorObject(kind: .highlight, start: CGPoint(x: 30, y: 40))
    target.highlightStyle = EditorHighlightStyle(mode: .freehand, points: [target.start, CGPoint(x: 80, y: 50)])
    let result = try #require(EditorSavedStyle(object: source).applying(to: target))
    #expect(result.highlightStyle?.points == target.highlightStyle?.points && result.highlightStyle?.mode == .freehand)
    #expect(result.highlightStyle?.opacity == 0.6 && result.lineWidth == 42)
}

@Test func stepStylesPreserveNumberingIndexAndCenter() throws {
    var source = EditorObject(kind: .step, start: .zero, end: CGPoint(x: 100, y: 100))
    source.stepStyle = EditorStepStyle(index: 8, numbering: .numbers, shape: .diamond, textColor: EditorColor(red: 0, green: 0, blue: 0))
    var target = EditorObject(kind: .step, start: CGPoint(x: 160, y: 110), end: CGPoint(x: 220, y: 170))
    target.stepStyle = EditorStepStyle(index: 27, numbering: .letters)
    let style = EditorSavedStyle(object: source)
    let result = try #require(style.applying(to: target))
    #expect(result.stepStyle?.label == "AA" && result.stepStyle?.shape == .diamond)
    #expect(result.rect.midX == target.rect.midX && result.rect.midY == target.rect.midY)
    #expect(result.rect.size == CGSize(width: 100, height: 100))
    let json = try #require(String(data: JSONEncoder().encode(style), encoding: .utf8))
    #expect(!json.contains("index") && !json.contains("numbering"))
}

@Test func styleLibraryNamingLimitsAndMutationsAreAtomic() throws {
    let style = EditorSavedStyle(object: EditorObject(kind: .arrow, start: .zero))
    let item = EditorNamedStyle(name: "  Support  ", style: style)
    var library = EditorStyleLibrary()
    try library.add(item)
    #expect(library.styles.first?.name == "Support")
    let original = library
    #expect(throws: EditorStyleLibraryError.duplicateName) { try library.add(EditorNamedStyle(name: "support", style: style)) }
    #expect(throws: EditorStyleLibraryError.invalidName) { try library.rename(item.id, to: " \n ") }
    #expect(throws: EditorStyleLibraryError.invalidName) { try library.rename(item.id, to: String(repeating: "x", count: 81)) }
    #expect(throws: EditorStyleLibraryError.invalidName) { try library.rename(item.id, to: "a" + String(repeating: "\u{301}", count: 1024)) }
    #expect(library == original)
    // The same visible name is useful in a different tool group.
    try library.add(EditorNamedStyle(name: "Support", style: EditorSavedStyle(object: EditorObject(kind: .text, start: .zero))))
    try library.rename(item.id, to: "Handbuch")
    #expect(library.styles[0].id == item.id && library.styles[0].name == "Handbuch")
    library.remove(item.id)
    #expect(library.styles.count == 1)
    for index in 1..<EditorStyleLibrary.maximumStyles {
        try library.add(EditorNamedStyle(name: "Arrow \(index)", style: style))
    }
    #expect(throws: EditorStyleLibraryError.limitReached) { try library.add(EditorNamedStyle(name: "Too many", style: style)) }
}

@Test func invalidAndFutureStyleLibrariesAreRejected() throws {
    var object = EditorObject(kind: .text, start: .zero)
    object.fontSize = .infinity
    #expect(!EditorSavedStyle(object: object).isValid)
    object.fontSize = 30; object.color.red = 2
    #expect(!EditorSavedStyle(object: object).isValid)
    let future = Data(#"{"version":2,"styles":[]}"#.utf8)
    #expect(throws: EditorStyleLibraryError.invalidLibrary) { try JSONDecoder().decode(EditorStyleLibrary.self, from: future).validated() }
    var library = EditorStyleLibrary()
    #expect(throws: EditorStyleLibraryError.invalidLibrary) { try library.add(EditorNamedStyle(name: "Invalid", style: EditorSavedStyle(object: object))) }
    #expect(library.styles.isEmpty)
}

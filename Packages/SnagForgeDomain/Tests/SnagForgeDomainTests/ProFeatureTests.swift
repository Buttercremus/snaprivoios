import Foundation
import Testing
@testable import SnagForgeDomain

@Test func paidObjectsAndToolsHaveExplicitBoundaries() {
    for kind in [EditorObject.Kind.arrow, .text, .rectangle, .ellipse, .redact, .blur] {
        #expect(ProFeature.required(for: kind) == nil)
    }
    for kind in [EditorObject.Kind.callout, .highlight, .step, .triangle, .diamond, .star] {
        #expect(ProFeature.required(for: kind) == .advancedEditing)
    }
    #expect(ProFeature.required(for: EditorObject.Kind.image) == .insertedImages)
    #expect(ProFeature.required(for: AnnotationTool.callout) == .advancedEditing)
    #expect(ProFeature.required(for: AnnotationTool.steps) == .advancedEditing)
    #expect(ProFeature.required(for: AnnotationTool.selection) == nil)
    var arrow = EditorObject(kind: .arrow, start: .zero)
    #expect(ProFeature.required(for: arrow) == nil)
    arrow.drawingStyle = .handDrawn
    #expect(ProFeature.required(for: arrow) == .advancedEditing)
}

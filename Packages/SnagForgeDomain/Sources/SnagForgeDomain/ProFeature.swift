/// Product boundaries. Reading, rendering, exporting and recovering existing data
/// never require an entitlement. Callers authorize new paid operations separately.
public enum ProFeature: String, CaseIterable, Sendable {
    case textRecognition, scrolling, advancedEditing, savedStyles, insertedImages
    case presentation, organization, guides, video

    public static func required(for kind: EditorObject.Kind) -> Self? {
        switch kind {
        case .callout, .highlight, .step, .triangle, .diamond, .star: .advancedEditing
        case .image: .insertedImages
        default: nil
        }
    }

    public static func required(for tool: AnnotationTool) -> Self? {
        switch tool {
        case .callout, .highlight, .steps: .advancedEditing
        default: nil
        }
    }

    public static func required(for object: EditorObject) -> Self? {
        required(for: object.kind) ?? (object.effectiveDrawingStyle == .handDrawn ? .advancedEditing : nil)
    }
}

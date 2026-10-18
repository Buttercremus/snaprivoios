import SwiftUI
import SnagForgeDomain

struct EditorObjectList: View {
    @Bindable var model: EditorModel
    @State private var expanded = true
    @State private var renaming: EditorObject?
    private var objects: [EditorObject] { EditorLayers.paintOrder(model.history.objects).reversed() }
    var body: some View {
        DisclosureGroup(String(localized: "Objekte (\(objects.count))"), isExpanded: $expanded) {
            List(selection: Binding(get: { model.selectedIDs }, set: { model.selectObjectsFromList($0) })) {
                ForEach(objects) { object in
                    Text(object.name ?? object.kind.objectTitle)
                        .lineLimit(1).tag(object.id)
                        .accessibilityLabel(object.name ?? object.kind.objectTitle)
                        .accessibilityValue(model.selectedIDs.contains(object.id) ? String(localized: "Ausgewählt") : "")
                        .contextMenu {
                            Button(String(localized: "Umbenennen …")) { renaming = object }
                            Button(String(localized: "Nach vorn")) { model.selectObjectFromList(object.id); model.moveSelection(.forward) }
                            Button(String(localized: "Nach hinten")) { model.selectObjectFromList(object.id); model.moveSelection(.backward) }
                        }
                }
            }.frame(height: min(190, max(64, CGFloat(objects.count) * 26 + 12)))
                .accessibilityIdentifier("editor.objects")
                .onDeleteCommand { if model.canActOnSelection { model.removeSelection() } }
            Button(String(localized: "Alle auswählen")) { model.selectAllObjects() }
            HStack(spacing: 12) {
                Button(String(localized: "Umbenennen …"), systemImage: "pencil") { renaming = model.selectedObject }
                    .disabled(model.selectedObject == nil)
                Spacer()
                Button(String(localized: "Nach vorn"), systemImage: "arrow.up") { model.moveSelection(.forward) }
                    .disabled(!model.canMoveSelection(.forward))
                Button(String(localized: "Nach hinten"), systemImage: "arrow.down") { model.moveSelection(.backward) }
                    .disabled(!model.canMoveSelection(.backward))
                Button(String(localized: "Löschen"), systemImage: "trash") { model.removeSelection() }
                    .disabled(!model.canActOnSelection)
            }.labelStyle(.iconOnly).buttonStyle(.borderless)
            Text(String(localized: "Vorn steht oben. Abdeckungen bleiben über allen anderen Objekten."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12)
            .disabled(model.isCanvasGestureActive || model.cropDraft != nil || model.isSwitchingImage)
            .sheet(item: $renaming) { object in
                ProjectRenameSheet(title: object.name ?? object.kind.objectTitle, heading: String(localized: "Objekt umbenennen"), prompt: String(localized: "Objektname")) { name in
                    guard model.renameObject(object.id, name: name) else { return false }
                    return await model.flush()
                }
            }
    }
}

private extension EditorObject.Kind {
    var objectTitle: String {
        switch self {
        case .image: String(localized: "Bild")
        case .arrow: String(localized: "Pfeil")
        case .text: String(localized: "Text")
        case .rectangle: String(localized: "Rechteck")
        case .ellipse: String(localized: "Ellipse")
        case .triangle: String(localized: "Dreieck")
        case .diamond: String(localized: "Raute")
        case .star: String(localized: "Stern")
        case .callout: String(localized: "Callout")
        case .blur: String(localized: "Unschärfe")
        case .redact: String(localized: "Abdecken")
        case .highlight: String(localized: "Markieren")
        case .step: String(localized: "Schrittnummer")
        }
    }
}

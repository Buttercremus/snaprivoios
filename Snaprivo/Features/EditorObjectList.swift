import SwiftUI
import SnagForgeDomain

struct EditorObjectList: View {
    @Bindable var model: EditorModel
    @State private var expanded = false
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
            Toggle(String(localized: "Einrasten"), isOn: $model.snapsToObjects)
                .toggleStyle(.switch).controlSize(.small).accessibilityIdentifier("editor.snapping")
            if model.selectedIDs.count > 1 { EditorArrangementControls(model: model) }
            Button(String(localized: "Alle auswählen")) { model.selectAllObjects() }
            Button(String(localized: "Im Bild bearbeiten"), systemImage: "viewfinder") { model.focusRequest += 1 }
                .disabled(!model.canNudgeSelection)
                .help(String(localized: "Pfeiltasten verschieben um 1 Ausgabepixel, mit Umschalt um 10. Im Text bewegen sie den Cursor."))
            HStack(spacing: 8) {
                Button(String(localized: "Umbenennen …"), systemImage: "pencil") { renaming = model.selectedObject }
                    .disabled(model.selectedObject == nil)
                Spacer()
                moveButton(.front)
                moveButton(.forward)
                moveButton(.backward)
                moveButton(.back)
                Button(String(localized: "Löschen"), systemImage: "trash") { model.removeSelection() }
                    .disabled(!model.canActOnSelection)
            }.labelStyle(.iconOnly).buttonStyle(.borderless)
            Text(String(localized: "Vorn steht oben. Abdeckungen bleiben über allen anderen Objekten."))
                .font(.caption).foregroundStyle(.secondary)
            if model.selectedObject?.kind == .blur {
                Text(String(localized: "Unschärfe wirkt auf das Original unter den Markierungen. Anordnen ändert die Reihenfolge mehrerer Unschärfebereiche."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(12)
            .disabled(model.isCanvasGestureActive || model.cropDraft != nil || model.isSwitchingImage)
            .sheet(item: $renaming) { object in
                ProjectRenameSheet(title: object.name ?? object.kind.objectTitle, heading: String(localized: "Objekt umbenennen"), prompt: String(localized: "Objektname")) { name in
                    guard model.renameObject(object.id, name: name) else { return false }
                    return await model.flush()
                }
            }
    }
    private func moveButton(_ direction: EditorLayerMove) -> some View {
        Button(direction.title, systemImage: direction.symbol) { model.moveSelection(direction) }
            .disabled(!model.canMoveSelection(direction))
            .help(direction.title)
            .accessibilityIdentifier("editor.object.\(direction.identifier)")
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
        case .pen: String(localized: "Stift")
        case .spotlight: String(localized: "Spotlight")
        case .magnifier: String(localized: "Lupe")
        case .blur: String(localized: "Unschärfe")
        case .redact: String(localized: "Abdecken")
        case .highlight: String(localized: "Markieren")
        case .step: String(localized: "Schrittnummer")
        }
    }
}

import SwiftUI

struct QuickCaptureView: View {
    let workspace: WorkspaceModel
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDiscarding = false
    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Aufnahme bereit")).font(.headline)
            Image(decorative: model.image, scale: 1).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(String(localized: "Vorschau der neuen Aufnahme"))
            HStack {
                Button(String(localized: "Kopieren"), systemImage: "doc.on.doc") { model.copyPNG() }.keyboardShortcut("c")
                Button(String(localized: "Markieren"), systemImage: "pencil.tip") { workspace.editQuickCapture(); dismiss() }.keyboardShortcut(.defaultAction)
                PinImageButton(model: model, size: workspace.preferences.toolbarSize)
                Spacer()
                Button(String(localized: "Verwerfen"), systemImage: "trash") {
                    isDiscarding = true
                    Task { await workspace.discardQuickCapture(); isDiscarding = false; if workspace.quickCapture == nil { dismiss() } }
                }.disabled(isDiscarding)
            }
            HStack {
                Text(model.copyState == .copied ? String(localized: "Kopiert") : String(localized: "In der Bibliothek gesichert. Verwerfen verschiebt die Aufnahme in den Papierkorb."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }.padding(20).frame(minWidth: 600, idealWidth: 720, minHeight: 360, idealHeight: 520)
    }
}

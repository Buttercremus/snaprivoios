import SwiftUI
import SnagForgeDomain

struct RedactionSuggestionView: View {
    @State private var model: RedactionSuggestionModel
    @Environment(\.dismiss) private var dismiss
    init(editor: EditorModel) { _model = State(initialValue: RedactionSuggestionModel(editor: editor)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Sensible Daten finden")).font(.title2.bold())
            Text(String(localized: "Die Prüfung erfolgt lokal. Vorschläge sind Hinweise und werden erst nach deiner Auswahl übernommen."))
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Vorschläge")).font(.headline)
                    Text(String(localized: "Markierungen decken zur Sicherheit die erkannte Textzeile vollständig ab."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let notice = model.notice {
                        Text(notice).foregroundStyle(.orange).font(.callout)
                    }
                    if model.suggestions.isEmpty && !model.isBusy {
                        Text(String(localized: "Noch keine Vorschläge."))
                            .foregroundStyle(.secondary).font(.callout)
                    }
                    List(model.suggestions) { suggestion in
                        Button { model.toggle(suggestion.id) } label: {
                            Label {
                                Text(suggestion.categories.map(\.displayName).joined(separator: ", "))
                            } icon: {
                                Image(systemName: model.selected.contains(suggestion.id) ? "checkmark.square.fill" : "square")
                            }
                        }.buttonStyle(.plain)
                    }.frame(width: 220)
                }
            }
            if model.isBusy { ProgressView(String(localized: "Bild wird lokal geprüft …")) }
            HStack {
                Button(String(localized: "Abbrechen")) { model.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Erneut versuchen")) { model.retry() }.disabled(model.isBusy)
                Button(String(localized: "Auswahl abdecken")) { if model.apply() { dismiss() } }
                    .buttonStyle(.borderedProminent).disabled(!model.canApply)
            }
        }
        .padding(24).frame(width: 760, height: 560)
        .task { model.start() }
        .onDisappear { model.cancel() }
    }
    @ViewBuilder private var preview: some View {
        if let image = model.preview {
            GeometryReader { geometry in
                let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                    ForEach(model.suggestions) { suggestion in
                        let area = model.previewSourceArea
                        Rectangle().fill(.red.opacity(model.selected.contains(suggestion.id) ? 0.24 : 0.08))
                            .overlay(Rectangle().stroke(.red, lineWidth: 1))
                            .frame(width: suggestion.bounds.width / area.width * size.width, height: suggestion.bounds.height / area.height * size.height)
                            .offset(x: (suggestion.bounds.minX - area.minX) / area.width * size.width, y: (suggestion.bounds.minY - area.minY) / area.height * size.height)
                    }
                }.frame(width: size.width, height: size.height)
            }
        } else { ContentUnavailableView(String(localized: "Bildvorschau"), systemImage: "eye.slash") }
    }
}

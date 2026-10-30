import SwiftUI
import SnagForgeDomain

struct EditorSavedStyles: View {
    let model: EditorModel
    let preferences: AppPreferences
    var compact = false
    @State private var saving: SavedStyleDraft?
    @State private var isManaging = false
    private var matchingStyles: [EditorNamedStyle] {
        let family = model.currentSavedStyle?.family
        return preferences.savedStyles.filter { $0.style.family == family }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                if compact, let error = preferences.styleLibraryError { Text(error) }
                if !matchingStyles.isEmpty {
                    Section(String(localized: "Stil anwenden")) {
                        ForEach(matchingStyles) { item in
                            Button(item.name) { model.applySavedStyle(item.style) }
                        }
                    }
                    Divider()
                }
                Button(String(localized: "Aktuellen Stil speichern …"), systemImage: "plus") {
                    guard model.requestFeature(.savedStyles) else { return }
                    if let style = model.currentSavedStyle { saving = SavedStyleDraft(style: style) }
                }
                .disabled(model.currentSavedStyle == nil || preferences.styleLibraryError != nil
                    || preferences.savedStyles.count >= EditorStyleLibrary.maximumStyles)
                Button(String(localized: "Stile verwalten …"), systemImage: "slider.horizontal.3") { isManaging = true }
            } label: {
                if compact {
                    Label(model.hasProAccess() ? String(localized: "Eigene Stile") : String(localized: "Eigene Stile · Pro"), systemImage: "paintpalette")
                        .labelStyle(.iconOnly)
                } else {
                    Label(model.hasProAccess() ? String(localized: "Eigene Stile") : String(localized: "Eigene Stile · Pro"), systemImage: "paintpalette")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .menuStyle(.borderedButton).controlSize(.small)
            .accessibilityIdentifier("editor.savedStyles.menu")
            .accessibilityLabel(model.hasProAccess() ? String(localized: "Eigene Stile") : String(localized: "Eigene Stile · Pro"))
            .help(String(localized: "Werkzeugstil speichern, anwenden oder verwalten"))
            if !compact, let error = preferences.styleLibraryError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if !compact, preferences.savedStyles.count >= EditorStyleLibrary.maximumStyles {
                Text(String(localized: "Es sind höchstens 100 eigene Stile möglich.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $saving) { draft in
            EditorStyleNameSheet(title: String(localized: "Stil speichern"), name: "") { name in
                guard model.requestFeature(.savedStyles) else { throw CocoaError(.userCancelled) }
                try preferences.saveStyle(name: name, style: draft.style)
            }
        }
        .sheet(isPresented: $isManaging) { EditorStyleManager(preferences: preferences) }
    }
}

private struct SavedStyleDraft: Identifiable {
    let id = UUID()
    let style: EditorSavedStyle
}

struct EditorStyleNameSheet: View {
    let title: String
    let save: (String) throws -> Void
    @State private var name: String
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    init(title: String, name: String, save: @escaping (String) throws -> Void) {
        self.title = title; self._name = State(initialValue: name); self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField(String(localized: "Stilname"), text: $name)
                .textFieldStyle(.roundedBorder).focused($nameFocused).onSubmit(submit)
                .accessibilityIdentifier("editor.savedStyles.name")
            Text(String(localized: "Bis zu 80 Zeichen. Namen müssen innerhalb einer Werkzeuggruppe eindeutig sein."))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("editor.savedStyles.error") }
            HStack {
                Spacer()
                Button(String(localized: "Abbrechen")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Speichern"), action: submit).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || name.trimmingCharacters(in: .whitespacesAndNewlines).count > EditorStyleLibrary.maximumNameLength)
                    .accessibilityIdentifier("editor.savedStyles.save")
            }
        }.padding(24).frame(width: 360).onAppear { nameFocused = true }
    }
    private func submit() {
        do { try save(name); dismiss() }
        catch { self.error = styleErrorMessage(error) }
    }
}

struct EditorStyleManager: View {
    let preferences: AppPreferences
    @State private var renaming: EditorNamedStyle?
    @State private var deleting: EditorNamedStyle?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Eigene Stile verwalten")).font(.headline)
            Text(String(localized: "Gespeicherte Stile gelten für alle Bildprojekte. Bereits angewendete Objekte bleiben beim Umbenennen oder Löschen erhalten."))
                .font(.callout).foregroundStyle(.secondary)
            if preferences.savedStyles.isEmpty {
                ContentUnavailableView(String(localized: "Noch keine eigenen Stile"), systemImage: "paintpalette",
                    description: Text(String(localized: "Wähle im Editor ein Werkzeug und speichere dessen aktuellen Stil.")))
                    .frame(height: 160)
            } else {
                List(preferences.savedStyles) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text(item.style.family.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button { renaming = item } label: { Image(systemName: "pencil") }
                            .accessibilityLabel(String(localized: "Stil \(item.name) umbenennen"))
                            .help(String(localized: "Umbenennen …"))
                        Button(role: .destructive) { deleting = item } label: { Image(systemName: "trash") }
                            .accessibilityLabel(String(localized: "Stil \(item.name) löschen"))
                            .help(String(localized: "Löschen"))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityElement(children: .contain)
                    .padding(.vertical, 4)
                }.frame(height: 240)
            }
            if let error = error ?? preferences.styleLibraryError { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button(String(localized: "Fertig")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 420)
        .sheet(item: $renaming) { item in
            EditorStyleNameSheet(title: String(localized: "Stil umbenennen"), name: item.name) { name in
                try preferences.renameStyle(item.id, to: name)
            }
        }
        .confirmationDialog(String(localized: "Stil löschen?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let deleting {
                    Button(String(localized: "Löschen"), role: .destructive) {
                        do { try preferences.removeStyle(deleting.id) }
                        catch { self.error = styleErrorMessage(error) }
                        self.deleting = nil
                    }
                }
                Button(String(localized: "Abbrechen"), role: .cancel) { deleting = nil }
            } message: { Text(String(localized: "Bereits angewendete Objekte werden nicht verändert.")) }
    }
}

private func styleErrorMessage(_ error: any Error) -> String {
    switch error as? EditorStyleLibraryError {
    case .invalidName: String(localized: "Bitte einen Namen mit 1 bis 80 Zeichen ohne Steuerzeichen eingeben.")
    case .duplicateName: String(localized: "Für dieses Werkzeug gibt es bereits einen Stil mit diesem Namen.")
    case .limitReached: String(localized: "Es sind höchstens 100 eigene Stile möglich.")
    default: String(localized: "Der Stil konnte nicht gespeichert werden. Vorhandene Stile bleiben erhalten.")
    }
}

private extension EditorStyleFamily {
    var title: String {
        switch self {
        case .arrow: String(localized: "Pfeil")
        case .text: String(localized: "Text")
        case .shape: String(localized: "Formen")
        case .callout: String(localized: "Callout")
        case .pen: String(localized: "Stift")
        case .spotlight: String(localized: "Spotlight")
        case .magnifier: String(localized: "Lupe")
        case .blur: String(localized: "Unschärfe")
        case .redact: String(localized: "Abdecken")
        case .highlight: String(localized: "Markieren")
        case .step: String(localized: "Liste")
        }
    }
}

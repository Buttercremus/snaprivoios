import SwiftUI
import SnagForgeDomain

struct ProPaywallView: View {
    @Bindable var model: ProPurchaseModel
    var feature: ProFeature?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Snaprivo Pro", systemImage: "sparkles").font(.largeTitle.bold())
            Text(String(localized: "Einmal kaufen. Pro dauerhaft freischalten.")).font(.title3)
            Text(String(localized: "Lange Inhalte aufnehmen, verständliche Anleitungen erstellen und Abläufe mit Bild und Ton erklären."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let feature, !model.hasPro {
                Label(String(localized: "Pro-Funktion: \(feature.title)"), systemImage: "lock")
                    .font(.callout).accessibilityIdentifier("pro.requestedFeature")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    benefit("text.viewfinder", String(localized: "Texterkennung"), String(localized: "Text aus Bildern und Bereichen kopieren, Bildinhalte in der Bibliothek durchsuchen."))
                    benefit("arrow.down.square", String(localized: "Scroll-Aufnahmen"), String(localized: "Lange Webseiten und Inhalte in einer Aufnahme festhalten."))
                    benefit("list.number", String(localized: "Anleitungen"), String(localized: "Mehrere Bilder zu bearbeitbaren Schritten verbinden und als PDF oder Markdown ausgeben."))
                    benefit("video", String(localized: "Video mit Ton und Schnitt"), String(localized: "Bereich, Fenster oder Bildschirm mit Systemton und Mikrofon aufnehmen, trimmen und als MP4 speichern."))
                    benefit("paintbrush", String(localized: "Erweiterte Bildwerkzeuge"), String(localized: "Callouts, Schrittnummern, Textmarker, zusätzliche Formen, handgezeichnete Stile, eigene Vorlagen und eingefügte Bilder."))
                    benefit("square.stack", String(localized: "Gestaltung und Ordnung"), String(localized: "Präsentationshintergründe, Tags und Sammlungen für wiederkehrende Arbeit."))
                    DisclosureGroup(String(localized: "Das bleibt kostenlos")) {
                        Text(String(localized: "Unbegrenzte Screenshots, Schnellvorschau, Anheften, grundlegende Bildwerkzeuge, Abdecken, Objektliste, lokale Bibliothek, Titelsuche, Favoriten und PNG/JPEG/Bild-PDF. Vorhandene Inhalte öffnen, exportieren, sichern, wiederherstellen und löschen bleibt immer möglich."))
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }.padding(.trailing, 8)
            }.frame(height: 240)
            Divider()
            if model.hasPro {
                Label(String(localized: "Pro ist aktiviert"), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if let offer = model.offer {
                VStack(alignment: .leading, spacing: 4) {
                    if offer.laterPrice != nil {
                        Text(String(localized: "Einführungspreis")).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    }
                    Text(String(localized: "\(offer.price) einmalig")).font(.title2.bold())
                        .accessibilityIdentifier("pro.price")
                    if let laterPrice = offer.laterPrice {
                        Text(String(localized: "Nach der Einführung: \(laterPrice) einmalig. Für deinen Kauf fallen später keine weiteren Zahlungen an."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if !model.isLoading {
                Text(String(localized: "Der Kauf ist im Store gerade nicht verfügbar. Du kannst Snaprivo Free weiter nutzen und den Preis erneut laden."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(String(localized: "Kein Abo. Kein eigenes Konto. Die enthaltenen Pro-Funktionen bleiben dauerhaft freigeschaltet."))
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let message = model.message { Text(message).foregroundStyle(.secondary) }
            if model.isLoading || model.isBusy { ProgressView().controlSize(.small) }
            HStack {
                Button(String(localized: "Käufe wiederherstellen")) { Task { await model.restore() } }
                    .disabled(model.isBusy || model.isLoading)
                Spacer()
                Button(String(localized: "Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
                if !model.hasPro {
                    Button { Task { await model.buy() } } label: {
                        Text(model.offer.map { String(localized: "Pro freischalten · \($0.price)") } ?? String(localized: "Preis nicht verfügbar"))
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!model.purchasesEnabled || model.offer == nil || model.isBusy || model.isLoading)
                    .accessibilityIdentifier("pro.buy")
                }
            }
            if !model.hasPro {
                Button(String(localized: "Erneut laden")) { Task { await model.reload() } }
                    .disabled(model.isBusy || model.isLoading).font(.caption)
            }
        }.padding(28).frame(width: 590)
            .task { await model.start() }
    }
    private func benefit(_ symbol: String, _ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(description).font(.callout).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

extension ProFeature {
    var title: String {
        switch self {
        case .textRecognition: String(localized: "Texterkennung und Inhaltssuche")
        case .scrolling: String(localized: "Scroll-Aufnahmen")
        case .advancedEditing: String(localized: "Erweiterte Bildwerkzeuge")
        case .savedStyles: String(localized: "Eigene Stilvorlagen")
        case .insertedImages: String(localized: "Bilder als Objekte einfügen")
        case .presentation: String(localized: "Präsentationshintergründe")
        case .organization: String(localized: "Tags und Sammlungen")
        case .guides: String(localized: "Anleitungen aus mehreren Bildern")
        case .video: String(localized: "Video mit Ton und Schnitt")
        }
    }
}

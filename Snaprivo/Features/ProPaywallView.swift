import SwiftUI
import SnagForgeDomain

struct ProPaywallView: View {
    @Bindable var model: ProPurchaseModel
    var feature: ProFeature?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let feature, !model.hasPro {
                        Label(String(localized: "Pro-Funktion: \(feature.title)"), systemImage: "sparkles")
                            .font(.callout.weight(.medium)).foregroundStyle(.tint)
                            .accessibilityIdentifier("pro.requestedFeature")
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 24) {
                        benefit("text.viewfinder", String(localized: "Texterkennung"), String(localized: "Text kopieren und Bildinhalte durchsuchen."))
                        benefit("arrow.down.square", String(localized: "Scroll-Aufnahmen"), String(localized: "Lange Seiten in einer Aufnahme festhalten."))
                        benefit("list.number", String(localized: "Anleitungen"), String(localized: "Schritte erklären und als PDF oder Markdown teilen."))
                        benefit("video", String(localized: "Video mit Ton und Schnitt"), String(localized: "Aufnehmen, schneiden und mit Zooms gestalten."))
                        benefit("paintbrush", String(localized: "Erweiterte Bildwerkzeuge"), String(localized: "Mit Callouts, Markierungen und eigenen Stilen erklären."))
                        benefit("square.stack", String(localized: "Gestaltung und Ordnung"), String(localized: "Hintergründe, Tags und Sammlungen für deine Arbeit."))
                    }
                    DisclosureGroup(String(localized: "Das bleibt kostenlos")) {
                        Text(String(localized: "Unbegrenzte Screenshots, Schnellvorschau, Anheften, grundlegende Bildwerkzeuge, Abdecken, Objektliste, lokale Bibliothek, Titelsuche, Favoriten und PNG/JPEG/Bild-PDF. Vorhandene Inhalte öffnen, exportieren, sichern, wiederherstellen und löschen bleibt immer möglich."))
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }.font(.callout).foregroundStyle(.secondary)
                }.padding(24)
            }
            Divider()
            purchaseArea.padding(24).background(.background.secondary)
        }
        .frame(width: 640, height: 660)
        .task { await model.start() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(.tint)
                    .frame(width: 56, height: 56).background(.tint.opacity(0.1), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snaprivo Pro").font(.title2.weight(.semibold))
                    Text(String(localized: "Einmal kaufen. Dauerhaft nutzen."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(String(localized: "Mehr aus jeder Aufnahme."))
                .font(.system(size: 28, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Halte fest, was wichtig ist. Erkläre es mit Bild, Video und klaren Schritten."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var purchaseArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasPro {
                Label(String(localized: "Pro ist aktiviert"), systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
            } else if let offer = model.offer {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(offer.price).font(.system(size: 28, weight: .semibold))
                        .accessibilityIdentifier("pro.price")
                    Text(String(localized: "einmalig")).foregroundStyle(.secondary)
                    Spacer()
                    if offer.laterPrice != nil {
                        Text(String(localized: "Einführungspreis")).font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.tint.opacity(0.1), in: .capsule).foregroundStyle(.tint)
                    }
                }
                if let laterPrice = offer.laterPrice {
                    Text(String(localized: "Nach der Einführung: \(laterPrice) einmalig. Für deinen Kauf fallen später keine weiteren Zahlungen an."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else if !model.isLoading {
                Label(String(localized: "Der Preis ist gerade nicht verfügbar."), systemImage: "tag")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(String(localized: "Kein Abo. Kein eigenes Konto. Pro bleibt dauerhaft freigeschaltet."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 12) {
                Button(String(localized: "Käufe wiederherstellen")) { Task { await model.restore() } }
                    .buttonStyle(.link).disabled(model.isBusy || model.isLoading)
                if model.isLoading || model.isBusy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                Button(String(localized: "Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
                if !model.hasPro {
                    if let offer = model.offer {
                        Button(String(localized: "Pro freischalten · \(offer.price)")) { Task { await model.buy() } }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .disabled(!model.purchasesEnabled || model.isBusy || model.isLoading)
                            .accessibilityIdentifier("pro.buy")
                    } else {
                        Button(String(localized: "Preis laden")) { Task { await model.reload() } }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .disabled(model.isBusy || model.isLoading).accessibilityIdentifier("pro.reload")
                    }
                }
            }
        }
    }
    private func benefit(_ symbol: String, _ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.tint)
                .frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

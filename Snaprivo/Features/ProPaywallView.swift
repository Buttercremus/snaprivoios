import SwiftUI

struct ProPaywallView: View {
    @Bindable var model: ProPurchaseModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Snaprivo Pro", systemImage: "sparkles").font(.largeTitle.bold())
            Text(String(localized: "Einmal kaufen. Dauerhaft freischalten.")).font(.title3)
            Text(String(localized: "Lokale Arbeit ohne eigenes Konto. Einmalige Freischaltung über deinen Apple Account."))
            if model.hasPro {
                Label(String(localized: "Pro ist aktiviert"), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if !model.purchasesEnabled {
                Text(String(localized: "Pro wird vorbereitet. Funktionsumfang und Preis stehen noch nicht fest. In dieser Entwicklungsversion sind alle vorhandenen Funktionen zugänglich; Käufe sind noch deaktiviert."))
                    .foregroundStyle(.secondary)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let message = model.message { Text(message).foregroundStyle(.secondary) }
            if model.isLoading || model.isBusy { ProgressView() }
            HStack {
                Button(String(localized: "Käufe wiederherstellen")) { Task { await model.restore() } }
                    .disabled(model.isBusy)
                Spacer()
                Button(String(localized: "Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
                if !model.hasPro {
                    Button {
                        Task { await model.buy() }
                    } label: {
                        Text(model.offer.map { String(localized: "Pro freischalten · \($0.price)") } ?? String(localized: "Preis nicht verfügbar"))
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!model.purchasesEnabled || model.offer == nil || model.isBusy || model.isLoading)
                }
            }
            Button(String(localized: "Erneut laden")) { Task { await model.reload() } }.disabled(model.isBusy || model.isLoading)
        }.padding(28).frame(width: 540)
            .task { await model.start() }
    }
}

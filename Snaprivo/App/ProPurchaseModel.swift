import Foundation
import Observation
import StoreKit

struct ProOffer: Equatable, Sendable {
    let name: String
    let price: String
    /// Only advertise the agreed EUR launch offer when the Store actually charges it.
    var laterPrice: String? = nil
    static let launchPrice: Decimal = 29.99
    static let regularPrice: Decimal = 39.99
    static func laterPrice(displayPrice: String, style: Decimal.FormatStyle.Currency) -> String? {
        // Compare the customer's actual Store price using Apple's own formatter.
        // This also avoids a StoreKitTest locale issue with the numeric price.
        let expected = launchPrice.formatted(style).filter { !$0.isWhitespace }
        guard style.currencyCode.uppercased() == "EUR",
              displayPrice.filter({ !$0.isWhitespace }) == expected else { return nil }
        return regularPrice.formatted(style)
    }
}
enum ProPurchaseOutcome: Sendable { case purchased, pending, cancelled }

@MainActor protocol ProStoreClient: AnyObject {
    func offer() async throws -> ProOffer?
    func entitled() async throws -> Bool
    func purchase() async throws -> ProPurchaseOutcome
    func restore() async throws
    func updates() -> AsyncStream<Void>
}

@MainActor final class StoreKitProClient: ProStoreClient {
    static let productID = "com.snaprivo.pro.lifetime"
    private var product: Product?
    func offer() async throws -> ProOffer? {
        product = try await Product.products(for: [Self.productID]).first { $0.id == Self.productID && $0.type == .nonConsumable }
        return product.map { ProOffer(name: $0.displayName, price: $0.displayPrice,
            laterPrice: ProOffer.laterPrice(displayPrice: $0.displayPrice, style: $0.priceFormatStyle)) }
    }
    func entitled() async throws -> Bool {
        var active = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == Self.productID && transaction.productType == .nonConsumable && transaction.revocationDate == nil { active = true }
            case .unverified(let transaction, let error):
                if transaction.productID == Self.productID { throw error }
            }
        }
        return active
    }
    func purchase() async throws -> ProPurchaseOutcome {
        if product == nil { _ = try await offer() }
        guard let product else { throw StoreKitError.notAvailableInStorefront }
        switch try await product.purchase() {
        case .success(let result):
            switch result {
            case .verified(let transaction):
                guard transaction.productID == Self.productID, transaction.productType == .nonConsumable,
                      transaction.revocationDate == nil else { throw StoreKitError.notAvailableInStorefront }
                await transaction.finish(); return .purchased
            case .unverified(_, let error): throw error
            }
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw StoreKitError.unknown
        }
    }
    func restore() async throws { try await AppStore.sync() }
    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result, transaction.productID == Self.productID {
                        await transaction.finish()
                    }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor @Observable final class ProPurchaseModel {
    // The approved package is active. StoreKit only enables buying when the
    // matching App Store Connect product is available; no fabricated price.
    static let commercialPurchasesEnabled = true
    private(set) var hasPro = false
    private(set) var hasCheckedEntitlement = false
    @ObservationIgnored var onEntitlementChanged: (@MainActor (Bool) -> Void)?
    private(set) var offer: ProOffer?
    private(set) var isBusy = false
    private(set) var isLoading = false
    var error: String?
    var message: String?
    let purchasesEnabled: Bool
    @ObservationIgnored private let client: any ProStoreClient
    @ObservationIgnored private var observer: Task<Void, Never>?
    init(client: any ProStoreClient = StoreKitProClient(), purchasesEnabled: Bool = commercialPurchasesEnabled) {
        self.client = client; self.purchasesEnabled = purchasesEnabled
    }
    func start() async {
        guard observer == nil else { await reload(); return }
        let events = client.updates()
        observer = Task { [weak self] in
            for await _ in events { guard !Task.isCancelled else { return }; await self?.refreshEntitlement() }
        }
        await reload()
    }
    func stop() { observer?.cancel(); observer = nil }
    private func applyEntitlement(_ value: Bool) {
        let notify = !hasCheckedEntitlement || hasPro != value
        hasCheckedEntitlement = true; hasPro = value
        if notify { onEntitlementChanged?(value) }
    }
    private func refreshEntitlement() async {
        do { applyEntitlement(try await client.entitled()); if hasPro { message = nil; error = nil } }
        catch { applyEntitlement(false); self.error = String(localized: "Der Kaufbeleg konnte nicht geprüft werden. Bitte versuche es erneut.") }
    }
    func reload() async {
        guard !isLoading, !isBusy else { return }
        error = nil
        isLoading = true; defer { isLoading = false }
        await refreshEntitlement()
        guard purchasesEnabled, !hasPro else { offer = nil; return }
        do { offer = try await client.offer() }
        catch { offer = nil; self.error = error.localizedDescription }
    }
    func buy() async {
        guard purchasesEnabled, !isBusy, !hasPro, offer != nil else { return }
        let displayedOffer = offer
        isBusy = true; error = nil; message = nil
        defer { isBusy = false }
        do {
            // A launch-price change may happen while this window is open.
            // Show the current Store price and require a fresh click if it changed.
            offer = try await client.offer()
            guard let offer, !hasPro else { return }
            guard offer == displayedOffer else {
                message = String(localized: "Der Store-Preis wurde aktualisiert. Bitte prüfe ihn und bestätige den Kauf erneut.")
                return
            }
            switch try await client.purchase() {
            case .purchased: applyEntitlement(true)
            case .pending: message = String(localized: "Der Kauf wartet auf Bestätigung. Pro wird nach erfolgreicher Freigabe aktiviert.")
            case .cancelled: break
            }
        } catch { self.error = error.localizedDescription }
    }
    func restore() async {
        guard !isBusy, !isLoading else { return }
        isBusy = true; error = nil; message = nil
        defer { isBusy = false }
        do {
            try await client.restore(); await refreshEntitlement()
            if error == nil { message = hasPro ? String(localized: "Pro wurde wiederhergestellt.") : String(localized: "Für diesen Apple Account wurde kein Pro-Kauf gefunden.") }
        } catch { self.error = error.localizedDescription }
    }
}

import AppKit
import StoreKitTest
import StoreKit
import XCTest

final class StoreKitChecks: XCTestCase {
    @MainActor func testNativePurchaseAndRefund() async throws {
        let file = Bundle(for: Self.self).url(forResource: "Snaprivo", withExtension: "storekit")!
        let session = try SKTestSession(contentsOf: file)
        session.storefront = "DEU"; session.locale = Locale(identifier: "de_DE")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let client = StoreKitProClient()
        let model = ProPurchaseModel(client: client)
        await model.start()
        defer { model.stop() }
        let offer = try await client.offer()
        XCTAssertNotNil(offer)
        XCTAssertTrue(offer?.price.contains("29") == true)
        let product = try await Product.products(for: [StoreKitProClient.productID]).first!
        XCTAssertTrue(offer?.laterPrice?.contains("39") == true, "Actual offer: \(String(describing: offer)); amount=\(product.price); code=\(product.priceFormatStyle.currencyCode)")
        let initial = try await client.entitled(); XCTAssertFalse(initial)
        await model.buy()
        XCTAssertTrue(model.hasPro)
        var purchased = false
        for _ in 0..<100 {
            purchased = try await client.entitled()
            if purchased { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(purchased)
        let restarted = try await StoreKitProClient().entitled(); XCTAssertTrue(restarted)
        try await client.restore()
        let afterRestore = try await client.entitled(); XCTAssertTrue(afterRestore)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        for _ in 0..<100 {
            if try await !client.entitled(), !model.hasPro { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Refund was not applied")
    }

    @MainActor func testRegularPriceHasNoLaunchClaim() async throws {
        let file = Bundle(for: Self.self).url(forResource: "Snaprivo", withExtension: "storekit")!
        var configuration = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var products = configuration["products"] as! [[String: Any]]
        products[0]["displayPrice"] = "39.99"
        configuration["products"] = products
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Regular-\(UUID()).storekit")
        try JSONSerialization.data(withJSONObject: configuration).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let session = try SKTestSession(contentsOf: temporary)
        session.storefront = "DEU"; session.locale = Locale(identifier: "de_DE")
        session.disableDialogs = true; session.clearTransactions()
        defer { session.clearTransactions() }
        let offer = try await StoreKitProClient().offer()
        XCTAssertTrue(offer?.price.contains("39") == true)
        XCTAssertNil(offer?.laterPrice)
    }
}

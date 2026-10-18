import AppKit
import StoreKitTest
import XCTest

final class StoreKitChecks: XCTestCase {
    @MainActor func testNativePurchaseAndRefund() async throws {
        let file = Bundle(for: Self.self).url(forResource: "Snaprivo", withExtension: "storekit")!
        let session = try SKTestSession(contentsOf: file)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let client = StoreKitProClient()
        let offer = try await client.offer()
        XCTAssertNotNil(offer)
        let initial = try await client.entitled(); XCTAssertFalse(initial)
        let outcome = try await client.purchase()
        if case .purchased = outcome {} else { XCTFail("Local purchase did not finish") }
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
            if try await !client.entitled() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Refund was not applied")
    }
}

import CoreGraphics
import XCTest
@testable import SnagForgeDomain

final class EditorArrangementTests: XCTestCase {
    func testSnapUsesNearestEdgesAndCanvas() {
        let result = EditorArrangement.snap(rect: CGRect(x: 98, y: 198, width: 20, height: 20),
                                             candidates: [CGRect(x: 120, y: 40, width: 40, height: 40)],
                                             canvas: CGRect(x: 0, y: 0, width: 320, height: 240),
                                             tolerance: CGSize(width: 5, height: 5))
        XCTAssertEqual(result.delta, CGSize(width: 2, height: 0))
        XCTAssertEqual(result.guides, [EditorArrangement.Guide(axis: .vertical, position: 120)])
    }

    func testScalingTransformsAuxiliaryPointsAndStyles() {
        var object = EditorObject(kind: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 30, y: 30), fontSize: 12, lineWidth: 4)
        object.arrowBend = CGPoint(x: 18, y: 8)
        object.calloutTip = CGPoint(x: 4, y: 40)
        let result = EditorArrangement.scaled(object: object, from: CGRect(x: 0, y: 0, width: 40, height: 40), to: CGRect(x: 100, y: 50, width: 80, height: 20))
        XCTAssertEqual(result.start, CGPoint(x: 120, y: 55))
        XCTAssertEqual(result.end, CGPoint(x: 160, y: 65))
        XCTAssertEqual(result.arrowBend, CGPoint(x: 136, y: 54))
        XCTAssertEqual(result.calloutTip, CGPoint(x: 108, y: 70))
        XCTAssertEqual(result.lineWidth, 4, accuracy: 0.0001)
    }

}

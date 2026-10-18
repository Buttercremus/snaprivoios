import Foundation
import Testing
@testable import SnagForgeDomain

@Test(arguments: [(0, 100), (100, 0), (-1, 100), (100, -1)])
func rejectsInvalidImageDimensions(dimensions: (Int, Int)) {
    #expect(PixelSize(width: dimensions.0, height: dimensions.1) == nil)
}

@Test func rejectsCorruptedStoredDimensions() {
    let invalid = Data(#"{"width":-1,"height":1080}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PixelSize.self, from: invalid)
    }
}

@Test func preservesPixelDimensionsAcrossSerialization() throws {
    let size = try #require(PixelSize(width: 3840, height: 2160))
    let encoded = try JSONEncoder().encode(size)
    let decoded = try JSONDecoder().decode(PixelSize.self, from: encoded)
    #expect(decoded == size)
}

import Testing
@testable import SnagForgeDomain

private func page(_ start: Int, height: Int = 240) throws -> ScrollFrame {
    let width = 100
    let pixels = (start..<(start + height)).flatMap { y in (0..<width).map { x in UInt8(truncatingIfNeeded: (y * 7919 + x * 104729) ^ (y * x * 313)) } }
    return try ScrollFrame(width: width, height: height, pixels: pixels)
}
@Test func verticalScrollMatchesExactOverlap() throws {
    let first = try page(0)
    for delta in [1, 2, 3, 4, 33, 87, 166] { #expect(try ScrollStitcher.displacement(from: first, to: page(delta)) == delta) }
    #expect(throws: ScrollStitchError.uncertain) { try ScrollStitcher.displacement(from: first, to: page(200)) }
}
@Test func scrollRejectsBlankRepeatedAndMovingContent() throws {
    let a = try page(0)
    #expect(throws: ScrollStitchError.unchanged) { try ScrollStitcher.displacement(from: a, to: a) }
    #expect(throws: ScrollStitchError.moving) { try ScrollStitcher.requireStable(a, page(1)) }
    try ScrollStitcher.requireStable(a, a)
    let blank = try ScrollFrame(width: 100, height: 240, pixels: .init(repeating: 255, count: 24000))
    #expect(throws: ScrollStitchError.unchanged) { try ScrollStitcher.displacement(from: blank, to: blank) }
    let periodic = try ScrollFrame(width: 100, height: 240, pixels: (0..<24000).map { UInt8(($0 / 100) % 20 * 10) })
    let shifted = try ScrollFrame(width: 100, height: 240, pixels: (0..<24000).map { UInt8((($0 / 100) + 7) % 20 * 10) })
    #expect(throws: ScrollStitchError.uncertain) { try ScrollStitcher.displacement(from: periodic, to: shifted) }
}
@Test func scrollRejectsStickyHeaderAndLimits() throws {
    let a = try page(0), b = try page(80)
    var pixels = b.pixels
    pixels.replaceSubrange(0..<2000, with: a.pixels[0..<2000])
    let sticky = try ScrollFrame(width: 100, height: 240, pixels: pixels)
    #expect(throws: ScrollStitchError.fixedContent) { try ScrollStitcher.displacement(from: a, to: sticky) }
    // A real sticky footer is painted over the scroll content in both frames.
    let footerBand = (0..<2000).map { UInt8($0 % 7 < 3 ? 0 : 255) }
    var oldFooterPixels = a.pixels, newFooterPixels = b.pixels
    oldFooterPixels.replaceSubrange(22000..<24000, with: footerBand)
    newFooterPixels.replaceSubrange(22000..<24000, with: footerBand)
    let oldFooter = try ScrollFrame(width: 100, height: 240, pixels: oldFooterPixels)
    let newFooter = try ScrollFrame(width: 100, height: 240, pixels: newFooterPixels)
    #expect(throws: ScrollStitchError.fixedContent) { try ScrollStitcher.displacement(from: oldFooter, to: newFooter) }
    #expect(throws: ScrollStitchError.limit) { try ScrollStitcher.validateSize(width: 4000, height: 20000, count: 2) }
    #expect(throws: ScrollStitchError.limit) { try ScrollStitcher.validateSize(width: 100, height: 20001, count: 2) }
    #expect(throws: ScrollStitchError.limit) { try ScrollStitcher.validateSize(width: 100, height: 400, count: 51) }
    try ScrollStitcher.validateSize(width: 100, height: 20000, count: 50)
}


@Test func repeatedTextNearBottomIsNotAStickyFooter() throws {
    let backgrounds: [UInt8] = [230, 210, 250, 190, 220, 140, 205, 205, 240, 180]
    func section(_ offset: Int) throws -> ScrollFrame {
        let width = 100, height = 700
        var pixels = [UInt8](); pixels.reserveCapacity(width * height)
        for y in offset..<(offset + height) {
            for x in 0..<width {
                // Common text-like rows repeat; consecutive final sections have
                // the same background, while the section before them differs.
                pixels.append((20..<46).contains(y % 120) && x % 5 < 3 ? 10 : backgrounds[y / 120])
            }
        }
        return try ScrollFrame(width: width, height: height, pixels: pixels)
    }
    #expect(try ScrollStitcher.displacement(from: section(120), to: section(240)) == 120)
}

@Test func scrollInsetsExcludeFixedHeaderAndFooterBeforeMatching() throws {
    let a = try page(0), b = try page(80)
    var next = b.pixels
    next.replaceSubrange(0..<2000, with: a.pixels[0..<2000])
    next.replaceSubrange(22000..<24000, with: a.pixels[22000..<24000])
    let rect = try ScrollContentInsets(topPercent: 10, bottomPercent: 10).rect(width: 100, height: 240)
    let range = Int(rect.minY) * 100 ..< Int(rect.maxY) * 100
    let trimmedA = try ScrollFrame(width: 100, height: Int(rect.height), pixels: Array(a.pixels[range]))
    let trimmedB = try ScrollFrame(width: 100, height: Int(rect.height), pixels: Array(next[range]))
    #expect(try ScrollStitcher.displacement(from: trimmedA, to: trimmedB) == 80)
    #expect(throws: ScrollStitchError.dimensions) { try ScrollContentInsets(topPercent: 21).rect(width: 100, height: 240) }
    #expect(throws: ScrollStitchError.dimensions) { try ScrollContentInsets(topPercent: 20, bottomPercent: 20).rect(width: 100, height: 100) }
}

@Test func livePanoramaUsesPixelBoundsRatherThanManualSectionCount() throws {
    try ScrollStitcher.validateOutputSize(width: 2000, height: 20000)
    #expect(throws: ScrollStitchError.limit) { try ScrollStitcher.validateOutputSize(width: 2001, height: 20000) }
    #expect(throws: ScrollStitchError.limit) { try ScrollStitcher.validateOutputSize(width: 2000, height: 20001) }
    #expect(throws: ScrollStitchError.limit) { try ScrollStitcher.validateOutputSize(width: 4097, height: 100) }
    #expect(throws: ScrollStitchError.limit) { try ScrollStitcher.validateOutputSize(width: 0, height: 100) }
}

import CoreGraphics

public struct ScrollContentInsets: Equatable, Sendable {
    public var topPercent: Int
    public var bottomPercent: Int
    public init(topPercent: Int = 0, bottomPercent: Int = 0) { self.topPercent = topPercent; self.bottomPercent = bottomPercent }
    public func rect(width: Int, height: Int) throws -> CGRect {
        guard (0...20).contains(topPercent), (0...20).contains(bottomPercent), width >= 40, height >= 80 else { throw ScrollStitchError.dimensions }
        let top = height * topPercent / 100, bottom = height * bottomPercent / 100
        guard height - top - bottom >= 80 else { throw ScrollStitchError.dimensions }
        return CGRect(x: 0, y: top, width: width, height: height - top - bottom)
    }
}

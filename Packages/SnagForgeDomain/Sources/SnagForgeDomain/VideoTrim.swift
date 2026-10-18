import Foundation

public struct VideoTrim: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public var duration: Double { end - start }
    public init(start: Double, end: Double) { self.start = start; self.end = end }
    public func validated(duration originalDuration: Double) throws -> Self {
        guard originalDuration.isFinite, originalDuration > 0,
              start.isFinite, end.isFinite, start >= 0, end <= originalDuration, duration > 0,
              duration >= min(1.0 / 30, originalDuration) - 0.000_001 else { throw ProjectError.invalidDocument }
        return self
    }
    public func normalized(duration: Double) throws -> Self? {
        _ = try validated(duration: duration)
        return start == 0 && end == duration ? nil : self
    }
}

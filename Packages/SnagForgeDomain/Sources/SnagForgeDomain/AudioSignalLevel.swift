import Foundation

/// Transient measurements only; this type deliberately does not persist audio.
public struct AudioSignalLevel: Equatable, Sendable {
    public let rms: Double
    public let peak: Double
    public let sampleCount: Int
    public init?(rms: Double, peak: Double, sampleCount: Int) {
        guard rms.isFinite, peak.isFinite, (0...1).contains(rms), (rms...1).contains(peak),
              (1...1_000_000).contains(sampleCount) else { return nil }
        self.rms = rms; self.peak = peak; self.sampleCount = sampleCount
    }
    public var decibels: Double { max(-60, 20 * log10(max(rms, 0.000_001))) }
    public var fraction: Double { min(1, max(0, (decibels + 60) / 60)) }
    public static func measure<S: Sequence>(_ samples: S) -> Self? where S.Element: BinaryFloatingPoint {
        var squares = 0.0, peak = 0.0, count = 0
        for value in samples.prefix(4096) where value.isFinite {
            let magnitude = min(1, abs(Double(value)))
            squares += magnitude * magnitude; peak = max(peak, magnitude); count += 1
        }
        guard count > 0 else { return nil }
        // Summing equal samples can round RMS just above their peak.
        return Self(rms: min(peak, sqrt(squares / Double(count))), peak: peak, sampleCount: count)
    }
}

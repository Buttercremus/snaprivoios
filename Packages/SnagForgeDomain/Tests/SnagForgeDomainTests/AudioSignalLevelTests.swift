import Testing
@testable import SnagForgeDomain

struct AudioSignalLevelTests {
    @Test func measuresSignalAndSilence() throws {
        let level = try #require(AudioSignalLevel.measure([0.0, 0.5, 0.0, -0.5]))
        #expect(abs(level.rms - 0.3535533906) < 0.000001)
        #expect(level.peak == 0.5 && level.sampleCount == 4)
        #expect(abs(level.decibels + 9.0309) < 0.0001)
        #expect(AudioSignalLevel.measure([Float(0), 0])?.fraction == 0)
        #expect(AudioSignalLevel.measure([Double(1)])?.fraction == 1)
    }
    @Test func boundsUntrustedSamples() throws {
        #expect(AudioSignalLevel.measure([Double.nan, .infinity, -.infinity]) == nil)
        #expect(AudioSignalLevel.measure([Double]()) == nil)
        let level = try #require(AudioSignalLevel.measure([Double.nan, -2, 2]))
        #expect(level.rms == 1 && level.peak == 1 && level.sampleCount == 2)
        let bounded = try #require(AudioSignalLevel.measure(repeatElement(0.1, count: 10_000)))
        #expect(bounded.sampleCount == 4096)
        #expect(AudioSignalLevel(rms: .nan, peak: 1, sampleCount: 1) == nil)
        #expect(AudioSignalLevel(rms: 0.5, peak: 0.4, sampleCount: 1) == nil)
        #expect(AudioSignalLevel(rms: 0, peak: 1.01, sampleCount: 1) == nil)
        #expect(AudioSignalLevel(rms: 0, peak: 0, sampleCount: 0) == nil)
        #expect(AudioSignalLevel(rms: 0, peak: 0, sampleCount: 1_000_001) == nil)
    }
}

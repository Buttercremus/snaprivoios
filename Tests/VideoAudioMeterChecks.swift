import AppKit
import AVFoundation
import SnagForgeDomain

@MainActor enum VideoAudioMeterChecks {
    static func run() throws {
        let tone = try VideoRecordingChecks.tone(frame: 0, amplitude: 0.5)
        let silence = try VideoRecordingChecks.tone(frame: 0, amplitude: 0)
        let decoded = VideoAudioMeter.decode(tone)!
        check(abs(decoded.rms - 0.5 / sqrt(2)) < 0.002 && abs(decoded.peak - 0.5) < 0.001)
        check(decoded.sampleCount == 3200)
        check(VideoAudioMeter.decode(silence)?.fraction == 0)
        let meter = VideoAudioMeter()
        check(meter.read(silence, source: .system, at: 0)?.rms == 0)
        check(meter.read(tone, source: .system, at: 50_000_000) == nil)
        check(meter.read(silence, source: .microphone, at: 50_000_000)?.rms == 0, "Sources shared throttle or samples")
        let window = meter.read(silence, source: .system, at: 100_000_000)!
        check(abs(window.rms - decoded.rms / sqrt(2)) < 0.0001 && window.peak == decoded.peak)
        check(meter.read(silence, source: .system, at: 200_000_000)?.rms == 0, "Previous window leaked")
        check(meter.read(tone, source: .system, at: 1) != nil, "Clock reset permanently stopped measurement")

        let toolbar = VideoRecordingToolbar(reduceMotion: { true })
        defer { toolbar.hide() }
        let panel = NSApp.windows.first { $0.identifier?.rawValue == "video.recordingToolbar" }!
        func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
        let indicators = views(panel.contentView!).compactMap { $0 as? NSLevelIndicator }
        let system = indicators.first { $0.accessibilityIdentifier() == "video.audio.system" }!
        let microphone = indicators.first { $0.accessibilityIdentifier() == "video.audio.microphone" }!
        toolbar.configureAudio(.init(systemAudio: true, microphone: false))
        toolbar.update(recording: true, status: "Synthetic", duration: "00:01", dimensions: "320 × 180 px", canCancel: false)
        toolbar.updateAudioLevel(.system, level: decoded, at: 100)
        toolbar.updateAudioLevel(.microphone, level: decoded, at: 100)
        check(system.doubleValue > 80 && microphone.doubleValue == 0)
        check(!system.isHiddenOrHasHiddenAncestor && microphone.isHiddenOrHasHiddenAncestor)
        toolbar.expireAudioLevels(at: 600_000_100)
        check(system.doubleValue == 0 && system.accessibilityHelp() != nil, "Stale reading remained live")
        toolbar.updateAudioLevel(.system, level: VideoAudioMeter.decode(silence)!, at: 700_000_000)
        check(system.doubleValue == 0 && system.accessibilityHelp() == nil, "Silence was reported as missing data")
        toolbar.configureAudio(.init(systemAudio: true, microphone: true))
        toolbar.updateAudioLevel(.microphone, level: decoded)
        check(!microphone.isHiddenOrHasHiddenAncestor && microphone.doubleValue > 80)
        toolbar.update(recording: false, status: "Finished", duration: "00:01", dimensions: "320 × 180 px", canCancel: false)
        toolbar.updateAudioLevel(.microphone, level: decoded)
        check(microphone.doubleValue == 0 && microphone.isHiddenOrHasHiddenAncestor)
        check(panel.frame.width == 360 && panel.frame.height == 56)
        print("Audio meters passed: PCM signal/silence, independent bounded windows, stale data, selected sources, stop and native toolbar geometry.")
    }
}
private func check(_ value: Bool, _ message: String = "Audio meter check failed", file: StaticString = #fileID, line: UInt = #line) {
    precondition(value, message, file: file, line: line)
}

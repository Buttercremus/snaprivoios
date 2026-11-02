import AVFoundation
import SnagForgeDomain

/// A private immutable composition, built afresh from the original for every edit.
struct VideoEditComposition {
    let asset: AVAsset
    let audioMix: AVAudioMix?

    @concurrent static func make(source: AVURLAsset, playback: VideoPlayback, duration: Double) async throws -> Self {
        _ = try playback.validated(duration: duration)
        let asset: AVAsset
        if playback.removed.isEmpty && playback.speed == 1 { asset = source }
        else {
            guard let video = try await source.loadTracks(withMediaType: .video).first else { throw VideoRecordingError.invalidMovie }
            let composition = AVMutableComposition()
            guard let output = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoRecordingError.invalidMovie }
            output.preferredTransform = try await video.load(.preferredTransform)
            var audio: [(AVAssetTrack, AVMutableCompositionTrack, CMTimeRange)] = []
            for track in try await source.loadTracks(withMediaType: .audio) {
                guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoRecordingError.invalidMovie }
                audio.append((track, target, try await track.load(.timeRange)))
            }
            var cursor = CMTime.zero
            for range in playback.keptRanges(duration: duration) {
                try Task.checkCancellation()
                let sourceRange = CMTimeRange(start: time(range.start), end: time(range.end))
                try output.insertTimeRange(sourceRange, of: video, at: cursor)
                for (sourceAudio, targetAudio, available) in audio {
                    let intersection = CMTimeRangeGetIntersection(sourceRange, otherRange: available)
                    if intersection.isValid && intersection.duration.seconds > 0 {
                        try targetAudio.insertTimeRange(intersection, of: sourceAudio,
                            at: cursor + intersection.start - sourceRange.start)
                    }
                }
                cursor = cursor + sourceRange.duration
            }
            if playback.speed != 1 { composition.scaleTimeRange(.init(start: .zero, duration: cursor), toDuration: time(cursor.seconds / playback.speed)) }
            guard let snapshot = composition.copy() as? AVComposition else { throw VideoRecordingError.invalidMovie }
            asset = snapshot
        }
        let mix: AVAudioMix?
        if playback.volume != 1 {
            let mutable = AVMutableAudioMix()
            mutable.inputParameters = try await asset.loadTracks(withMediaType: .audio).map { track in
                let input = AVMutableAudioMixInputParameters(track: track)
                input.setVolume(Float(playback.volume), at: .zero)
                input.audioTimePitchAlgorithm = .spectral
                return input
            }
            mix = mutable.copy() as? AVAudioMix
        } else { mix = nil }
        return Self(asset: asset, audioMix: mix)
    }
    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }
}

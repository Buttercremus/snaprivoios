import Testing
@testable import SnagForgeDomain

@Test func captureDelayRunsAtExactlyOneStageForEachMedia() {
    for seconds in [0, 3, 5] {
        for source in CaptureSource.allCases {
            let image = CaptureConfiguration(media: .image, source: source, delaySeconds: seconds)
            #expect(image.selectionDelaySeconds == seconds)
            #expect(image.recordingDelaySeconds == 0)
            let video = CaptureConfiguration(media: .video, source: source, delaySeconds: seconds)
            #expect(video.selectionDelaySeconds == 0)
            #expect(video.recordingDelaySeconds == seconds)
        }
    }
}

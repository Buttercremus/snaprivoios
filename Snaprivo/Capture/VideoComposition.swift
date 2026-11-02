import AVFoundation
import CoreImage
import SnagForgeDomain

/// The same immutable instruction drives AVPlayer, MP4 and GIF output.
final class VideoFrameInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening: Bool
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let sourceSize: PixelSize
    let presentation: VideoPresentation
    let playback: VideoPlayback
    let originalDuration: Double

    init(track: CMPersistentTrackID, duration: CMTime, transform: CGAffineTransform,
         size: PixelSize, presentation: VideoPresentation, playback: VideoPlayback, originalDuration: Double) {
        trackID = track; timeRange = CMTimeRange(start: .zero, duration: duration)
        requiredSourceTrackIDs = [NSNumber(value: track)]
        self.transform = transform; sourceSize = size; self.presentation = presentation
        self.playback = playback; self.originalDuration = originalDuration; containsTweening = !playback.zooms.isEmpty
    }
}

enum VideoComposition {
    static func make(asset: AVAsset, size: PixelSize, presentation: VideoPresentation,
                     playback: VideoPlayback = .init(), originalDuration: Double? = nil) async throws -> AVVideoComposition? {
        guard !presentation.isIdentity || !playback.isIdentity else { return nil }
        guard let geometry = presentation.geometry(for: size),
              let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoRecordingError.invalidMovie }
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let sourceDuration = originalDuration ?? duration.seconds
        _ = try playback.validated(duration: sourceDuration)
        let interval = try await track.load(.minFrameDuration)
        let frameDuration = playback.speed == 1 && interval.isNumeric && interval.seconds > 0 ? interval : CMTime(value: 1, timescale: 30)
        let instruction = VideoFrameInstruction(track: track.trackID, duration: duration, transform: transform,
                                                size: size, presentation: presentation, playback: playback, originalDuration: sourceDuration)
        let config = AVVideoComposition.Configuration(customVideoCompositorClass: VideoFrameCompositor.self,
            frameDuration: frameDuration, instructions: [instruction],
            renderSize: CGSize(width: geometry.outputSize.width, height: geometry.outputSize.height))
        return AVVideoComposition(configuration: config)
    }
}

/// Core Image retains a graph, not a new CPU bitmap per frame. CIContext is thread safe.
final class VideoFrameCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var renderContext: AVVideoCompositionRenderContext?
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        lock.lock(); renderContext = newRenderContext; lock.unlock()
    }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            lock.lock(); let targetContext = renderContext; lock.unlock()
            guard let instruction = request.videoCompositionInstruction as? VideoFrameInstruction,
                  let source = request.sourceFrame(byTrackID: instruction.trackID),
                  let buffer = targetContext?.newPixelBuffer(),
                  let geometry = instruction.presentation.geometry(for: instruction.sourceSize) else {
                request.finish(with: VideoRecordingError.invalidMovie); return
            }
            // Track transforms use top-left coordinates; Core Image uses bottom-left coordinates.
            // Bridge both coordinate systems before normalizing the transformed extent.
            let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(CVPixelBufferGetHeight(source)))
            let input = CIImage(cvPixelBuffer: source).transformed(by: flip)
                .transformed(by: instruction.transform).transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            let normalized = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
            let time = instruction.playback.sourceTime(for: request.compositionTime.seconds, duration: instruction.originalDuration)
            let focused = Self.focus(normalized, transform: instruction.playback.focus(at: time))
            let image = Self.render(focused, presentation: instruction.presentation, geometry: geometry)
            let bounds = CGRect(x: 0, y: 0, width: geometry.outputSize.width, height: geometry.outputSize.height)
            context.render(image, to: buffer, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            request.finish(withComposedVideoFrame: buffer)
        }
    }
    // Requests are completed synchronously; no owned queue or retained requests remain to cancel.
    func cancelAllPendingVideoCompositionRequests() {}

    static func focus(_ source: CIImage, transform: VideoZoom.Transform) -> CIImage {
        guard transform.scale > 1 else { return source }
        let size = source.extent.size, width = size.width / transform.scale, height = size.height / transform.scale
        let x = min(max(0, transform.centerX * size.width - width / 2), size.width - width)
        let y = min(max(0, (1 - transform.centerY) * size.height - height / 2), size.height - height)
        return source.cropped(to: CGRect(x: x, y: y, width: width, height: height))
            .transformed(by: CGAffineTransform(translationX: -x, y: -y))
            .transformed(by: CGAffineTransform(scaleX: transform.scale, y: transform.scale))
    }

    static func render(_ source: CIImage, presentation: VideoPresentation, geometry: VideoPresentationGeometry) -> CIImage {
        let output = CGRect(x: 0, y: 0, width: geometry.outputSize.width, height: geometry.outputSize.height)
        let frame = geometry.videoFrame
        let black = CIImage(color: .black).cropped(to: output)
        let background: CIImage
        switch presentation.backdrop {
        case .none: background = black
        case .solid: background = CIImage(color: ciColor(presentation.color)).cropped(to: output)
        case .gradient:
            background = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: output.height), "inputPoint1": CIVector(x: output.width, y: 0),
                "inputColor0": ciColor(presentation.color), "inputColor1": ciColor(presentation.secondColor)
            ])!.outputImage!.cropped(to: output)
        }
        let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: frame),
            "inputRadius": min(presentation.cornerRadius, min(frame.width, frame.height) / 2),
            "inputColor": CIColor.white
        ])!.outputImage!.cropped(to: output)
        let clear = CIImage(color: .clear).cropped(to: output)
        let placed = source.cropped(to: CGRect(origin: .zero, size: frame.size))
            .transformed(by: CGAffineTransform(translationX: frame.minX, y: frame.minY))
        let video = placed.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask])
        var backdrop = background
        if presentation.shadow > 0 {
            let shadow = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: presentation.shadow * 0.5))
                .cropped(to: output).applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask])
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4 + presentation.shadow * 16])
                .transformed(by: CGAffineTransform(translationX: 0, y: -presentation.shadow * 8))
            backdrop = shadow.composited(over: background)
        }
        return video.composited(over: backdrop).composited(over: black).cropped(to: output)
    }
    private static func ciColor(_ c: EditorColor) -> CIColor { CIColor(red: c.red, green: c.green, blue: c.blue) }
}

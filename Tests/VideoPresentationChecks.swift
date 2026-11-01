import AppKit
import AVFoundation
import ImageIO
import CoreImage
import SnagForgeDomain

@MainActor enum VideoPresentationChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoPresentation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VideoRecordingFiles(root: root.appendingPathComponent("Originals"))
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        try await VideoRecordingChecks.movie(at: partial, includesAudio: true)
        let original = try await files.finalize(partial, audio: .init(systemAudio: true))
        let bytes = try Data(contentsOf: original)
        let document = try await files.list().items.first!.document
        let model = VideoEditorModel(document: document, url: original, files: files)
        model.player.isMuted = true
        defer { model.stopPreview() }
        var style = VideoPresentation()
        style.backdrop = .solid; style.color = EditorColor(red: 1, green: 0, blue: 0)
        style.padding = 24; style.cornerRadius = 20; style.shadow = 0.4
        model.setPresentation(style); model.moveStart(to: 0.2); model.moveEnd(to: 0.8)
        check(model.hasUnappliedChanges)
        await model.updatePreviewComposition()
        check(model.player.currentItem?.videoComposition?.renderSize == CGSize(width: 368, height: 228))
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        model.player.currentItem!.add(videoOutput)
        model.seek(0.4)
        var pausedFrame: CVPixelBuffer?
        for _ in 0..<200 {
            pausedFrame = videoOutput.copyPixelBuffer(forItemTime: CMTime(seconds: 0.4, preferredTimescale: 600), itemTimeForDisplay: nil)
            if pausedFrame != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(pausedFrame != nil, "Paused playback never produced a styled frame")
        let pausedImage = CIImage(cvPixelBuffer: pausedFrame!)
        let pausedCG = CIContext().createCGImage(pausedImage, from: pausedImage.extent)!
        check(pixel(pausedCG, CGPoint(x: 5, y: 5))[0] > 0.85 && model.player.rate == 0, "Paused preview did not update")
        model.player.currentItem!.remove(videoOutput)
        check(await model.apply())
        check(await model.undo()); check(model.presentation.isIdentity)
        check(await model.redo()); check(model.presentation == style)
        let saved = try await files.document(document.id)
        check(saved.presentation == style && saved.trim == VideoTrim(start: 0.2, end: 0.8))
        let reopened = VideoEditorModel(document: saved, url: original, files: files)
        defer { reopened.stopPreview() }
        check(reopened.presentation == style && !reopened.hasUnappliedChanges)

        let previewGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: original))
        previewGenerator.videoComposition = try await VideoComposition.make(asset: previewGenerator.asset, size: saved.pixelSize!, presentation: style)
        previewGenerator.requestedTimeToleranceBefore = .zero; previewGenerator.requestedTimeToleranceAfter = .zero
        let preview = try await previewGenerator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image
        let mp4 = root.appendingPathComponent("Styled.mp4")
        try await files.exportEdited(saved.id, to: mp4)
        let movie = AVURLAsset(url: mp4)
        let track = try await movie.loadTracks(withMediaType: .video).first!
        check(try await track.load(.naturalSize) == CGSize(width: 368, height: 228))
        check(!(try await movie.loadTracks(withMediaType: .audio)).isEmpty)
        let outputGenerator = AVAssetImageGenerator(asset: movie)
        outputGenerator.requestedTimeToleranceBefore = .zero; outputGenerator.requestedTimeToleranceAfter = .zero
        let output = try await outputGenerator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
        check(preview.width == output.width && preview.height == output.height)
        for point in [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 25), CGPoint(x: 184, y: 114)] {
            let a = pixel(preview, point), b = pixel(output, point)
            check(zip(a, b).allSatisfy { abs($0.0 - $0.1) < 0.12 }, "Preview/export pixels diverged at \(point): \(a), \(b)")
        }
        let edge = pixel(output, CGPoint(x: 5, y: 5))
        check(edge[0] > 0.85 && edge[1] < 0.1 && edge[2] < 0.1, "Background missing")
        let corner = pixel(output, CGPoint(x: 25, y: 25))
        check(corner[0] > 0.85 && corner[1] < 0.1, "Rounded corner did not reveal the background")
        let center = pixel(output, CGPoint(x: 184, y: 114))
        check(abs(center[0] - center[1]) < 0.08 && center[0] > 0.1, "Source video missing")
        let gif = root.appendingPathComponent("Styled.gif")
        try await files.exportGIF(saved.id, to: gif)
        let gifSource = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        let gifFrame = CGImageSourceCreateImageAtIndex(gifSource, 2, nil)!
        check(gifFrame.width == 368 && gifFrame.height == 228)
        check(pixel(gifFrame, CGPoint(x: 5, y: 5))[0] > 0.85)
        let backup = root.appendingPathComponent("Backup")
        try await files.backup(to: backup)
        let restored = VideoRecordingFiles(root: root.appendingPathComponent("Restored"))
        check(try await restored.restore(from: backup) == 1)
        check(try await restored.list().items.first!.document.presentation == style)
        let previous = try Data(contentsOf: mp4)
        do {
            try await files.exportEdited(saved.id, to: mp4, beforePublish: { throw CancellationError() })
            preconditionFailure("Cancelled output published")
        } catch is CancellationError {}
        check(try Data(contentsOf: mp4) == previous)

        for aspect in [PresentationAspectRatio.square, .wide, .portrait] {
            var gradient = style; gradient.backdrop = .gradient
            gradient.secondColor = EditorColor(red: 0, green: 0, blue: 1); gradient.aspectRatio = aspect
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: original))
            generator.videoComposition = try await VideoComposition.make(asset: generator.asset, size: saved.pixelSize!, presentation: gradient)
            let frame = try await generator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image
            let geometry = gradient.geometry(for: saved.pixelSize!)!
            check(frame.width == geometry.outputSize.width && frame.height == geometry.outputSize.height)
            let a = pixel(frame, CGPoint(x: 5, y: 5)), b = pixel(frame, CGPoint(x: frame.width - 6, y: frame.height - 6))
            check(abs(a[0] - b[0]) > 0.3 && abs(a[2] - b[2]) > 0.3, "Gradient missing")
        }
        let turnedPartial = try await files.prepare(availableBytes: 1_000_000_000)
        try await VideoRecordingChecks.movie(at: turnedPartial,
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0), quadrants: true)
        let turned = try await files.finalize(turnedPartial)
        let turnedDocument = try await files.list().items.first { $0.document.fileName == turned.lastPathComponent }!.document
        let rawGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: turned)); rawGenerator.appliesPreferredTrackTransform = true
        let rawFrame = try await rawGenerator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image
        let styledGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: turned))
        styledGenerator.videoComposition = try await VideoComposition.make(asset: styledGenerator.asset, size: turnedDocument.pixelSize!, presentation: style)
        let styledFrame = try await styledGenerator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image
        for p in [CGPoint(x: 45, y: 80), CGPoint(x: 135, y: 80), CGPoint(x: 45, y: 240), CGPoint(x: 135, y: 240)] {
            let a = pixel(rawFrame, p), b = pixel(styledFrame, CGPoint(x: p.x + 24, y: p.y + 24))
            check(zip(a, b).allSatisfy { abs($0.0 - $0.1) < 0.12 }, "Preferred track transform mismatch: \(a), \(b)")
        }
        check(try Data(contentsOf: original) == bytes, "Original video changed")
        model.hasProAccess = { false }
        model.setPresentation(VideoPresentation())
        check(model.presentation == style, "Locked style changed")
        print("Video presentation passed: shared preview/MP4/GIF pixels, even/aspect output geometry, gradient/background/corners, preferred transform, audio/trim, immutable original, backup, cancelled publish, stored edits, Undo/Redo, reopen and Pro guard.")
    }
    private static func check(_ value: Bool, _ message: String = "Video presentation check failed") { precondition(value, message) }
    private static func pixel(_ image: CGImage, _ point: CGPoint) -> [Double] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (Int(point.y) * image.width + Int(point.x)) * 4
        return bytes[offset..<(offset + 3)].map { Double($0) / 255 }
    }
}

import AppKit
import AVFoundation
import ImageIO
import SnagForgeDomain

/// Synthetic file-only fixtures. No screen stream, microphone or audio output.
@MainActor enum VideoPlaybackChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoPlayback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VideoRecordingFiles(root: root.appendingPathComponent("Originals"))
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        try await VideoRecordingChecks.movie(at: partial, includesAudio: true, audioPulse: true)
        let original = try await files.finalize(partial, audio: .init(systemAudio: true))
        let bytes = try Data(contentsOf: original)
        let document = try await files.list().items.first!.document
        let model = VideoEditorModel(document: document, url: original, files: files)
        defer { model.stopPreview() }
        model.player.isMuted = true
        var edit = try VideoPlayback().removing(.init(start: 0.2, end: 0.4), duration: 1)
        edit.speed = 2; edit.volume = 0.5
        model.moveStart(to: 0.1); model.moveEnd(to: 0.9)
        check(model.setPlayback(edit) && model.hasUnappliedChanges && abs(model.outputDuration - 0.3) < 0.0001)
        model.seek(0.5)
        check(model.position == 0.5 && !model.isPreviewReady, "Pending edit snapped a source seek through the old composition")
        check(await model.apply() && model.document.playback == edit)
        check(model.position == 0.5, "Saving moved the source playhead away from the reviewed edit")
        check(await model.undo() && model.playback.isIdentity && model.start == 0)
        check(await model.redo() && model.playback == edit)
        await model.updatePreviewComposition()
        let item = model.player.currentItem!
        check(item.audioMix != nil && item.videoComposition != nil)
        check(abs(item.reversePlaybackEndTime.seconds - 0.05) < 0.00001 && abs(item.forwardPlaybackEndTime.seconds - 0.35) < 0.00001)
        check(model.player.rate == 0 && !model.isPreparingPreview)
        check(model.isPreviewReady)
        let saved = try await files.document(document.id)
        check(saved.playback == edit && saved.schemaVersion == 5)
        let restarted = VideoEditorModel(document: saved, url: original, files: files)
        defer { restarted.stopPreview() }
        check(restarted.playback == edit && restarted.outputDuration == model.outputDuration && !restarted.hasUnappliedChanges)
        let missing = VideoEditorModel(document: saved, url: root.appendingPathComponent("Missing.mp4"), files: files)
        defer { missing.stopPreview() }
        await missing.updatePreviewComposition(); missing.playSelection()
        check(missing.error != nil && !missing.isPreviewReady && !missing.isPlaying, "Failed composition played an older edit")
        restarted.hasProAccess = { false }
        var refused = edit; refused.speed = 4
        check(!restarted.setPlayback(refused) && restarted.playback == edit, "Playback edits bypassed Pro")

        let output = root.appendingPathComponent("Spliced.mp4")
        try await files.exportEdited(document.id, to: output)
        let asset = AVURLAsset(url: output), duration = try await asset.load(.duration).seconds
        check(abs(duration - 0.3) < 0.04, "Retime export has wrong output duration")
        let frames = try await VideoEditingChecks.frames(output), sourceFrames = try await VideoEditingChecks.frames(original)
        for frame in frames {
            let nearest = sourceFrames.min { abs($0.gray - frame.gray) < abs($1.gray - frame.gray) }!.time
            check(nearest < 0.2 || nearest >= 0.4 - 0.00001, "A removed source frame leaked into MP4")
        }
        let track = try await asset.loadTracks(withMediaType: .audio).first!
        let pcm = try VideoEditingChecks.decodedAudio(asset, track: track)
        check(abs(pcm.end - duration) < 0.05 && abs(pcm.first) < 0.04)
        let firstPulse = pcm.values.firstIndex { abs($0) > 0.025 }!
        let pulseTime = pcm.first + Double(firstPulse) / (48_000 * 2)
        let visualPulse = frames.min { abs($0.gray - sourceFrames[12].gray) < abs($1.gray - sourceFrames[12].gray) }!.time
        check(abs(pulseTime - visualPulse) < 0.07, "Cuts or speed desynchronized the synthetic audio/video pulse")
        let gif = root.appendingPathComponent("Spliced.gif")
        try await files.exportGIF(document.id, to: gif, options: .init(framesPerSecond: 10))
        let imageSource = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        check(CGImageSourceGetCount(imageSource) == 3, "GIF used original duration instead of edited output time")

        let previous = try Data(contentsOf: output)
        do { try await files.exportEdited(document.id, to: output, beforePublish: { throw CancellationError() }); preconditionFailure("Cancelled splice published") }
        catch is CancellationError { }
        check(try Data(contentsOf: output) == previous)
        let backup = root.appendingPathComponent("Backup")
        try await files.backup(to: backup)
        let restored = VideoRecordingFiles(root: root.appendingPathComponent("Restored"))
        check(try await restored.restore(from: backup) == 1)
        let copy = try await restored.list().items.first!.document
        check(copy.id != document.id && copy.playback == edit && copy.trim == saved.trim)
        check(try Data(contentsOf: await restored.movieURL(copy.id)) == bytes)
        check(try Data(contentsOf: original) == bytes, "Time edits modified the original")
        try await volume(root: root)
        try await focus(root: root)
        model.stopPreview(); model.playSelection()
        check(!model.isPreviewReady && !model.isPlaying, "Closed preview restarted playback")
        print("Video playback passed: source/output mapping, splices and speed in MP4/GIF, audio pulse synchronization, volume, focus pixels, version 5, saved/reopened edits, Undo/Redo, Pro, backup, cancellation and immutable originals.")
    }

    private static func volume(root: URL) async throws {
        let files = VideoRecordingFiles(root: root.appendingPathComponent("Volume"))
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        try await VideoRecordingChecks.movie(at: partial, includesAudio: true)
        let original = try await files.finalize(partial, audio: .init(systemAudio: true))
        let doc = try await files.list().items.first!.document
        func rms(_ url: URL) async throws -> Double {
            let asset = AVURLAsset(url: url), track = try await asset.loadTracks(withMediaType: .audio).first!
            let samples = try VideoEditingChecks.decodedAudio(asset, track: track).values
            return sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
        }
        let before = try await rms(original)
        var edit = VideoPlayback(); edit.volume = 0.25
        let saved = try await files.setEdit(doc.id, trim: nil, presentation: .init(), playback: edit, expectedRevision: 0)
        let quiet = root.appendingPathComponent("Quiet.mp4")
        try await files.exportEdited(doc.id, to: quiet)
        let after = try await rms(quiet)
        check(abs(after / before - 0.25) < 0.025, "Applied volume differs from encoded PCM")
        edit.volume = 0
        _ = try await files.setEdit(doc.id, trim: nil, presentation: .init(), playback: edit, expectedRevision: saved.revision)
        let muted = root.appendingPathComponent("Muted.mp4")
        try await files.exportEdited(doc.id, to: muted)
        check(try await rms(muted) < 0.001, "Zero volume did not encode silence")
    }
    private static func focus(root: URL) async throws {
        let files = VideoRecordingFiles(root: root.appendingPathComponent("Focus"))
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        try await VideoRecordingChecks.movie(at: partial, quadrants: true)
        _ = try await files.finalize(partial)
        let doc = try await files.list().items.first!.document
        var edit = VideoPlayback()
        edit.zooms = [.init(range: .init(start: 0, end: 1), scale: 3, centerX: 0.2, centerY: 0.2)]
        var style = VideoPresentation(); style.padding = 16; style.backdrop = .solid
        _ = try await files.setEdit(doc.id, trim: nil, presentation: style, playback: edit, expectedRevision: 0)
        let url = root.appendingPathComponent("Focused.mp4")
        try await files.exportEdited(doc.id, to: url)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: .init(seconds: 0.5, preferredTimescale: 600))
        check(abs(result.actualTime.seconds - 0.5) < 1.0 / 30)
        let image = result.image
        let bitmap = NSBitmapImageRep(cgImage: image)
        check(image.width == 352 && image.height == 212)
        for point in [CGPoint(x: 25, y: 25), CGPoint(x: 320, y: 180), CGPoint(x: 170, y: 100)] {
            let color = bitmap.colorAt(x: Int(point.x), y: Int(point.y))!.usingColorSpace(.sRGB)!
            check(color.redComponent > 0.85 && color.greenComponent < 0.15 && color.blueComponent < 0.15, "Focus did not target the displayed top-left quadrant")
        }
    }
}
private func check(_ value: Bool, _ message: String = "Video playback check failed", file: StaticString = #fileID, line: UInt = #line) {
    precondition(value, message, file: file, line: line)
}

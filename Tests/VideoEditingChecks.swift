import AppKit
import AVFoundation
import ImageIO
import SnagForgeDomain

/// File-only fixtures: never opens a microphone, capture source or audio device.
@MainActor enum VideoEditingChecks {
    static let selection = VideoTrim(start: 0.23, end: 0.77)

    static func run() async throws {
        try await VideoPresentationChecks.run()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoEditing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VideoRecordingFiles(root: root.appendingPathComponent("Videos"))
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        try await VideoRecordingChecks.movie(at: partial, includesAudio: true, audioPulse: true)
        let original = try await files.finalize(partial, audio: .init(systemAudio: true))
        let document = try await files.list().items.first!.document
        let bytes = try Data(contentsOf: original), attributes = try FileManager.default.attributesOfItem(atPath: original.path)
        let model = VideoEditorModel(document: document, url: original, files: files)
        model.player.isMuted = true
        try await VideoTimelineChecks.run(model: model, original: original)
        defer { model.stopPreview() }
        model.start = 0.9; model.end = 0.1
        require(!model.isValid && !model.canApply)
        require(!(await model.apply()))
        require(!(await model.finishPendingWork()), "Quit silently discarded a draft")
        model.error = nil; model.discardDraft()
        require(await model.finishPendingWork())
        do { _ = try await files.setTrim(document.id, trim: .init(start: 0.9, end: 0.1), expectedRevision: 0); preconditionFailure("Invalid range persisted") } catch { }
        require(try await files.document(document.id).revision == 0)

        model.start = selection.start; model.end = selection.end
        require(!(await model.export(to: root.appendingPathComponent("Unsaved.mp4"))), "Unapplied draft exported")
        require(await model.apply() && !model.hasUnappliedChanges && model.document.trim == selection && model.document.revision == 1)
        require(await model.undo() && model.document.trim == nil && model.canRedo)
        require(await model.redo() && model.document.trim == selection && model.document.revision == 3)
        model.restoreOriginal(); require(model.hasUnappliedChanges)
        require(await model.apply() && model.document.trim == nil)
        require(await model.undo() && model.document.trim == selection)
        let persisted = try await VideoRecordingFiles(root: files.root).document(document.id)
        require(persisted.trim == selection && persisted.duration == document.duration && persisted.revision == 5)
        let reopened = VideoEditorModel(document: persisted, url: original, files: files)
        reopened.player.isMuted = true
        require(reopened.draft == selection && !reopened.canUndo && !reopened.canRedo)
        // AVPlayer's bounds use exactly the saved selection after reopening.
        require(abs(reopened.player.currentItem!.reversePlaybackEndTime.seconds - selection.start) < 0.0001)
        require(abs(reopened.player.currentItem!.forwardPlaybackEndTime.seconds - selection.end) < 0.0001)
        reopened.playSelection()
        for _ in 0..<100 {
            if reopened.position >= selection.end - 0.04 && reopened.player.rate == 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        require(reopened.position >= selection.end - 0.04 && reopened.position <= selection.end + 0.04 && reopened.player.rate == 0, "Preview did not stop at the selected end")
        reopened.stopPreview()

        let output = root.appendingPathComponent("Trimmed.mp4")
        try Data("Existing destination".utf8).write(to: output)
        require(await model.export(to: output) && model.notice != nil)
        model.notice = nil
        try await checkExport(original: original, output: output, audio: true)
        for target in [original, files.root.appendingPathComponent("Other.mp4"), files.root.appendingPathComponent(".library/Other.mp4")] {
            do { try await files.exportEdited(document.id, to: target); preconditionFailure("Library original could be overwritten") }
            catch VideoEditError.originalTarget { }
        }
        do { try await files.exportEdited(document.id, to: root.appendingPathComponent("missing/Video.mp4")); preconditionFailure("Missing parent export succeeded") } catch { }
        require(try Data(contentsOf: original) == bytes)
        let previous = try Data(contentsOf: output)
        // Cancellation after successful encoding/validation still preserves the
        // old destination. The gate deliberately ignores cancellation itself.
        let gate = ExportPublishGate()
        let cancelled = Task { try await files.exportEdited(document.id, to: output, beforePublish: { await gate.pause() }) }
        for _ in 0..<3000 {
            if await gate.reached { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        require(await gate.reached, "Encoding never reached the publication checkpoint")
        cancelled.cancel(); await gate.resume()
        do { try await cancelled.value; preconditionFailure("Cancelled export published") } catch is CancellationError { }
        require(try Data(contentsOf: output) == previous)
        let cancelledBeforeStart = Task { try await files.exportEdited(document.id, to: root.appendingPathComponent("Cancelled.mp4")) }
        cancelledBeforeStart.cancel()
        do { try await cancelledBeforeStart.value; preconditionFailure("Pre-cancelled export succeeded") } catch is CancellationError { }
        require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Cancelled.mp4").path))

        try await files.rename(document.id, title: "Concurrent title")
        model.start = 0.3
        require(!(await model.apply()) && model.error != nil && model.hasUnappliedChanges, "Stale save replaced the newer revision")
        require(try await files.document(document.id).trim == selection)
        model.discardDraft(); model.error = nil
        require(!(await model.export(to: output)) && model.error != nil, "Stale export accepted")
        require(try Data(contentsOf: output) == previous)
        model.error = nil; await model.reload()
        require(model.document.title == "Concurrent title" && model.draft == selection && !model.canUndo)

        let backup = root.appendingPathComponent("Backup")
        try await files.backup(to: backup)
        let restored = VideoRecordingFiles(root: root.appendingPathComponent("Restored"))
        require(try await restored.restore(from: backup) == 1)
        let copy = try await restored.list().items.first!.document
        require(copy.id != document.id && copy.trim == selection && copy.duration == document.duration)
        require(try Data(contentsOf: await restored.movieURL(copy.id)) == bytes, "Backup stored a destructive cut")
        try await restored.exportEdited(copy.id, to: root.appendingPathComponent("RestoredExport.mp4"))
        try await checkExport(original: original, output: root.appendingPathComponent("RestoredExport.mp4"), audio: true)

        let silentPartial = try await files.prepare(availableBytes: 1_000_000_000)
        try await VideoRecordingChecks.movie(at: silentPartial)
        let silentOriginal = try await files.finalize(silentPartial)
        let silent = try await files.list().items.first { $0.document.fileName == silentOriginal.lastPathComponent }!.document
        let fullCopy = root.appendingPathComponent("Full.mp4")
        try await files.exportEdited(silent.id, to: fullCopy)
        require(try Data(contentsOf: fullCopy) == Data(contentsOf: silentOriginal), "Full export rewrote the original")
        _ = try await files.setTrim(silent.id, trim: selection, expectedRevision: 0)
        try await files.exportEdited(silent.id, to: root.appendingPathComponent("SilentTrim.mp4"))
        try await checkExport(original: silentOriginal, output: root.appendingPathComponent("SilentTrim.mp4"), audio: false)
        let gif = root.appendingPathComponent("SilentTrim.gif")
        do {
            try await files.exportGIF(silent.id, to: root.appendingPathComponent("TooLong.gif"), options: .init(maximumDuration: 0.25))
            preconditionFailure("GIF export silently truncated the selection")
        } catch VideoRecordingError.gifDurationExceeded { }
        try await files.exportGIF(silent.id, to: gif, options: .init(framesPerSecond: 8, maximumDimension: 320, maximumDuration: 2))
        try checkGIF(gif, expectedMaximumFrames: 16, maximumDimension: 320)
        let priorGIF = try Data(contentsOf: gif)
        let gifGate = ExportPublishGate()
        let cancelledGIF = Task { try await files.exportGIF(silent.id, to: gif, options: .init(framesPerSecond: 8), beforePublish: { await gifGate.pause() }) }
        for _ in 0..<3000 { if await gifGate.reached { break }; try await Task.sleep(for: .milliseconds(5)) }
        require(await gifGate.reached, "GIF encoding never reached publication checkpoint")
        cancelledGIF.cancel(); await gifGate.resume()
        do { try await cancelledGIF.value; preconditionFailure("Cancelled GIF export published") } catch is CancellationError { }
        require(try Data(contentsOf: gif) == priorGIF, "Cancelled GIF export replaced destination")
        do { try await files.exportGIF(silent.id, to: silentOriginal); preconditionFailure("GIF export accepted library original") }
        catch VideoEditError.originalTarget { }
        do { try await files.exportGIF(silent.id, to: root.appendingPathComponent("Stale.gif"), expectedRevision: 0); preconditionFailure("GIF export accepted stale revision") }
        catch ProjectError.staleRevision { }
        _ = try await files.setTrim(silent.id, trim: .init(start: 0.4, end: 0.53), expectedRevision: 1)
        let shortGIF = root.appendingPathComponent("Short.gif")
        try await files.exportGIF(silent.id, to: shortGIF, options: .init(framesPerSecond: 8, maximumDimension: 320))
        try checkGIF(shortGIF, expectedMaximumFrames: 2, maximumDimension: 320)
        let shortFrames = CGImageSourceCreateWithURL(shortGIF as CFURL, nil)!
        require(CGImageSourceGetCount(shortFrames) == 2, "Short GIF lost its final partial interval")
        let lastGIF = NSBitmapImageRep(cgImage: CGImageSourceCreateImageAtIndex(shortFrames, 1, nil)!).colorAt(x: 10, y: 10)!.usingColorSpace(.sRGB)!
        let exactGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: silentOriginal))
        exactGenerator.maximumSize = CGSize(width: 320, height: 320); exactGenerator.appliesPreferredTrackTransform = true
        exactGenerator.requestedTimeToleranceBefore = .zero; exactGenerator.requestedTimeToleranceAfter = .zero
        let expectedFrame = try await exactGenerator.image(at: CMTime(seconds: 0.525, preferredTimescale: 60_000)).image
        // Compare in GIF's palette/color space, rather than the video's ICC space.
        let referenceData = NSMutableData()
        let referenceDestination = CGImageDestinationCreateWithData(referenceData, "com.compuserve.gif" as CFString, 1, nil)!
        CGImageDestinationAddImage(referenceDestination, expectedFrame, nil)
        require(CGImageDestinationFinalize(referenceDestination))
        let reference = CGImageSourceCreateWithData(referenceData, nil)!
        let expectedColor = NSBitmapImageRep(cgImage: CGImageSourceCreateImageAtIndex(reference, 0, nil)!).colorAt(x: 10, y: 10)!.usingColorSpace(.sRGB)!
        require(abs(lastGIF.redComponent - expectedColor.redComponent) < 0.025, "Short GIF did not sample the end of the selected range")
        _ = try await files.setTrim(silent.id, trim: .init(start: 0.2, end: 0.2 + 1.0 / 30), expectedRevision: 2)
        let oneFrame = root.appendingPathComponent("OneFrame.mp4")
        try await files.exportEdited(silent.id, to: oneFrame)
        require(try await frames(oneFrame).count == 1, "Minimum legal cut did not produce one video frame")
        let oneFrameGIF = root.appendingPathComponent("OneFrame.gif")
        try await files.exportGIF(silent.id, to: oneFrameGIF, options: .init(framesPerSecond: 8))
        require(CGImageSourceGetCount(CGImageSourceCreateWithURL(oneFrameGIF as CFURL, nil)!) == 1,
                "Minimum legal cut did not produce one GIF frame")
        let after = try FileManager.default.attributesOfItem(atPath: original.path)
        require(try Data(contentsOf: original) == bytes && (attributes[.systemFileNumber] as? NSNumber) == (after[.systemFileNumber] as? NSNumber)
            && (attributes[.modificationDate] as? Date) == (after[.modificationDate] as? Date), "Editing/export rewrote the original movie")
        // A damaged sidecar may not redirect a write to another video's ID.
        var mismatched = try await files.document(silent.id)
        mismatched.id = UUID()
        let damaged = files.root.appendingPathComponent(".library/\(silent.id).json")
        try JSONEncoder().encode(mismatched).write(to: damaged)
        do { _ = try await files.setTrim(silent.id, trim: nil, expectedRevision: mismatched.revision); preconditionFailure("Mismatched ID redirected a save") }
        catch ProjectError.invalidDocument { }
        require(!FileManager.default.fileExists(atPath: files.root.appendingPathComponent(".library/\(mismatched.id).json").path))
        print("Video editing passed: invalid bounds, applied-only export, saved revisions, Undo/Redo, full-original reset, reopened AVPlayer bounds and automatic stop, stale save/export refusal, reload, immutable bytes/inode/date, backup/restore with full original and trim, H.264 cuts between keyframes, AAC pulse timeline, silent cuts, atomic overwrite, cancellation before publish and protected library targets.")
    }

    private static func checkGIF(_ url: URL, expectedMaximumFrames: Int, maximumDimension: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { preconditionFailure("GIF source unreadable") }
        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= expectedMaximumFrames else { preconditionFailure("GIF frame count invalid") }
        var firstByte: UInt8?
        var lastByte: UInt8?
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil), max(image.width, image.height) <= maximumDimension else {
                preconditionFailure("GIF frame dimensions exceed bound")
            }
            if let data = image.dataProvider?.data as Data?, let byte = data.first {
                firstByte = firstByte ?? byte; lastByte = byte
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
            let gif = properties?[kCGImagePropertyGIFDictionary as String] as? NSDictionary
            require((gif?[kCGImagePropertyGIFDelayTime as String] as? NSNumber)?.doubleValue ?? 0 > 0, "GIF frame delay missing")
        }
        require(firstByte != nil && lastByte != nil && abs(Int(firstByte!) - Int(lastByte!)) > 2,
                "GIF frames did not preserve distinct source sections")
    }

    static func checkExport(original: URL, output: URL, audio: Bool) async throws {
        let asset = AVURLAsset(url: output), duration = try await asset.load(.duration).seconds
        require(abs(duration - selection.duration) <= 2.0 / 30, "Export retained the untrimmed duration")
        let track = try await asset.loadTracks(withMediaType: .video).first!
        require(try await track.load(.naturalSize) == CGSize(width: 320, height: 180))
        require(try await track.load(.formatDescriptions).allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 })
        let sourceFrames = try await frames(original), cut = try await frames(output)
        func matched(_ gray: Double) -> (time: Double, gray: Double) { sourceFrames.min { abs($0.gray - gray) < abs($1.gray - gray) }! }
        let first = matched(cut.first!.gray).time, last = matched(cut.last!.gray).time
        require(abs(cut.first!.time) <= 1.0 / 30 && abs(first - selection.start) <= 1.0 / 30, "First encoded frame contains keyframe preroll")
        require(abs(last - selection.end) <= 1.0 / 30, "Exported last frame lies outside the selection")
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        require(audioTracks.count == (audio ? 1 : 0), "Export lost or introduced audio")
        if audio {
            let format = try await audioTracks[0].load(.formatDescriptions).first!
            require(CMAudioFormatDescriptionGetStreamBasicDescription(format)!.pointee.mFormatID == kAudioFormatMPEG4AAC)
            let pcm = try decodedAudio(asset, track: audioTracks[0])
            require(abs(pcm.first) <= 1.0 / 30 && abs(pcm.end - duration) < 0.05, "Cut audio timestamps diverged")
            let pulse = pcm.values.firstIndex { abs($0) > 0.05 }!
            let pulseTime = pcm.first + Double(pulse) / (48_000 * 2)
            let visualPulse = cut.min { abs($0.gray - sourceFrames[10].gray) < abs($1.gray - sourceFrames[10].gray) }!.time
            require(abs(pulseTime - (10.0 / 30 - selection.start)) < 0.04 && abs(pulseTime - visualPulse) < 0.04, "Export moved the synthetic audio pulse relative to its video frame")
            print("Synthetic trim: duration \(duration), source frames \(first)...\(last), AAC pulse \(pulseTime), corresponding video \(visualPulse).")
        }
    }

    static func frames(_ url: URL) async throws -> [(time: Double, gray: Double)] {
        let asset = AVURLAsset(url: url), track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); require(reader.startReading())
        var frames: [(Double, Double)] = []
        while let sample = output.copyNextSampleBuffer() {
            let pixel = CMSampleBufferGetImageBuffer(sample)!
            CVPixelBufferLockBaseAddress(pixel, .readOnly)
            let bytes = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixel), width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
            var gray = 0.0
            for y in (height / 2 - 5)..<(height / 2 + 5) { for x in (width / 2 - 5)..<(width / 2 + 5) { gray += Double(bytes[y * stride + x * 4 + 1]) } }
            CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
            frames.append((CMSampleBufferGetPresentationTimeStamp(sample).seconds, gray / 100))
        }
        require(reader.status == .completed && !frames.isEmpty)
        return frames
    }
    static func decodedAudio(_ asset: AVURLAsset, track: AVAssetTrack) throws -> (first: Double, end: Double, values: [Float]) {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(output); require(reader.startReading())
        var first: Double?, end = 0.0, values: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            first = first ?? time; end = time + Double(CMSampleBufferGetNumSamples(sample)) / 48_000
            let block = CMSampleBufferGetDataBuffer(sample)!
            var samples = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / 4)
            require(samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) } == noErr)
            values.append(contentsOf: samples)
        }
        require(reader.status == .completed && !values.isEmpty)
        return (first!, end, values)
    }
    static func restart(write: Bool, key: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VideoEditRestart-\(key)"), files = VideoRecordingFiles(root: folder)
        if write {
            let partial = try await files.prepare(availableBytes: 1_000_000_000)
            try await VideoRecordingChecks.movie(at: partial, includesAudio: true, audioPulse: true)
            _ = try await files.finalize(partial, audio: .init(systemAudio: true))
            let document = try await files.list().items.first!.document
            _ = try await files.setTrim(document.id, trim: selection, expectedRevision: 0)
        } else {
            defer { try? FileManager.default.removeItem(at: folder) }
            let item = try await files.list().items.first!, original = try await files.movieURL(item.id)
            require(item.document.trim == selection && item.document.revision == 1)
            let export = folder.deletingLastPathComponent().appendingPathComponent("VideoEditRestart-\(key).mp4")
            defer { try? FileManager.default.removeItem(at: export) }
            try await files.exportEdited(item.id, to: export)
            try await checkExport(original: original, output: export, audio: true)
        }
        print("Video edit process restart \(write ? "write" : "read") passed.")
    }
}

private actor ExportPublishGate {
    var reached = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async { reached = true; await withCheckedContinuation { continuation = $0 } }
    func resume() { continuation?.resume(); continuation = nil }
}
@main struct VideoEditingRunner {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3 { try await VideoEditingChecks.restart(write: CommandLine.arguments[1] == "--write", key: CommandLine.arguments[2]) }
        else { try await VideoEditingChecks.run() }
    }
}
private func require(_ value: Bool, _ message: String = "Video editing check failed", file: StaticString = #fileID, line: UInt = #line) { precondition(value, message, file: file, line: line) }

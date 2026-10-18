import AppKit
import AVFoundation
import ScreenCaptureKit
import SnagForgeDomain

#if !VIDEO_PERMISSION_CHECKS && !VIDEO_LIBRARY_CHECKS && !VIDEO_EDITING_CHECKS && !VIDEO_VALIDATION_CHECKS
@main
#endif
struct VideoRecordingChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count > 1 {
            try await inspect(URL(fileURLWithPath: CommandLine.arguments[1])); return
        }
        try checkConfiguration()
        try await checkMicrophoneAccess()
        try await VideoLifecycleChecks.engines()
        try await VideoLibraryChecks.run()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Video-Tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = VideoRecordingFiles(root: root.appendingPathComponent("Recordings"))
        do { _ = try await files.prepare(availableBytes: 1); preconditionFailure("Low space accepted") }
        catch VideoRecordingError.lowSpace { }
        let partial = try await files.prepare(availableBytes: 1_000_000_000)
        check(try await files.completed().isEmpty)
        try await movie(at: partial)
        let ready = try await files.finalize(partial)
        check(!FileManager.default.fileExists(atPath: partial.path))
        check(try await files.completed().map(\.lastPathComponent) == [ready.lastPathComponent])
        let restarted = VideoRecordingFiles(root: root.appendingPathComponent("Recordings"))
        check(try await restarted.completed().map(\.lastPathComponent) == [ready.lastPathComponent], "Finished video lost on restart")
        let target = root.appendingPathComponent("Export.mp4")
        try await files.export(ready, to: target)
        let originalBytes = try Data(contentsOf: ready)
        check(try Data(contentsOf: target) == originalBytes)
        // Atomic replacement must replace the old destination, not truncate it in place.
        try Data("Previous destination".utf8).write(to: target)
        try await files.export(ready, to: target)
        check(try Data(contentsOf: target) == originalBytes)
        do { try await files.export(ready, to: root.appendingPathComponent("missing/Export.mp4")); preconditionFailure("Export failure ignored") }
        catch { check(try Data(contentsOf: ready) == originalBytes, "Failed save lost the original recording") }
        let invalid = try await files.prepare(availableBytes: 1_000_000_000)
        try Data("not an MP4".utf8).write(to: invalid)
        do { _ = try await files.finalize(invalid); preconditionFailure("Invalid movie published") } catch { }
        check(try await files.completed().map(\.lastPathComponent) == [ready.lastPathComponent])
        await files.discardPartial(invalid)
        check(!FileManager.default.fileExists(atPath: invalid.path), "Failed partial recording was not cleaned up")
        let asset = AVURLAsset(url: target)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await tracks[0].load(.naturalSize)
        let duration = try await asset.load(.duration)
        check(size == CGSize(width: 320, height: 180) && CMTimeGetSeconds(duration) > 0.9)
        let frame = try await AVAssetImageGenerator(asset: asset).image(at: CMTime(value: 1, timescale: 2)).image
        check(frame.width == 320 && frame.height == 180)
        check(try await asset.loadTracks(withMediaType: .audio).isEmpty, "Silent capture gained an audio track")

        let missingAudio = try await files.prepare(availableBytes: 1_000_000_000)
        try FileManager.default.copyItem(at: ready, to: missingAudio)
        do {
            _ = try await files.finalize(missingAudio, audio: .init(systemAudio: true))
            preconditionFailure("Requested system audio silently omitted")
        } catch VideoRecordingError.missingAudio { }
        check(try await files.completed().count == 1, "Missing audio was published as a completed recording")
        await files.discardPartial(missingAudio)

        let withAudio = try await files.prepare(availableBytes: 1_000_000_000)
        try await movie(at: withAudio, includesAudio: true)
        let audioReady = try await files.finalize(withAudio, audio: .init(systemAudio: true))
        try await checkAudio(at: audioReady)
        let audioExport = root.appendingPathComponent("With-Audio.mp4")
        try await files.export(audioReady, to: audioExport)
        check(try Data(contentsOf: audioExport) == Data(contentsOf: audioReady), "Export changed the audio/video data")
        try await checkAudio(at: audioExport)
        check(try await restarted.completed().count == 2, "Recording with audio lost on restart")

        let silentAudio = try await files.prepare(availableBytes: 1_000_000_000)
        try await movie(at: silentAudio, includesAudio: true, amplitude: 0)
        let silenceReady = try await files.finalize(silentAudio, audio: .init(systemAudio: true))
        try await checkAudio(at: silenceReady, expectsTone: false)

        for options in [VideoAudioOptions(microphone: true), .init(systemAudio: true, microphone: true)] {
            let absent = try await files.prepare(availableBytes: 1_000_000_000)
            try FileManager.default.copyItem(at: ready, to: absent)
            do {
                _ = try await files.finalize(absent, audio: options)
                preconditionFailure("Requested microphone/combined audio silently omitted")
            } catch VideoRecordingError.missingAudio { }
            await files.discardPartial(absent)
            let present = try await files.prepare(availableBytes: 1_000_000_000)
            try FileManager.default.copyItem(at: audioReady, to: present)
            let result = try await files.finalize(present, audio: options)
            try await checkAudio(at: result)
        }
        print("Video checks passed: four independent audio configurations, explicit microphone authorization/denial/retry/cancellation, system audio 48 kHz/stereo, self excluded, silent MP4, AAC encode/decode and timing, valid silence, missing audio refusal, finalized playable MP4, dimensions/duration/frame, low-space refusal, atomic save/overwrite, save failure preserves original, invalid output rejected, restart discovery.")
    }
    @MainActor static func checkConfiguration() throws {
        let geometry = try VideoGeometry(selection: CGRect(x: 110, y: 220, width: 320, height: 180),
            screen: CGRect(x: 100, y: 200, width: 1920, height: 1080), scale: 2)
        check(VideoAudioOptions() == .init(systemAudio: false, microphone: false), "Audio must be opt-in for each session")
        for system in [false, true] {
            for microphone in [false, true] {
                let audio = VideoAudioOptions(systemAudio: system, microphone: microphone)
                let config = VideoRecordingEngine.configuration(geometry: geometry, includesCursor: !system, audio: audio)
                check(config.capturesAudio == system && config.captureMicrophone == microphone, "System and microphone selections are not independent")
                check(config.microphoneCaptureDeviceID == nil, "Use the macOS default microphone")
                check(audio.requiresAudio == (system || microphone))
                check(config.excludesCurrentProcessAudio, "Snaprivo audio must be excluded")
                check(config.sampleRate == 48_000 && config.channelCount == 2)
                check(config.queueDepth == 8, "H.264 recording needs the hardware-tested surface headroom")
                check(config.sourceRect == geometry.sourceRect && config.width == 640 && config.height == 360)
                check(config.showsCursor == !system && config.minimumFrameInterval == CMTime(value: 1, timescale: 30))
                check(config.captureDynamicRange == .SDR && config.preservesAspectRatio && !config.scalesToFit)
            }
        }
        let windowGeometry = try VideoGeometry(contentSize: CGSize(width: 1200, height: 800), scale: 2)
        let window = VideoRecordingEngine.configuration(geometry: windowGeometry, includesCursor: false, audio: .init(), windowCapture: true)
        check(window.sourceRect == SCStreamConfiguration().sourceRect, "A fixed crop prevents recording the whole resized window")
        check(window.scalesToFit && window.preservesAspectRatio && window.ignoreShadowsSingleWindow)
        check(window.backgroundColor.components == [0, 1], "Window letterboxing keeps an opaque black background alive")
        check(window.width == 1620 && window.height == 1080 && window.captureDynamicRange == .SDR)
        check(!window.capturesAudio && !window.captureMicrophone)
    }
    @MainActor static func checkMicrophoneAccess() async throws {
        // No real authorization prompt or microphone input is used in tests.
        let unused = VideoMicrophoneAccess(status: { preconditionFailure("Audio without microphone checked its permission") },
            request: { preconditionFailure("Audio without microphone requested permission") },
            hasInput: { preconditionFailure("Audio without microphone enumerated input") })
        try await unused.authorize(ifNeeded: false)

        for state in [AVAuthorizationStatus.authorized, .notDetermined, .denied, .restricted] {
            var requests = 0, inputs = 0
            let access = VideoMicrophoneAccess(status: { state }, request: { requests += 1; return true },
                hasInput: { inputs += 1; return true })
            do {
                try await access.authorize(ifNeeded: true)
                check(state == .authorized || state == .notDetermined)
                check(inputs == 1)
            } catch VideoMicrophoneError.denied { check(state == .denied && inputs == 0) }
            catch VideoMicrophoneError.restricted { check(state == .restricted && inputs == 0) }
            check(requests == (state == .notDetermined ? 1 : 0), "Repeated or unnecessary system permission request")
        }
        var deniedRequests = 0
        let denied = VideoMicrophoneAccess(status: { .notDetermined }, request: { deniedRequests += 1; return false },
            hasInput: { preconditionFailure("Input accessed after denial") })
        do { try await denied.authorize(ifNeeded: true); preconditionFailure("Permission denial ignored") }
        catch VideoMicrophoneError.denied { check(deniedRequests == 1) }

        let noInput = VideoMicrophoneAccess(status: { .authorized }, request: { preconditionFailure("Authorized input prompted again") },
            hasInput: { false })
        do { try await noInput.authorize(ifNeeded: true); preconditionFailure("Missing microphone accepted") }
        catch VideoMicrophoneError.unavailable { }

        let permission = MicrophoneTestPermission()
        let retry = VideoMicrophoneAccess(status: { permission.status }, request: { preconditionFailure("Retry unexpectedly prompted") }, hasInput: { true })
        do { try await retry.authorize(ifNeeded: true); preconditionFailure("Permission denial ignored") }
        catch VideoMicrophoneError.denied { }
        permission.status = .authorized
        try await retry.authorize(ifNeeded: true)

        var pending: CheckedContinuation<Bool, Never>?
        let delayed = VideoMicrophoneAccess(status: { .notDetermined },
            request: { await withCheckedContinuation { pending = $0 } },
            hasInput: { preconditionFailure("Cancelled authorization continued toward recording") })
        let task = Task { try await delayed.authorize(ifNeeded: true) }
        while pending == nil { await Task.yield() }
        task.cancel(); pending?.resume(returning: true)
        do { try await task.value; preconditionFailure("Cancelled permission wait continued") }
        catch is CancellationError { }
    }
    @MainActor static func checkPermissionPanel() async throws {
        _ = NSApplication.shared
        let screen = NSScreen.main!.frame
        let selection = ScreenshotSelection(displayID: 0,
            rect: CGRect(x: screen.minX + 50, y: screen.minY + 50, width: 320, height: 180), screenFrame: screen)
        var statusReads = 0, screenFailures = 0
        let permission = MicrophoneTestPermission()
        var pending: CheckedContinuation<Bool, Never>?
        let access = VideoMicrophoneAccess(status: { statusReads += 1; return permission.status },
            request: { await withCheckedContinuation { pending = $0 } },
            hasInput: { preconditionFailure("Denied or cancelled input was opened") })
        let session = VideoRecordingSession(selection: selection, includesCursor: false, delaySeconds: 3, microphoneAccess: access,
            waitCountdownSecond: { preconditionFailure("Denied or cancelled authorization started countdown") })
        session.onPermissionFailure = { _ in screenFailures += 1 }
        let run = Task { await session.run() }
        try await Task.sleep(for: .milliseconds(150))
        let view = NSApp.windows.first { $0.identifier?.rawValue == "video.controls" && $0.isVisible }!.contentView!
        func button(_ identifier: String) -> NSButton {
            view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == identifier }!
        }
        let microphone = button("video.microphone"), system = button("video.systemAudio"), primary = button("video.primary")
        let settings = button("video.microphoneSettings")
        let status = view.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "video.status" }!
        check(microphone.state == .off && system.state == .off && settings.isHidden)
        microphone.performClick(nil)
        check(microphone.state == .on && statusReads == 0, "Toggling microphone requested access before Start")
        for attempt in 1...2 {
            primary.performClick(nil)
            for _ in 0..<200 {
                if session.phase == .ready && statusReads == attempt { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            check(session.phase == .ready && primary.isEnabled && microphone.isEnabled && system.isEnabled)
            check(statusReads == attempt && screenFailures == 0, "Microphone denial changed screen permissions")
            check(microphone.state == .on && !settings.isHidden, "Permission denial discarded the user's selection")
            check(status.stringValue == VideoMicrophoneError.denied.localizedDescription)
        }
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("MicrophoneDeniedControls-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }
        try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
        microphone.performClick(nil)
        check(microphone.state == .off && settings.isHidden && primary.isEnabled, "Could not recover without microphone")

        permission.status = .notDetermined
        microphone.performClick(nil); primary.performClick(nil)
        for _ in 0..<200 {
            if pending != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        check(pending != nil && session.phase == .starting && !microphone.isEnabled)
        let closing = Task { await session.closeSafely() }
        try await Task.sleep(for: .milliseconds(10))
        pending?.resume(returning: true)
        await closing.value; await run.value
        check(session.phase == .ready, "Late permission result started or failed a closed session")
        print("Native microphone permission controls passed: no request on toggle, denial/retry preserves selection, screen permission unchanged, recover without microphone, closing during permission wait prevents late capture, rendered error/settings.")
    }
    static func checkAudio(at url: URL, expectsTone: Bool = true) async throws {
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        check(audio.count == 1)
        let descriptions = try await audio[0].load(.formatDescriptions)
        let format = CMAudioFormatDescriptionGetStreamBasicDescription(descriptions[0])!.pointee
        check(format.mFormatID == kAudioFormatMPEG4AAC && format.mSampleRate == 48_000 && format.mChannelsPerFrame == 2)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audio[0], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output); check(reader.startReading())
        var count = 0, energy = 0.0, firstTime: Double?, endTime = 0.0
        while let sample = output.copyNextSampleBuffer() {
            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            if firstTime == nil { firstTime = timestamp }
            endTime = timestamp + Double(CMSampleBufferGetNumSamples(sample)) / 48_000
            let block = CMSampleBufferGetDataBuffer(sample)!
            var samples = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size)
            let result = samples.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            check(result == kCMBlockBufferNoErr)
            for value in samples { energy += Double(value * value) }
            count += samples.count
        }
        check(reader.status == .completed && count > 90_000, "Audio could not be fully decoded")
        let rms = sqrt(energy / Double(count))
        check(expectsTone ? rms > 0.1 : rms < 0.001, "Decoded tone/silence differs from fixture")
        let videoDuration = CMTimeGetSeconds(try await asset.load(.duration))
        check(abs(firstTime ?? .infinity) < 1.0 / 30 && abs(endTime - videoDuration) < 0.1, "Audio/video fixture timestamps diverged")
    }
    static func inspect(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let size = try await tracks[0].load(.naturalSize)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
        let last = try await generator.image(at: CMTime(seconds: max(0.1, duration - 0.2), preferredTimescale: 600)).image
        check(first.width == Int(size.width) && first.height == Int(size.height))
        check(duration > 0)
        let firstPixels = first.dataProvider!.data! as Data, lastPixels = last.dataProvider!.data! as Data
        check(firstPixels != lastPixels, "Video contains no changed frame despite moving test content")
        if !audio.isEmpty {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audio[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(output); check(reader.startReading())
            defer { reader.cancelReading() }
            check(output.copyNextSampleBuffer() != nil, "Recorded audio could not be decoded")
        }
        print("Recorded MP4 verified: \(Int(size.width)) × \(Int(size.height)), \(duration) seconds, \(audio.count) audio tracks, two different decoded frames.")
    }
    static func movie(at url: URL, includesAudio: Bool = false, amplitude: Double = 0.3, audioPulse: Bool = false) async throws {
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
        ])
        if includesAudio { writer.add(audioInput) }
        check(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var pixel: CVPixelBuffer?
            check(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel) == kCVReturnSuccess)
            let buffer = pixel!
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(index * 7), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            check(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
            if includesAudio {
                while !audioInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
                check(audioInput.append(try tone(frame: index, amplitude: !audioPulse || (10...13).contains(index) ? amplitude : 0)))
            }
        }
        input.markAsFinished()
        if includesAudio { audioInput.markAsFinished() }
        await writer.finishWriting()
        if let error = writer.error { throw error }
        check(writer.status == .completed)
    }
    static func tone(frame: Int, amplitude: Double) throws -> CMSampleBuffer {
        let frames = 1_600, channels = 2
        let samples = (0..<(frames * channels)).map {
            Float(amplitude * sin(2 * .pi * 440 * Double(frame * frames + $0 / channels) / 48_000))
        }
        let byteCount = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        check(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr)
        check(samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: byteCount)
        } == kCMBlockBufferNoErr)
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
            mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        check(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
            layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMTime(value: Int64(frame * frames), timescale: 48_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        check(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: description, sampleCount: frames, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        return sample!
    }
}

private func check(_ condition: Bool, _ message: String = "Video check failed", file: StaticString = #fileID, line: UInt = #line) { precondition(condition, message, file: file, line: line) }

@MainActor private final class MicrophoneTestPermission {
    var status: AVAuthorizationStatus = .denied
}

#if VIDEO_PERMISSION_CHECKS
/// AppKit may stop nested run loops while ordering/closing panels. Use the native
/// application event loop instead of Swift's async-main queue drain for this host.
@main struct VideoPermissionChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let result = PermissionCheckCompletion()
        Task { @MainActor in
            do {
                try await VideoRecordingChecks.checkPermissionPanel()
                try await VideoLifecycleChecks.sessions()
                try await VideoCountdownChecks.sessions()
                result.completed = true
            }
            catch { preconditionFailure("Native permission check failed: \(error)") }
            app.stop(nil)
            let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
            app.postEvent(event, atStart: true)
        }
        app.run()
        check(result.completed, "Native event loop exited before the permission checks completed")
    }
}
@MainActor private final class PermissionCheckCompletion {
    var completed = false
}
#endif

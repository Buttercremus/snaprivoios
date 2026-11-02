import AVFoundation

enum SyntheticVideoFixture {
    /// A quiet tone gives the editor's volume control a real audio track to act on.
    static func write(to url: URL, includesAudio: Bool = false) async throws {
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                                                           AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
        if includesAudio { writer.add(audio) }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        func appendVideo(_ frame: Int) throws {
            var pixel: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel) == kCVReturnSuccess, let pixel else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(pixel, [])
            let pixels = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixel)
            for y in 0..<180 { for x in 0..<320 {
                var color: (UInt8, UInt8, UInt8) = (242, 245, 250)
                if y < 28 { color = (28, 42, 66) }
                else if x < 68 { color = (218, 228, 242) }
                else if (84..<184).contains(x) && (44..<124).contains(y) { color = (238, 104, 96) }
                else if (196..<304).contains(x) && (44..<124).contains(y) { color = (66, 139, 233) }
                else if (144..<158).contains(y) && x >= 84 && x < min(304, 100 + frame * 3) { color = (65, 171, 113) }
                if y >= 28 && (x % 32 == 0 || y % 32 == 0) { color = (168, 184, 204) }
                let offset = y * stride + x * 4
                pixels[offset] = 255; pixels[offset + 1] = color.0; pixels[offset + 2] = color.1; pixels[offset + 3] = color.2
            } }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        }
        // The writer interleaves tracks: feed whichever input is ready instead of waiting on one of them.
        var video = 0, sound = includesAudio ? 0 : 60, idle = 0
        while video < 60 || sound < 60 {
            var progressed = false
            // A finished track is marked at once; an open one would hold the other back.
            if video < 60, input.isReadyForMoreMediaData {
                try appendVideo(video); video += 1; progressed = true
                if video == 60 { input.markAsFinished() }
            }
            if sound < 60, audio.isReadyForMoreMediaData {
                guard audio.append(try tone(frame: sound)) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                sound += 1; progressed = true
                if sound == 60 { audio.markAsFinished() }
            }
            if progressed { idle = 0; continue }
            idle += 1
            guard idle < 5_000 else { throw CocoaError(.fileWriteUnknown) }
            try await Task.sleep(for: .milliseconds(2))
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
    private static func tone(frame: Int) throws -> CMSampleBuffer {
        let frames = 1_600, channels = 2
        let samples = (0..<(frames * channels)).map { Float(0.1 * sin(2 * .pi * 440 * Double(frame * frames + $0 / channels) / 48_000)) }
        let byteCount = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr, let block,
              samples.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount) }) == kCMBlockBufferNoErr
        else { throw CocoaError(.fileWriteUnknown) }
        var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format, layoutSize: 0, layout: nil, magicCookieSize: 0,
                magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr else { throw CocoaError(.fileWriteUnknown) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(value: Int64(frame * frames), timescale: 48_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: description, sampleCount: frames,
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr,
              let sample else { throw CocoaError(.fileWriteUnknown) }
        return sample
    }
}

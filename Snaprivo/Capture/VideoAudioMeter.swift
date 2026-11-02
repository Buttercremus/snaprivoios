import AVFoundation
import AudioToolbox
import SnagForgeDomain

enum VideoAudioSource: Hashable, Sendable { case system, microphone }

/// Audio bytes never leave the sample queue. Only bounded aggregate numbers reach UI.
final class VideoAudioMeter: @unchecked Sendable {
    private struct Window {
        var time: UInt64?
        var squares = 0.0, peak = 0.0
        var count = 0
    }
    private let lock = NSLock()
    private var windows: [VideoAudioSource: Window] = [:]
    func read(_ sample: CMSampleBuffer, source: VideoAudioSource, at time: UInt64 = DispatchTime.now().uptimeNanoseconds) -> AudioSignalLevel? {
        guard let level = Self.decode(sample) else { return nil }
        lock.lock(); defer { lock.unlock() }
        var window = windows[source] ?? Window()
        if window.count + level.sampleCount > 1_000_000 { window.count = 0; window.squares = 0; window.peak = 0 }
        window.count += level.sampleCount; window.squares += level.rms * level.rms * Double(level.sampleCount)
        window.peak = max(window.peak, level.peak)
        if let previous = window.time, time >= previous, time - previous < 100_000_000 {
            windows[source] = window; return nil
        }
        let value = AudioSignalLevel(rms: min(window.peak, sqrt(window.squares / Double(window.count))), peak: window.peak, sampleCount: window.count)
        window = Window(time: time); windows[source] = window
        return value
    }
    static func decode(_ sample: CMSampleBuffer) -> AudioSignalLevel? {
        guard CMSampleBufferDataIsReady(sample), let description = CMSampleBufferGetFormatDescription(sample),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM, (1...32).contains(format.mChannelsPerFrame),
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else { return nil }
        let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let signed = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        let bytes = Int(format.mBitsPerChannel / 8)
        guard (floating && [32, 64].contains(format.mBitsPerChannel)) || (signed && [16, 32].contains(format.mBitsPerChannel)) else { return nil }
        let channels = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 1 : Int(format.mChannelsPerFrame)
        guard Int(format.mBytesPerFrame) == bytes * channels else { return nil }
        var needed = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: &needed,
            bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), blockBufferOut: nil) == noErr,
              needed > 0, needed <= 4096 else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { storage.deallocate() }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil,
            bufferListOut: list, bufferListSize: needed, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), blockBufferOut: &block) == noErr,
              (1...32).contains(list.pointee.mNumberBuffers) else { return nil }
        return withExtendedLifetime(block) {
            var squares = 0.0, peak = 0.0, count = 0
            for buffer in UnsafeMutableAudioBufferListPointer(list) {
                guard let data = buffer.mData, buffer.mDataByteSize > 0, buffer.mDataByteSize <= 1_048_576 else { continue }
                let length = min(4096, Int(buffer.mDataByteSize) / bytes)
                let level: AudioSignalLevel?
                if floating && bytes == 4 {
                    level = .measure(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: length))
                } else if floating {
                    level = .measure(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Double.self), count: length))
                } else if bytes == 2 {
                    level = .measure(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int16.self), count: length).lazy.map { Double($0) / 32768 })
                } else {
                    level = .measure(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int32.self), count: length).lazy.map { Double($0) / 2_147_483_648 })
                }
                guard let level else { continue }
                squares += level.rms * level.rms * Double(level.sampleCount)
                count += level.sampleCount; peak = max(peak, level.peak)
            }
            guard count > 0 else { return nil }
            return AudioSignalLevel(rms: min(peak, sqrt(squares / Double(count))), peak: peak, sampleCount: count)
        }
    }
}

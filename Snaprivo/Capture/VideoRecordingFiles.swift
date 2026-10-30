import Foundation
import AVFoundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers
import SnagForgeDomain

struct VideoGIFOptions: Equatable, Sendable {
    var framesPerSecond: Int = 12
    var maximumDimension: Int = 720
    var maximumDuration: Double = 15

    func validated() throws -> Self {
        guard (1...24).contains(framesPerSecond), (160...1_440).contains(maximumDimension),
              maximumDuration.isFinite, (0.25...30).contains(maximumDuration) else {
            throw VideoRecordingError.invalidGIFOptions
        }
        return self
    }
}

actor VideoRecordingFiles {
    struct Item: Identifiable, Sendable {
        var document: VideoDocument
        var thumbnail: Data?
        var id: UUID { document.id }
        var bytes: Int64 = 0
    }
    struct Listing: Sendable { var items: [Item]; var issues: [String] }
    let root: URL
    private var active = Set<UUID>()
    private var listingTask: Task<Listing, any Error>?
    private var metadata: URL { root.appendingPathComponent(".library", isDirectory: true) }
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snaprivo/VideoRecordings", isDirectory: true)
    }
    func prepare(availableBytes: Int64? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let capacity = try availableBytes ?? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < 128 * 1024 * 1024 { throw VideoRecordingError.lowSpace }
        let id = UUID()
        let name = ".\(id).recording.mp4"
        let document = VideoDocument(id: id, title: String(localized: "Video – ") + Date.now.formatted(date: .abbreviated, time: .standard), fileName: name)
        try save(document); active.insert(id)
        return root.appendingPathComponent(name)
    }
    /// A visible .mp4 is published only after SCK's finish callback AND validation.
    func finalize(_ partial: URL, audio options: VideoAudioOptions = .init()) async throws -> URL {
        try requireRegularFile(partial)
        let asset = AVURLAsset(url: partial)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        guard let track = tracks.first, CMTimeGetSeconds(duration).isFinite, CMTimeGetSeconds(duration) > 0 else { throw VideoRecordingError.invalidMovie }
        let size = try await track.load(.naturalSize)
        guard size.width > 0, size.height > 0 else { throw VideoRecordingError.invalidMovie }
        _ = try await movieInfo(asset)
        if options.requiresAudio {
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard let audioTrack = audio.first else { throw VideoRecordingError.missingAudio }
            // Silence is valid. A missing or undecodable track must not be reported
            // as a successful recording with the requested audio. This does not
            // prove that each source contributed to a combined SCK audio track.
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            guard reader.canAdd(output) else { throw VideoRecordingError.missingAudio }
            reader.add(output)
            guard reader.startReading() else { throw VideoRecordingError.missingAudio }
            defer { reader.cancelReading() }
            guard let sample = output.copyNextSampleBuffer(), CMSampleBufferGetNumSamples(sample) > 0 else {
                throw VideoRecordingError.missingAudio
            }
        }
        guard let original = try record(for: partial) else { throw ProjectError.invalidDocument }
        var document = original
        let target = root.appendingPathComponent("\(document.id).mp4")
        document.fileName = target.lastPathComponent; document.state = .finished
        document.duration = CMTimeGetSeconds(duration)
        document.pixelSize = PixelSize(width: Int(size.width), height: Int(size.height))
        document.hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        document.modifiedAt = .now; document.failure = nil
        let thumbnail = try? await makeThumbnail(asset)
        // Journal the destination before moving. A crash between move and commit
        // leaves an interrupted known file, never an adoptable legacy movie.
        var pending = document; pending.state = .recording; try save(pending)
        do { try FileManager.default.moveItem(at: partial, to: target); try save(document) }
        catch { try? FileManager.default.moveItem(at: target, to: partial); try? save(original); throw error }
        active.remove(document.id)
        if let thumbnail { try? thumbnail.write(to: thumbnailURL(document.id), options: .atomic) }
        return target
    }
    func completed() async throws -> [URL] {
        try await list().items.filter { $0.document.state == .finished }.map { root.appendingPathComponent($0.document.fileName) }
    }
    private func legacyFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func discardPartial(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path,
              url.lastPathComponent.hasPrefix(".") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func markFailed(_ partial: URL, message: String?) throws {
        guard var document = try record(for: partial) else { return }
        document.state = message == nil ? .interrupted : .failed
        document.failure = message.map { String($0.prefix(800)) }
        document.modifiedAt = .now
        active.remove(document.id); try save(document)
    }

    func list() async throws -> Listing {
        if let listingTask { return try await listingTask.value }
        let task = Task { try await loadListing() }
        listingTask = task
        defer { listingTask = nil }
        return try await task.value
    }
    private func loadListing() async throws -> Listing {
        guard FileManager.default.fileExists(atPath: root.path) else { return Listing(items: [], issues: []) }
        var documents: [VideoDocument] = [], issues: [String] = []
        if FileManager.default.fileExists(atPath: metadata.path) {
            for url in try FileManager.default.contentsOfDirectory(at: metadata, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                do {
                    var document = try read(url)
                    guard url.lastPathComponent == "\(document.id).json" else { throw ProjectError.invalidDocument }
                    if document.state == .recording && !active.contains(document.id) {
                        document.state = .interrupted; document.modifiedAt = .now; try save(document)
                    }
                    documents.append(document)
                } catch { issues.append(url.lastPathComponent + ": " + error.localizedDescription) }
            }
        }
        // Previous versions published only finalized top-level MP4s. Validate
        // before adopting, and never bypass unreadable/newer metadata.
        if issues.isEmpty {
            let known = Set(documents.map(\.fileName))
            for url in try legacyFiles() where !known.contains(url.lastPathComponent) {
                var document = VideoDocument(title: String(localized: "Video – ") + url.deletingPathExtension().lastPathComponent,
                    fileName: url.lastPathComponent, state: .failed,
                    createdAt: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now)
                do {
                    try requireRegularFile(url)
                    let asset = AVURLAsset(url: url)
                    let info = try await movieInfo(asset)
                    document.state = .finished; document.duration = info.duration; document.pixelSize = info.size; document.hasAudio = info.audio
                    if let thumb = try? await makeThumbnail(asset) {
                        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
                        try? thumb.write(to: thumbnailURL(document.id), options: .atomic)
                    }
                } catch { document.failure = String(localized: "Die Videodatei ist nicht lesbar.") }
                try save(document); documents.append(document)
            }
        }
        let items = documents.map { original in
            var document = original
            if document.state == .finished, (try? requireRegularFile(root.appendingPathComponent(document.fileName))) == nil {
                document.state = .failed; document.failure = String(localized: "Die Videodatei fehlt oder ist nicht zugänglich.")
            }
            return Item(document: document, thumbnail: document.state == .finished ? try? ProjectArchive.readRegularFile(thumbnailURL(document.id), limit: ProjectArchive.maximumThumbnailBytes) : nil,
                        bytes: Int64((try? root.appendingPathComponent(document.fileName).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        }.sorted { $0.document.createdAt > $1.document.createdAt }
        return Listing(items: items, issues: issues)
    }

    func rename(_ id: UUID, title: String) throws {
        var document = try readDocument(id)
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines); document.modifiedAt = .now; document.revision += 1
        try save(document)
    }
    func moveToTrash(_ id: UUID) throws {
        guard !active.contains(id) else { throw ProjectError.staleRevision }
        var document = try readDocument(id)
        document.trashedAt = .now; document.revision += 1; document.modifiedAt = .now
        try save(document)
    }
    func restoreFromTrash(_ id: UUID) throws {
        var document = try readDocument(id)
        guard document.trashedAt != nil else { throw ProjectError.invalidDocument }
        document.trashedAt = nil; document.revision += 1; document.modifiedAt = .now
        try save(document)
    }
    func permanentlyDelete(_ id: UUID) throws {
        let document = try readDocument(id)
        guard document.trashedAt != nil, !active.contains(id) else { throw ProjectError.invalidDocument }
        // Keep the trash sidecar until media and cache removal succeeds. A crash
        // therefore leaves a deletable trash entry, never an adopted legacy movie.
        for url in [root.appendingPathComponent(document.fileName), thumbnailURL(id)] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.removeItem(at: recordURL(id))
    }
    func removeImported(_ ids: [UUID]) throws {
        for id in ids { try moveToTrash(id); try permanentlyDelete(id) }
    }
    func document(_ id: UUID) throws -> VideoDocument { try readDocument(id) }
    func setTrim(_ id: UUID, trim: VideoTrim?, expectedRevision: Int) throws -> VideoDocument {
        var document = try readDocument(id)
        guard document.revision == expectedRevision else { throw ProjectError.staleRevision }
        _ = try movieURL(id)
        document.trim = try trim?.normalized(duration: document.duration ?? 0)
        document.revision += 1; document.modifiedAt = .now
        try save(document); return document
    }

    /// A frozen saved edit is exported; the movie and sidecar remain unchanged.
    func exportEdited(_ id: UUID, to target: URL, expectedRevision: Int? = nil,
                      beforePublish: @Sendable () async throws -> Void = {}) async throws {
        let document = try readDocument(id), source = try movieURL(id)
        if let expectedRevision, expectedRevision != document.revision { throw ProjectError.staleRevision }
        let canonicalTarget = target.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        guard canonicalTarget != canonicalRoot, !canonicalTarget.hasPrefix(canonicalRoot + "/") else {
            throw VideoEditError.originalTarget
        }
        try Task.checkCancellation()
        guard let trim = document.trim else { try export(source, to: target); return }
        _ = try trim.validated(duration: document.duration ?? 0)
        let replacement = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? FileManager.default.removeItem(at: replacement) }
        let temporary = replacement.appendingPathComponent("Video.mp4"), asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw VideoRecordingError.invalidMovie }
        session.timeRange = CMTimeRange(start: CMTime(seconds: trim.start, preferredTimescale: 60_000), end: CMTime(seconds: trim.end, preferredTimescale: 60_000))
        session.shouldOptimizeForNetworkUse = true
        // The SDK's async export already installs a cancellation handler and
        // keeps the session on this actor. A second handler would transfer it.
        try await session.export(to: temporary, as: .mp4, isolation: self)
        try Task.checkCancellation()
        let result = AVURLAsset(url: temporary), info = try await movieInfo(result)
        guard abs(info.duration - trim.duration) <= 2.0 / 30, info.size == document.pixelSize, info.audio == document.hasAudio else { throw VideoRecordingError.invalidMovie }
        if document.hasAudio {
            guard let track = try await result.loadTracks(withMediaType: .audio).first else { throw VideoRecordingError.missingAudio }
            let reader = try AVAssetReader(asset: result), output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(output); guard reader.startReading() else { throw VideoRecordingError.missingAudio }
            defer { reader.cancelReading() }
            guard let sample = output.copyNextSampleBuffer(), CMSampleBufferGetNumSamples(sample) > 0 else { throw VideoRecordingError.missingAudio }
        }
        try await beforePublish()
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: target) }
    }

    /// Exports the applied trim as a bounded animated GIF without modifying the source.
    func exportGIF(_ id: UUID, to target: URL, expectedRevision: Int? = nil,
                   options: VideoGIFOptions = .init(),
                   beforePublish: @Sendable () async throws -> Void = {}) async throws {
        let options = try options.validated()
        let document = try readDocument(id), source = try movieURL(id)
        if let expectedRevision, expectedRevision != document.revision { throw ProjectError.staleRevision }
        let canonicalTarget = target.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        guard canonicalTarget != canonicalRoot, !canonicalTarget.hasPrefix(canonicalRoot + "/") else { throw VideoEditError.originalTarget }
        let duration = document.duration ?? 0
        let trim = try (document.trim ?? .init(start: 0, end: duration)).validated(duration: duration)
        guard trim.duration <= options.maximumDuration + 0.0001 else { throw VideoRecordingError.gifDurationExceeded }
        let exportDuration = trim.duration
        let frameCount = max(1, Int(ceil(exportDuration * Double(options.framesPerSecond))))
        let replacement = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? FileManager.default.removeItem(at: replacement) }
        let temporary = replacement.appendingPathComponent("Video.gif")
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frameCount, nil) else { throw VideoRecordingError.invalidMovie }
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: options.maximumDimension, height: options.maximumDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frameProperties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(options.framesPerSecond)]]
        let loopProperties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, loopProperties as CFDictionary)
        for index in 0..<frameCount {
            try Task.checkCancellation()
            let seconds = trim.start + min(Double(index) / Double(options.framesPerSecond), max(0, exportDuration - 1.0 / Double(options.framesPerSecond)))
            let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let frameInterval = 1.0 / Double(options.framesPerSecond)
            // Encoded keyframes can be reported a single frame around the
            // requested timestamp; never allow a sample from a different trim
            // section to leak into the GIF.
            guard result.actualTime.seconds >= trim.start - frameInterval,
                  result.actualTime.seconds < trim.end + frameInterval else { throw VideoRecordingError.invalidMovie }
            CGImageDestinationAddImage(destination, result.image, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw VideoRecordingError.invalidMovie }
        try data.write(to: temporary, options: .atomic)
        try await beforePublish()
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: target) }
    }
    func movieURL(_ id: UUID) throws -> URL {
        let document = try readDocument(id)
        guard document.state == .finished, document.trashedAt == nil else { throw VideoRecordingError.invalidMovie }
        let url = root.appendingPathComponent(document.fileName); try requireRegularFile(url)
        return url
    }
    private func recordURL(_ id: UUID) -> URL { metadata.appendingPathComponent("\(id).json") }
    private func thumbnailURL(_ id: UUID) -> URL { metadata.appendingPathComponent("\(id).jpg") }
    private func readDocument(_ id: UUID) throws -> VideoDocument {
        let document = try read(recordURL(id))
        guard document.id == id else { throw ProjectError.invalidDocument }
        return document
    }
    private func read(_ url: URL) throws -> VideoDocument {
        return try JSONDecoder().decode(VideoDocument.self, from: ProjectArchive.readRegularFile(url, limit: 1_048_576)).validated()
    }
    private func save(_ document: VideoDocument) throws {
        _ = try document.validated()
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        guard data.count <= 1_048_576 else { throw ProjectError.invalidDocument }
        try data.write(to: recordURL(document.id), options: .atomic)
    }
    private func record(for url: URL) throws -> VideoDocument? {
        guard url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              url.lastPathComponent.hasPrefix("."), url.lastPathComponent.hasSuffix(".recording.mp4"),
              let id = UUID(uuidString: String(url.lastPathComponent.dropFirst().dropLast(".recording.mp4".count))) else { return nil }
        let document = try read(recordURL(id))
        guard document.id == id else { throw ProjectError.invalidDocument }
        return document
    }
    private func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ProjectError.invalidDocument }
    }
    private func movieInfo(_ asset: AVURLAsset) async throws -> (duration: Double, size: PixelSize, audio: Bool) {
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0, let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoRecordingError.invalidMovie }
        let size = try await track.load(.naturalSize)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 32768, size.height <= 32768,
              let pixels = PixelSize(width: Int(size.width), height: Int(size.height)) else { throw VideoRecordingError.invalidMovie }
        let generator = AVAssetImageGenerator(asset: asset); generator.maximumSize = CGSize(width: 32, height: 32)
        let image = try await generator.image(at: .zero).image
        guard image.width > 0 else { throw VideoRecordingError.invalidMovie }
        return (duration, pixels, !(try await asset.loadTracks(withMediaType: .audio)).isEmpty)
    }
    private func makeThumbnail(_ asset: AVURLAsset) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 512, height: 288); generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: .zero).image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw VideoRecordingError.invalidMovie }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw VideoRecordingError.invalidMovie }
        return data as Data
    }

    /// Explicit backup is the only metadata operation that copies large movies.
    /// A new directory is published atomically; existing destinations are preserved.
    func backup(to target: URL) async throws {
        let listing = try await list()
        guard listing.issues.isEmpty else { throw ProjectError.invalidDocument }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".\(UUID()).video-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stage) }
        var entries: [VideoBackup.Entry] = []
        guard active.isEmpty else { throw ProjectError.staleRevision }
        for item in listing.items {
            let source = root.appendingPathComponent(item.document.fileName)
            let present = FileManager.default.fileExists(atPath: source.path)
            guard present || item.document.state != .finished else { throw ProjectError.missingOriginal }
            var hash = ""
            if present {
                try requireRegularFile(source)
                let copy = stage.appendingPathComponent(item.document.fileName)
                try FileManager.default.copyItem(at: source, to: copy)
                hash = try checksum(source)
                guard try checksum(copy) == hash else { throw ProjectError.invalidDocument }
            }
            entries.append(.init(document: item.document, sha256: hash, hasFile: present))
        }
        let backup = try VideoBackup(entries: entries).validated()
        let manifest = try JSONEncoder().encode(backup)
        guard manifest.count <= 16_777_216 else { throw ProjectError.invalidDocument }
        try manifest.write(to: stage.appendingPathComponent("manifest.json"), options: .atomic)
        try FileManager.default.moveItem(at: stage, to: target)
    }
    func restore(from source: URL) async throws -> Int { try await restoreIDs(from: source).count }
    func restoreIDs(from source: URL) async throws -> [UUID] {
        let manifest = source.appendingPathComponent("manifest.json")
        let backup = try JSONDecoder().decode(VideoBackup.self, from: ProjectArchive.readRegularFile(manifest, limit: 16_777_216)).validated()
        // Validate every source before changing the library. No overwrite: restore
        // always creates new identities, including repeated imports.
        for entry in backup.entries where entry.hasFile != false {
            let url = source.appendingPathComponent(entry.document.fileName); try requireRegularFile(url)
            guard try checksum(url) == entry.sha256 else { throw ProjectError.invalidDocument }
            guard entry.document.state == .finished else { continue }
            let info = try await movieInfo(AVURLAsset(url: url))
            guard info.size == entry.document.pixelSize, abs(info.duration - (entry.document.duration ?? 0)) < 0.05,
                  info.audio == entry.document.hasAudio else { throw ProjectError.invalidDocument }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stage = root.appendingPathComponent(".\(UUID()).restore", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stage) }
        var documents: [VideoDocument] = []
        for entry in backup.entries {
            var document = entry.document; document.id = UUID()
            document.fileName = document.state == .finished ? "\(document.id).mp4" : ".\(document.id).recording.mp4"
            let copy = stage.appendingPathComponent(document.fileName)
            if entry.hasFile != false {
                try FileManager.default.copyItem(at: source.appendingPathComponent(entry.document.fileName), to: copy)
                guard try checksum(copy) == entry.sha256 else { throw ProjectError.invalidDocument }
            }
            documents.append(document)
        }
        var published: [URL] = []
        do {
            for document in documents {
                let target = root.appendingPathComponent(document.fileName)
                let staged = stage.appendingPathComponent(document.fileName)
                if FileManager.default.fileExists(atPath: staged.path) {
                    try FileManager.default.moveItem(at: staged, to: target); published.append(target)
                }
                try save(document); published.append(recordURL(document.id))
            }
        } catch {
            for url in published { try? FileManager.default.removeItem(at: url) }; throw error
        }
        for document in documents where document.state == .finished {
            if let data = try? await makeThumbnail(AVURLAsset(url: root.appendingPathComponent(document.fileName))) {
                try? data.write(to: thumbnailURL(document.id), options: .atomic)
            }
        }
        return documents.map(\.id)
    }
    private func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func export(_ source: URL, to target: URL) throws {
        try Task.checkCancellation()
        guard source.standardizedFileURL != target.standardizedFileURL else { return }
        // NSSavePanel grants access to this file, not arbitrary siblings. Foundation
        // supplies a replacement directory on the target volume for atomic export.
        let replacement = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: target, create: true)
        let temporary = replacement.appendingPathComponent("Video.mp4")
        defer { try? FileManager.default.removeItem(at: replacement) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: target) }
        // Keep the app-local original available if saving is retried or the app quits.
    }
}


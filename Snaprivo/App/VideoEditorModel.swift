import AppKit
import AVFoundation
import Observation
import SnagForgeDomain

enum VideoEditError: LocalizedError {
    case originalTarget
    var errorDescription: String? { String(localized: "Wähle ein Ziel außerhalb der Videobibliothek. Das Original bleibt unverändert.") }
}

@MainActor @Observable final class VideoEditorModel: Identifiable {
    @ObservationIgnored var requestFeature: @MainActor (ProFeature) -> Bool = { _ in true }
    @ObservationIgnored var hasProAccess: @MainActor () -> Bool = { true }
    let id: UUID
    private(set) var document: VideoDocument
    let files: VideoRecordingFiles
    let originalURL: URL
    @ObservationIgnored let player: AVPlayer
    private var draftStart: Double
    private var draftEnd: Double
    private(set) var presentation = VideoPresentation()
    private(set) var isPreparingPreview = false
    @ObservationIgnored private var previewGeneration = 0
    var start: Double {
        get { draftStart }
        set { draftStart = hasProAccess() ? newValue : document.effectiveTrim.start; updatePlaybackBounds() }
    }
    var end: Double {
        get { draftEnd }
        set { draftEnd = hasProAccess() ? newValue : document.effectiveTrim.end; updatePlaybackBounds() }
    }
    private(set) var position = 0.0
    private(set) var isPlaying = false
    private(set) var isSaving = false
    private(set) var isExporting = false
    private(set) var isExportingGIF = false
    var error: String?
    var notice: String?
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var saving: Task<Bool, Never>?
    @ObservationIgnored private var exporting: Task<Bool, Never>?
    @ObservationIgnored private var panel: NSSavePanel?
    @ObservationIgnored private var gifPanel: NSSavePanel?
    @ObservationIgnored private var playbackRevision = 0
    @ObservationIgnored private let onSave: @MainActor () async -> Void
    private struct Edit: Equatable { var trim: VideoTrim?; var presentation: VideoPresentation }
    private var history: [Edit]
    private var historyIndex = 0

    init(document: VideoDocument, url: URL, files: VideoRecordingFiles, onSave: @escaping @MainActor () async -> Void = {}) {
        id = document.id; self.document = document; self.files = files; self.onSave = onSave; originalURL = url
        draftStart = document.effectiveTrim.start; draftEnd = document.effectiveTrim.end
        presentation = document.presentation
        history = [Edit(trim: document.trim, presentation: document.presentation)]; player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.playbackMoved(time.seconds) }
        }
        updatePlaybackBounds(); seek(start)
    }
    var duration: Double { document.duration ?? 0 }
    var draft: VideoTrim { .init(start: start, end: end) }
    var isValid: Bool { (try? draft.validated(duration: duration)) != nil }
    var hasUnappliedChanges: Bool { draft != document.effectiveTrim || presentation != document.presentation }
    var isBusy: Bool { isSaving || isExporting }
    var canApply: Bool { isValid && hasUnappliedChanges && !isBusy }
    var canUndo: Bool { historyIndex > 0 && !hasUnappliedChanges && !isBusy }
    var canRedo: Bool { historyIndex + 1 < history.count && !hasUnappliedChanges && !isBusy }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        pausePlayback(); position = min(max(0, seconds), duration)
        player.seek(to: CMTime(seconds: position, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func playSelection() {
        startPlayback(from: start)
    }
    func togglePlayback() {
        if isPlaying { pausePlayback() }
        else {
            let lastFrame = end - min(1.0 / 30, duration)
            startPlayback(from: position >= start && position < lastFrame - 0.001 ? position : start)
        }
    }
    func pausePlayback() {
        playbackRevision += 1; player.pause(); isPlaying = false
    }
    private func startPlayback(from seconds: Double) {
        guard isValid, !isBusy else { return }
        pausePlayback(); position = seconds; isPlaying = true
        let selection = draft, revision = playbackRevision
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.playbackRevision == revision, self.observer != nil else { return }
                guard finished, self.draft == selection, !self.isBusy else { self.isPlaying = false; return }
                self.player.play()
            }
        }
    }
    func scrub(to seconds: Double) {
        guard isValid, !isBusy, seconds.isFinite else { return }
        seek(min(max(start, seconds), end))
    }
    func stepFrame(_ direction: Double) { scrub(to: position + direction / 30) }
    func moveStart(to seconds: Double) {
        guard seconds.isFinite, duration > 0, !isBusy, hasProAccess() else { return }
        start = min(max(0, seconds), max(0, end - min(1.0 / 30, duration))); seek(start)
    }
    func moveEnd(to seconds: Double) {
        guard seconds.isFinite, duration > 0, !isBusy, hasProAccess() else { return }
        end = max(min(duration, seconds), min(duration, start + min(1.0 / 30, duration)))
        seek(max(start, end - min(1.0 / 30, duration)))
    }
    func setStartFromPlayhead() { start = min(position, end - min(1.0 / 30, duration)) }
    func setEndFromPlayhead() { end = max(position, start + min(1.0 / 30, duration)) }
    func restoreOriginal() { start = 0; end = duration; seek(0) }
    func discardDraft() {
        start = document.effectiveTrim.start; end = document.effectiveTrim.end
        presentation = document.presentation; seek(start)
    }
    func setPresentation(_ value: VideoPresentation) {
        guard !isBusy, hasProAccess(), value.isValid,
              let size = document.pixelSize, value.geometry(for: size) != nil else { return }
        pausePlayback(); presentation = value
    }
    func updatePreviewComposition() async {
        previewGeneration += 1
        let generation = previewGeneration, style = presentation
        guard let item = player.currentItem, let size = document.pixelSize else { return }
        isPreparingPreview = true; pausePlayback()
        defer { if generation == previewGeneration { isPreparingPreview = false } }
        do {
            let composition = try await VideoComposition.make(asset: item.asset, size: size, presentation: style)
            guard !Task.isCancelled, generation == previewGeneration, player.currentItem === item, observer != nil else { return }
            // A paused AVPlayerLayer can retain its old decoded frame after merely
            // changing videoComposition. Publish a fully configured item so it requests
            // the styled frame even when the playhead has not moved.
            if composition == nil && item.videoComposition == nil { return }
            let updated = AVPlayerItem(asset: item.asset)
            updated.videoComposition = composition
            updated.seekingWaitsForVideoCompositionRendering = true
            updated.reversePlaybackEndTime = CMTime(seconds: start, preferredTimescale: 60_000)
            updated.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 60_000)
            player.replaceCurrentItem(with: updated)
            seek(position)
        } catch {
            if !Task.isCancelled, generation == previewGeneration { self.error = error.localizedDescription }
        }
    }
    private func updatePlaybackBounds() {
        pausePlayback()
        guard isValid, let item = player.currentItem else { return }
        item.reversePlaybackEndTime = CMTime(seconds: start, preferredTimescale: 60_000)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 60_000)
        if position < start || position >= end { seek(start) }
    }
    private func playbackMoved(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = seconds
        isPlaying = player.rate != 0
        if isValid && (seconds < start - 0.02 || seconds > end + 0.02) { seek(start) }
    }
    @discardableResult func apply() async -> Bool {
        guard canApply else { return !hasUnappliedChanges }
        do { return await commit(Edit(trim: try draft.normalized(duration: duration), presentation: presentation), historyDestination: nil) }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func undo() async -> Bool {
        guard canUndo else { return false }; return await commit(history[historyIndex - 1], historyDestination: historyIndex - 1)
    }
    @discardableResult func redo() async -> Bool {
        guard canRedo else { return false }; return await commit(history[historyIndex + 1], historyDestination: historyIndex + 1)
    }
    private func commit(_ edit: Edit, historyDestination: Int?) async -> Bool {
        guard requestFeature(.video) else { return false }
        guard !isBusy else { return false }
        isSaving = true; pausePlayback()
        let task = Task { [self] in
            do {
                let next = try await files.setEdit(id, trim: edit.trim, presentation: edit.presentation, expectedRevision: document.revision)
                document = next
                if let historyDestination { historyIndex = historyDestination }
                else { history.removeSubrange((historyIndex + 1)..<history.count); history.append(edit); historyIndex += 1 }
                discardDraft(); await onSave(); return true
            } catch { self.error = error.localizedDescription; return false }
        }
        saving = task; let result = await task.value; saving = nil; isSaving = false
        return result
    }
    func reload() async {
        guard !isBusy else { return }
        do {
            document = try await files.document(id); history = [Edit(trim: document.trim, presentation: document.presentation)]; historyIndex = 0
            discardDraft(); await onSave()
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func export(to target: URL) async -> Bool {
        guard !isBusy, !hasUnappliedChanges else { return false }
        isExporting = true; pausePlayback()
        let task = Task { [self] in
            do {
                try await files.exportEdited(id, to: target, expectedRevision: document.revision)
                notice = String(localized: "MP4 gespeichert. Das Original und dein Arbeitsstand bleiben erhalten.")
                return true
            } catch is CancellationError { return false }
            catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
                return false
            }
        }
        exporting = task; let result = await task.value; exporting = nil; isExporting = false
        return result
    }
    @discardableResult func exportGIF(to target: URL, options: VideoGIFOptions = .init()) async -> Bool {
        guard !isBusy, !hasUnappliedChanges else { return false }
        isExporting = true; isExportingGIF = true; pausePlayback()
        let task = Task { [self] in
            do {
                try await files.exportGIF(id, to: target, expectedRevision: document.revision, options: options)
                notice = String(localized: "GIF gespeichert. Das Original und dein Arbeitsstand bleiben erhalten.")
                return true
            } catch is CancellationError { return false }
            catch { if !Task.isCancelled { self.error = error.localizedDescription }; return false }
        }
        exporting = task; let result = await task.value; exporting = nil; isExporting = false; isExportingGIF = false
        return result
    }
    func chooseExport() {
        guard !isBusy, !hasUnappliedChanges, panel == nil else { return }
        let dialog = NSSavePanel(); dialog.allowedContentTypes = [.mpeg4Movie]
        dialog.nameFieldStringValue = "Snaprivo-Video.mp4"; panel = dialog
        dialog.begin { [weak self] response in
            guard let self else { return }; panel = nil
            guard response == .OK, let url = dialog.url else { return }
            Task {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                _ = await export(to: url)
            }
        }
    }
    func chooseGIFExport() {
        guard !isBusy, !hasUnappliedChanges, gifPanel == nil else { return }
        let dialog = NSSavePanel(); dialog.allowedContentTypes = [.gif]
        dialog.nameFieldStringValue = "Snaprivo-Video.gif"; gifPanel = dialog
        dialog.begin { [weak self] response in
            guard let self else { return }; gifPanel = nil
            guard response == .OK, let url = dialog.url else { return }
            Task {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                _ = await exportGIF(to: url)
            }
        }
    }
    /// The export action saves a valid draft before opening the destination chooser.
    func prepareExport() async -> Bool {
        guard isValid, !isBusy else { return false }
        return hasUnappliedChanges ? await apply() : true
    }
    func cancelExport() { exporting?.cancel() }
    func stopPreview() {
        pausePlayback(); panel?.cancel(nil); panel = nil; gifPanel?.cancel(nil); gifPanel = nil
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
    }
    func finishPendingWork() async -> Bool {
        panel?.cancel(nil); panel = nil; gifPanel?.cancel(nil); gifPanel = nil
        if let saving { _ = await saving.value }
        if let exporting { _ = await exporting.value }
        guard !hasUnappliedChanges else {
            error = String(localized: "Übernimm oder verwirf zuerst die Änderungen in der Videovorschau."); return false
        }
        pausePlayback(); return true
    }
}

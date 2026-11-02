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
    private(set) var isQuickPreview: Bool
    let files: VideoRecordingFiles
    let originalURL: URL
    @ObservationIgnored let player: AVPlayer
    private var draftStart: Double
    private var draftEnd: Double
    private(set) var presentation = VideoPresentation()
    private(set) var playback = VideoPlayback()
    @ObservationIgnored private var activePlayback = VideoPlayback()
    @ObservationIgnored private var activePresentation = VideoPresentation()
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
    @ObservationIgnored private var observerGeneration = 0
    @ObservationIgnored private var saving: Task<Bool, Never>?
    @ObservationIgnored private var exporting: Task<Bool, Never>?
    @ObservationIgnored private var panel: NSSavePanel?
    @ObservationIgnored private var gifPanel: NSSavePanel?
    @ObservationIgnored private var playbackRevision = 0
    @ObservationIgnored private let onSave: @MainActor () async -> Void
    struct PreviewSettings: Equatable { var presentation: VideoPresentation; var playback: VideoPlayback }
    var previewSettings: PreviewSettings { .init(presentation: presentation, playback: playback) }
    private struct Edit: Equatable { var trim: VideoTrim?; var presentation: VideoPresentation; var playback: VideoPlayback }
    private var history: [Edit]
    private var historyIndex = 0

    init(document: VideoDocument, url: URL, files: VideoRecordingFiles, quickPreview: Bool = false, onSave: @escaping @MainActor () async -> Void = {}) {
        id = document.id; self.document = document; self.files = files; self.onSave = onSave; originalURL = url
        isQuickPreview = quickPreview
        draftStart = document.effectiveTrim.start; draftEnd = document.effectiveTrim.end
        presentation = document.presentation
        playback = document.playback
        isPreparingPreview = !document.presentation.isIdentity || !document.playback.isIdentity
        history = [Edit(trim: document.trim, presentation: document.presentation, playback: document.playback)]; player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        observePlayback()
        updatePlaybackBounds(); seek(start)
    }
    private func observePlayback() {
        if let observer { player.removeTimeObserver(observer) }
        observerGeneration += 1
        let generation = observerGeneration
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.observerGeneration == generation else { return }
                self.playbackMoved(time.seconds)
            }
        }
    }
    var duration: Double { document.duration ?? 0 }
    var draft: VideoTrim { .init(start: start, end: end) }
    var isValid: Bool { (try? draft.validated(duration: duration)) != nil && (try? playback.validated(duration: duration, selection: draft)) != nil }
    var outputDuration: Double { max(0, playback.outputDuration(selection: draft, duration: duration)) }
    var isPreviewReady: Bool { !isPreparingPreview && observer != nil && activePlayback == playback && activePresentation == presentation }
    var hasUnappliedChanges: Bool { draft != document.effectiveTrim || presentation != document.presentation || playback != document.playback }
    var isBusy: Bool { isSaving || isExporting }
    var canApply: Bool { isValid && hasUnappliedChanges && !isBusy }
    var canUndo: Bool { historyIndex > 0 && !hasUnappliedChanges && !isBusy }
    var canRedo: Bool { historyIndex + 1 < history.count && !hasUnappliedChanges && !isBusy }
    func openEditor() {
        guard !isBusy else { return }
        pausePlayback(); isQuickPreview = false
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        pausePlayback(); position = min(max(0, seconds), duration)
        // Preserve source intent while an older player item is being replaced.
        guard !isPreparingPreview else { return }
        var output = activePlayback.outputTime(for: position, duration: duration)
        if !activePlayback.removed.isEmpty, isValid {
            let upper = activePlayback.outputTime(for: end, duration: duration)
            let lower = activePlayback.outputTime(for: start, duration: duration)
            output = min(max(lower, output), max(lower, upper - 1.0 / 60_000))
            position = activePlayback.sourceTime(for: output, duration: duration)
        }
        player.seek(to: CMTime(seconds: output, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
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
        guard isValid, !isBusy, isPreviewReady else { return }
        pausePlayback(); position = seconds; isPlaying = true
        let selection = draft, revision = playbackRevision
        let output = activePlayback.outputTime(for: seconds, duration: duration)
        player.seek(to: CMTime(seconds: output, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
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
    func restoreOriginal() {
        start = 0; end = duration
        var value = playback; value.removed = []; setPlayback(value)
        seek(0)
    }
    func discardDraft() {
        start = document.effectiveTrim.start; end = document.effectiveTrim.end
        if presentation != document.presentation || playback != document.playback { isPreparingPreview = true }
        presentation = document.presentation; playback = document.playback; seek(start)
    }
    func setPresentation(_ value: VideoPresentation) {
        guard !isBusy, hasProAccess(), value.isValid,
              let size = document.pixelSize, value.geometry(for: size) != nil else { return }
        guard value != presentation else { return }
        pausePlayback(); presentation = value; isPreparingPreview = true
    }
    @discardableResult func setPlayback(_ value: VideoPlayback) -> Bool {
        guard !isBusy, hasProAccess() else { return false }
        do {
            _ = try value.validated(duration: duration, selection: draft)
            guard let size = document.pixelSize, presentation.geometry(for: size) != nil else { throw ProjectError.invalidDocument }
            guard value != playback else { return true }
            pausePlayback(); playback = value; isPreparingPreview = true; return true
        } catch {
            self.error = String(localized: "Behalte mindestens ein Videobild. Zoomabschnitte dürfen sich nicht überschneiden.")
            return false
        }
    }
    @discardableResult func removeRange(_ range: VideoTrim) -> Bool {
        guard !isBusy, hasProAccess() else { return false }
        do { return setPlayback(try playback.removing(range, duration: duration)) }
        catch { self.error = String(localized: "Behalte mindestens ein Videobild. Zoomabschnitte dürfen sich nicht überschneiden."); return false }
    }
    func updatePreviewComposition() async {
        previewGeneration += 1
        let generation = previewGeneration, settings = previewSettings
        guard let item = player.currentItem, let size = document.pixelSize else { return }
        isPreparingPreview = true; pausePlayback()
        defer { if generation == previewGeneration { isPreparingPreview = false } }
        do {
            let edit = try await VideoEditComposition.make(source: AVURLAsset(url: originalURL), playback: settings.playback, duration: duration)
            let composition = try await VideoComposition.make(asset: edit.asset, size: size, presentation: settings.presentation,
                playback: settings.playback, originalDuration: duration)
            guard !Task.isCancelled, generation == previewGeneration, player.currentItem === item, observer != nil else { return }
            // A paused AVPlayerLayer can retain its old decoded frame after merely
            // changing videoComposition. Publish a fully configured item so it requests
            // the styled frame even when the playhead has not moved.
            if composition == nil && item.videoComposition == nil && activePlayback.isIdentity {
                activePresentation = settings.presentation
                isPreparingPreview = false; seek(position); return
            }
            let updated = AVPlayerItem(asset: edit.asset)
            updated.videoComposition = composition
            updated.audioMix = edit.audioMix; updated.audioTimePitchAlgorithm = .spectral
            updated.seekingWaitsForVideoCompositionRendering = true
            updated.reversePlaybackEndTime = CMTime(seconds: settings.playback.outputTime(for: start, duration: duration), preferredTimescale: 60_000)
            updated.forwardPlaybackEndTime = CMTime(seconds: settings.playback.outputTime(for: end, duration: duration), preferredTimescale: 60_000)
            activePlayback = settings.playback
            activePresentation = settings.presentation
            player.replaceCurrentItem(with: updated)
            observePlayback()
            isPreparingPreview = false
            seek(position)
        } catch {
            if !Task.isCancelled, generation == previewGeneration { self.error = error.localizedDescription }
        }
    }
    private func updatePlaybackBounds() {
        pausePlayback()
        guard isValid, let item = player.currentItem else { return }
        item.reversePlaybackEndTime = CMTime(seconds: activePlayback.outputTime(for: start, duration: duration), preferredTimescale: 60_000)
        item.forwardPlaybackEndTime = CMTime(seconds: activePlayback.outputTime(for: end, duration: duration), preferredTimescale: 60_000)
        if position < start || position >= end { seek(start) }
    }
    private func playbackMoved(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = activePlayback.sourceTime(for: seconds, duration: duration)
        isPlaying = player.rate != 0
        if isValid, !isPlaying, seconds >= activePlayback.outputTime(for: end, duration: duration) - 0.002 { position = end; return }
        if isValid && (position < start - 0.02 || position > end + 0.02) { seek(start) }
    }
    @discardableResult func apply() async -> Bool {
        guard canApply else { return !hasUnappliedChanges }
        do { return await commit(Edit(trim: try draft.normalized(duration: duration), presentation: presentation, playback: playback), historyDestination: nil) }
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
        let savedPosition = position
        let task = Task { [self] in
            do {
                let next = try await files.setEdit(id, trim: edit.trim, presentation: edit.presentation, playback: edit.playback, expectedRevision: document.revision)
                document = next
                if let historyDestination { historyIndex = historyDestination }
                else { history.removeSubrange((historyIndex + 1)..<history.count); history.append(edit); historyIndex += 1 }
                discardDraft()
                if historyDestination == nil { seek(min(max(savedPosition, start), end)) }
                await onSave(); return true
            } catch { self.error = error.localizedDescription; return false }
        }
        saving = task; let result = await task.value; saving = nil; isSaving = false
        return result
    }
    func reload() async {
        guard !isBusy else { return }
        do {
            document = try await files.document(id); history = [Edit(trim: document.trim, presentation: document.presentation, playback: document.playback)]; historyIndex = 0
            discardDraft(); await updatePreviewComposition(); await onSave()
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
        observerGeneration += 1
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

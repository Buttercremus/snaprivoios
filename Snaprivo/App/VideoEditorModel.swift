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
    @ObservationIgnored let player: AVPlayer
    private var draftStart: Double
    private var draftEnd: Double
    var start: Double {
        get { draftStart }
        set { draftStart = hasProAccess() ? newValue : document.effectiveTrim.start; updatePlaybackBounds() }
    }
    var end: Double {
        get { draftEnd }
        set { draftEnd = hasProAccess() ? newValue : document.effectiveTrim.end; updatePlaybackBounds() }
    }
    private(set) var position = 0.0
    private(set) var isSaving = false
    private(set) var isExporting = false
    var error: String?
    var notice: String?
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var saving: Task<Bool, Never>?
    @ObservationIgnored private var exporting: Task<Bool, Never>?
    @ObservationIgnored private var panel: NSSavePanel?
    @ObservationIgnored private let onSave: @MainActor () async -> Void
    private var history: [VideoTrim?]
    private var historyIndex = 0

    init(document: VideoDocument, url: URL, files: VideoRecordingFiles, onSave: @escaping @MainActor () async -> Void = {}) {
        id = document.id; self.document = document; self.files = files; self.onSave = onSave
        draftStart = document.effectiveTrim.start; draftEnd = document.effectiveTrim.end
        history = [document.trim]; player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.playbackMoved(time.seconds) }
        }
        updatePlaybackBounds(); seek(start)
    }
    var duration: Double { document.duration ?? 0 }
    var draft: VideoTrim { .init(start: start, end: end) }
    var isValid: Bool { (try? draft.validated(duration: duration)) != nil }
    var hasUnappliedChanges: Bool { draft != document.effectiveTrim }
    var isBusy: Bool { isSaving || isExporting }
    var canApply: Bool { isValid && hasUnappliedChanges && !isBusy }
    var canUndo: Bool { historyIndex > 0 && !hasUnappliedChanges && !isBusy }
    var canRedo: Bool { historyIndex + 1 < history.count && !hasUnappliedChanges && !isBusy }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        player.pause()
        player.seek(to: CMTime(seconds: min(max(0, seconds), duration), preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func playSelection() {
        guard isValid, !isBusy else { return }
        let selection = draft
        player.seek(to: CMTime(seconds: start, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard finished, let self, self.observer != nil, self.draft == selection, !self.isBusy else { return }
                self.player.play()
            }
        }
    }
    func setStartFromPlayhead() { start = min(position, end - min(1.0 / 30, duration)) }
    func setEndFromPlayhead() { end = max(position, start + min(1.0 / 30, duration)) }
    func restoreOriginal() { start = 0; end = duration; seek(0) }
    func discardDraft() { start = document.effectiveTrim.start; end = document.effectiveTrim.end; seek(start) }
    private func updatePlaybackBounds() {
        guard isValid, let item = player.currentItem else { player.pause(); return }
        item.reversePlaybackEndTime = CMTime(seconds: start, preferredTimescale: 60_000)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 60_000)
        if position < start || position >= end { seek(start) }
    }
    private func playbackMoved(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = seconds
        if isValid && (seconds < start - 0.02 || seconds > end + 0.02) { seek(start) }
    }
    @discardableResult func apply() async -> Bool {
        guard canApply else { return !hasUnappliedChanges }
        do { return await commit(try draft.normalized(duration: duration), historyDestination: nil) }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func undo() async -> Bool {
        guard canUndo else { return false }; return await commit(history[historyIndex - 1], historyDestination: historyIndex - 1)
    }
    @discardableResult func redo() async -> Bool {
        guard canRedo else { return false }; return await commit(history[historyIndex + 1], historyDestination: historyIndex + 1)
    }
    private func commit(_ trim: VideoTrim?, historyDestination: Int?) async -> Bool {
        guard requestFeature(.video) else { return false }
        guard !isBusy else { return false }
        isSaving = true; player.pause()
        let task = Task { [self] in
            do {
                let next = try await files.setTrim(id, trim: trim, expectedRevision: document.revision)
                document = next
                if let historyDestination { historyIndex = historyDestination }
                else { history.removeSubrange((historyIndex + 1)..<history.count); history.append(trim); historyIndex += 1 }
                discardDraft(); await onSave(); return true
            } catch { self.error = error.localizedDescription; return false }
        }
        saving = task; let result = await task.value; saving = nil; isSaving = false
        return result
    }
    func reload() async {
        guard !isBusy else { return }
        do {
            document = try await files.document(id); history = [document.trim]; historyIndex = 0
            discardDraft(); await onSave()
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func export(to target: URL) async -> Bool {
        guard !isBusy, !hasUnappliedChanges else { return false }
        isExporting = true; player.pause()
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
    func cancelExport() { exporting?.cancel() }
    func stopPreview() {
        player.pause(); panel?.cancel(nil); panel = nil
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
    }
    func finishPendingWork() async -> Bool {
        panel?.cancel(nil); panel = nil
        if let saving { _ = await saving.value }
        if let exporting { _ = await exporting.value }
        guard !hasUnappliedChanges else {
            error = String(localized: "Übernimm oder verwirf zuerst die Änderungen in der Videovorschau."); return false
        }
        player.pause(); return true
    }
}

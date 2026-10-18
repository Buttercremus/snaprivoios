import SwiftUI
import AVKit

struct VideoEditorView: View {
    @Bindable var model: VideoEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDiscard = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.document.title).font(.title2.bold()).lineLimit(1)
                Spacer()
                Button(String(localized: "Schließen")) {
                    if model.hasUnappliedChanges { confirmsDiscard = true } else { dismiss() }
                }.disabled(model.isBusy).keyboardShortcut(.cancelAction)
            }
            NativeVideoPreview(player: model.player).frame(minHeight: 220, maxHeight: .infinity)
                .accessibilityIdentifier("video.editor.player")
            HStack {
                Button(String(localized: "Auswahl abspielen"), systemImage: "play.fill") { model.playSelection() }
                    .disabled(!model.isValid || model.isBusy).accessibilityIdentifier("video.editor.play")
                Text(String(localized: "Original: \(model.duration.formatted(.number.precision(.fractionLength(3)))) s"))
                Spacer()
                Text(String(localized: "Auswahl: \(max(0, model.end - model.start).formatted(.number.precision(.fractionLength(3)))) s"))
            }.font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            trimRow(start: true)
            trimRow(start: false)
            if !model.hasProAccess() {
                Button(String(localized: "Video bearbeiten · Pro"), systemImage: "lock") { _ = model.requestFeature(.video) }
            }
            if !model.isValid { Text(String(localized: "Start und Ende müssen innerhalb des Originals liegen. Behalte mindestens ein Videobild.")) .font(.caption).foregroundStyle(.red) }
            HStack {
                Button(String(localized: "Ganzes Original")) { if model.requestFeature(.video) { model.restoreOriginal() } }
                Button(String(localized: "Rückgängig")) { Task { await model.undo() } }
                    .disabled(!model.canUndo)
                Button(String(localized: "Wiederholen")) { Task { await model.redo() } }
                    .disabled(!model.canRedo)
                Spacer()
                Text(model.hasUnappliedChanges ? String(localized: "Noch nicht übernommen") : String(localized: "Gesichert"))
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(model.isBusy)
            Divider()
            if model.isExporting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "MP4 wird exportiert …"))
                    Spacer()
                    Button(String(localized: "Export abbrechen")) { model.cancelExport() }
                }
            } else {
                HStack {
                    Text(String(localized: "Trimmen verändert das Original nicht. Der MP4-Export verwendet die gespeicherte Auswahl."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Übernehmen")) { Task { await model.apply() } }
                        .disabled(!model.canApply).accessibilityIdentifier("video.editor.apply")
                    Button(String(localized: "MP4 speichern …")) { model.chooseExport() }
                        .buttonStyle(.glassProminent).disabled(model.isBusy || model.hasUnappliedChanges)
                        .accessibilityIdentifier("video.editor.export")
                }
            }
        }.padding(20).frame(minWidth: 720, idealWidth: 840, minHeight: 580, idealHeight: 640)
        .interactiveDismissDisabled(model.isBusy || model.hasUnappliedChanges)
        .onDisappear { model.stopPreview() }
        .alert(String(localized: "Änderungen verwerfen?"), isPresented: $confirmsDiscard) {
            Button(String(localized: "Verwerfen"), role: .destructive) { model.discardDraft(); dismiss() }
            Button(String(localized: "Abbrechen"), role: .cancel) { }
        } message: { Text(String(localized: "Die noch nicht übernommene Auswahl wird verworfen. Dein gespeicherter Arbeitsstand bleibt erhalten.")) }
        .alert(String(localized: "Videoaktion fehlgeschlagen"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            Button(String(localized: "Gesicherten Stand neu laden")) { model.error = nil; Task { await model.reload() } }
        } message: { Text(model.error ?? "") }
        .alert(String(localized: "Dateiaktion abgeschlossen"), isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }
    private func trimRow(start isStart: Bool) -> some View {
        let value = isStart ? $model.start : $model.end
        return HStack(spacing: 12) {
            Text(isStart ? String(localized: "Start (s)") : String(localized: "Ende (s)")).frame(width: 64, alignment: .leading)
            TextField(isStart ? String(localized: "Start (s)") : String(localized: "Ende (s)"), value: value, format: .number.precision(.fractionLength(3)))
                .textFieldStyle(.roundedBorder).frame(width: 100)
                .accessibilityIdentifier(isStart ? "video.editor.start" : "video.editor.end")
            Slider(value: Binding(get: { min(max(value.wrappedValue, 0), model.duration) }, set: { value.wrappedValue = $0 }), in: 0...max(model.duration, 0.001))
                .accessibilityLabel(isStart ? String(localized: "Trimmbeginn") : String(localized: "Trimmende"))
            Button(String(localized: "Hier setzen")) { if isStart { model.setStartFromPlayhead() } else { model.setEndFromPlayhead() } }
                .help(String(localized: "Aktuelle Abspielposition als Grenze setzen"))
                .accessibilityLabel(isStart ? String(localized: "Start an Abspielposition setzen") : String(localized: "Ende an Abspielposition setzen"))
        }.disabled(model.isBusy || !model.hasProAccess())
    }
}

private struct NativeVideoPreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .inline; view.player = player
        view.videoGravity = .resizeAspect; view.showsFrameSteppingButtons = true
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}

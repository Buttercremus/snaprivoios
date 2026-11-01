import SwiftUI
import AVKit

struct VideoEditorView: View {
    @Bindable var model: VideoEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(spacing: 16) {
            header
            NativeVideoPreview(player: model.player)
                .frame(minHeight: 200, idealHeight: 320, maxHeight: .infinity)
                .background(.black).clipShape(.rect(cornerRadius: 8))
                .accessibilityIdentifier("video.editor.player")
            transport
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(String(localized: "Schnittbereich"), systemImage: "scissors").font(.callout.weight(.semibold))
                    Spacer()
                    Button(String(localized: "Zurücksetzen")) { if model.requestFeature(.video) { model.restoreOriginal() } }
                        .disabled(model.isBusy || (model.start == 0 && model.end == model.duration))
                        .help(String(localized: "Gesamtes Video verwenden"))
                        .accessibilityIdentifier("video.editor.reset")
                }
                VideoTrimTimeline(model: model)
                HStack(spacing: 24) {
                    trimField(start: true)
                    Spacer(minLength: 8)
                    trimField(start: false)
                }
                if !model.hasProAccess() {
                    Button(String(localized: "Video bearbeiten · Pro"), systemImage: "lock") { _ = model.requestFeature(.video) }
                }
                if !model.isValid {
                    Text(String(localized: "Start und Ende müssen innerhalb des Originals liegen. Behalte mindestens ein Videobild."))
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Divider()
            footer
        }.padding(20).frame(minWidth: 720, idealWidth: 860, minHeight: 600, idealHeight: 680)
        .interactiveDismissDisabled(model.isBusy || model.hasUnappliedChanges)
        .onDisappear { model.stopPreview() }
        .alert(String(localized: "Schnitt vor dem Schließen sichern?"), isPresented: $confirmsDiscard) {
            Button(String(localized: "Schnitt sichern")) { Task { if await model.apply() { dismiss() } } }
                .disabled(!model.canApply)
            Button(String(localized: "Verwerfen"), role: .destructive) { model.discardDraft(); dismiss() }
            Button(String(localized: "Abbrechen"), role: .cancel) { }
        } message: { Text(String(localized: "Deine Änderungen am Schnitt sind noch nicht gesichert.")) }
        .alert(String(localized: "Videoaktion fehlgeschlagen"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            Button(String(localized: "Gesicherten Stand neu laden")) { model.error = nil; Task { await model.reload() } }
        } message: { Text(model.error ?? "") }
        .alert(String(localized: "Dateiaktion abgeschlossen"), isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Video kürzen")).font(.title3.weight(.semibold))
                Text(model.document.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { Task { await model.undo() } } label: {
                    Label(String(localized: "Rückgängig"), systemImage: "arrow.uturn.backward")
                        .foregroundStyle(model.canUndo ? Color.primary : Color(nsColor: .disabledControlTextColor))
                }
                    .disabled(!model.canUndo).help(String(localized: "Rückgängig (⌘Z)"))
                Button { Task { await model.redo() } } label: {
                    Label(String(localized: "Wiederholen"), systemImage: "arrow.uturn.forward")
                        .foregroundStyle(model.canRedo ? Color.primary : Color(nsColor: .disabledControlTextColor))
                }
                    .disabled(!model.canRedo).help(String(localized: "Wiederholen (⇧⌘Z)"))
            }.labelStyle(.iconOnly).buttonStyle(.glass)
            Button {
                model.pausePlayback()
                if model.hasUnappliedChanges { confirmsDiscard = true } else { dismiss() }
            } label: {
                Text(String(localized: "Schließen"))
                    .foregroundStyle(model.isBusy ? Color(nsColor: .disabledControlTextColor) : Color.primary)
            }.disabled(model.isBusy).keyboardShortcut(.cancelAction).buttonStyle(.glass)
        }
    }
    private var transport: some View {
        HStack(spacing: 12) {
            Button(model.isPlaying ? String(localized: "Pause") : String(localized: "Abspielen"),
                   systemImage: model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlayback() }
                .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.isValid || model.isBusy).accessibilityIdentifier("video.editor.play")
            HStack(spacing: 4) {
                Button(String(localized: "Ein Videobild zurück"), systemImage: "backward.frame") { model.stepFrame(-1) }
                    .help(String(localized: "Ein Videobild zurück"))
                Button(String(localized: "Ein Videobild vor"), systemImage: "forward.frame") { model.stepFrame(1) }
                    .help(String(localized: "Ein Videobild vor"))
            }.labelStyle(.iconOnly).buttonStyle(.glass).disabled(!model.isValid || model.isBusy)
            Text(verbatim: "\(VideoTimeText.clock(model.position)) / \(VideoTimeText.clock(model.duration))")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Abspielposition"))
                .accessibilityValue(VideoTimeText.clock(model.position))
                .accessibilityIdentifier("video.editor.position")
            Spacer()
            Text(VideoTimeText.selection(max(0, model.end - model.start)))
                .font(.callout.monospacedDigit().weight(.medium))
                .accessibilityIdentifier("video.editor.selectionDuration")
        }.accessibilityElement(children: .contain)
    }
    private func trimField(start isStart: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isStart ? String(localized: "Beginn") : String(localized: "Ende"))
                .font(.callout).foregroundStyle(.secondary)
            VideoSecondsField(value: isStart ? model.start : model.end,
                              label: isStart ? String(localized: "Beginn in Sekunden") : String(localized: "Ende in Sekunden"),
                              identifier: isStart ? "video.editor.start" : "video.editor.end") { value in
                if isStart { model.moveStart(to: value); return model.start }
                model.moveEnd(to: value); return model.end
            }.frame(width: 88, height: 24)
            Text(verbatim: "s").font(.callout).foregroundStyle(.secondary)
            Button(isStart ? String(localized: "Start an Abspielposition setzen") : String(localized: "Ende an Abspielposition setzen"),
                   systemImage: isStart ? "arrow.left.to.line" : "arrow.right.to.line") {
                if isStart { model.setStartFromPlayhead() } else { model.setEndFromPlayhead() }
            }.labelStyle(.iconOnly).buttonStyle(.glass)
                .help(isStart ? String(localized: "Start an Abspielposition setzen") : String(localized: "Ende an Abspielposition setzen"))
        }.disabled(model.isBusy || !model.hasProAccess())
    }
    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(model.hasUnappliedChanges ? String(localized: "Ungesicherter Schnitt") : String(localized: "Gesichert"),
                      systemImage: model.hasUnappliedChanges ? "circle.dotted" : "checkmark.circle")
                    .font(.callout)
                Text(String(localized: "Das Original bleibt erhalten."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isExporting {
                ProgressView().controlSize(.small)
                Text(model.isExportingGIF ? String(localized: "GIF wird exportiert …") : String(localized: "MP4 wird exportiert …")).font(.callout)
                Button(String(localized: "Export abbrechen")) { model.cancelExport() }.buttonStyle(.glass)
            } else {
                if model.isSaving { ProgressView().controlSize(.small) }
                Button(String(localized: "Schnitt sichern")) { Task { await model.apply() } }
                    .buttonStyle(.glass).disabled(!model.canApply).accessibilityIdentifier("video.editor.apply")
                Button(String(localized: "MP4 exportieren …")) {
                    Task { if await model.prepareExport() { model.chooseExport() } }
                }.buttonStyle(.glassProminent).disabled(model.isBusy || !model.isValid)
                    .help(String(localized: "Sichert den Schnitt und exportiert die Auswahl als MP4."))
                    .accessibilityIdentifier("video.editor.export")
                Button(String(localized: "GIF exportieren …"), systemImage: "photo.on.rectangle.angled") {
                    Task { if await model.prepareExport() { model.chooseGIFExport() } }
                }.buttonStyle(.glass).disabled(model.isBusy || !model.isValid)
                    .help(String(localized: "Animiertes GIF · 12 fps · maximal 720 px · maximal 15 Sekunden."))
                    .accessibilityIdentifier("video.editor.gifExport")
            }
        }
    }
}

private struct NativeVideoPreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .none; view.player = player
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}

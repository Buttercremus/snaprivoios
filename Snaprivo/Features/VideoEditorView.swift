import SwiftUI
import AVKit
import SnagForgeDomain

struct VideoEditorView: View {
    @Bindable var model: VideoEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(spacing: 16) {
            header
            HStack(spacing: 16) {
                NativeVideoPreview(player: model.player)
                    .frame(minWidth: 340, minHeight: 200, idealHeight: 360, maxHeight: .infinity)
                    .background(.black).clipShape(.rect(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if model.isPreparingPreview { ProgressView().controlSize(.small).padding(12) }
                    }
                    .accessibilityIdentifier("video.editor.player")
                Divider()
                ScrollView { VideoPresentationOptions(model: model).padding(.trailing, 4) }
                    .frame(width: 224)
            }
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
        }.padding(20).frame(minWidth: 760, idealWidth: 1040, minHeight: 640, idealHeight: 760)
        .task(id: model.presentation) { await model.updatePreviewComposition() }
        .interactiveDismissDisabled(model.isBusy || model.hasUnappliedChanges)
        .onDisappear { model.stopPreview() }
        .alert(String(localized: "Änderungen vor dem Schließen sichern?"), isPresented: $confirmsDiscard) {
            Button(String(localized: "Änderungen sichern")) { Task { if await model.apply() { dismiss() } } }
                .disabled(!model.canApply)
            Button(String(localized: "Verwerfen"), role: .destructive) { model.discardDraft(); dismiss() }
            Button(String(localized: "Abbrechen"), role: .cancel) { }
        } message: { Text(String(localized: "Deine Änderungen am Video sind noch nicht gesichert.")) }
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
                Text(String(localized: "Video bearbeiten")).font(.title3.weight(.semibold))
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
            Button {
                withAnimation(EditorMotion.panel(reduceMotion: reduceMotion)) { model.togglePlayback() }
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 20)
            }
                .accessibilityLabel(model.isPlaying ? String(localized: "Pause") : String(localized: "Abspielen"))
                .help(model.isPlaying ? String(localized: "Pause") : String(localized: "Abspielen"))
                .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.isValid || model.isBusy || model.isPreparingPreview).accessibilityIdentifier("video.editor.play")
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
                Label(model.hasUnappliedChanges ? String(localized: "Ungesicherte Änderungen") : String(localized: "Gesichert"),
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
                Button(String(localized: "Änderungen sichern")) { Task { await model.apply() } }
                    .buttonStyle(.glass).disabled(!model.canApply).accessibilityIdentifier("video.editor.apply")
                Button(String(localized: "MP4 exportieren …")) {
                    Task { if await model.prepareExport() { model.chooseExport() } }
                }.buttonStyle(.glassProminent).disabled(model.isBusy || !model.isValid)
                    .help(String(localized: "Sichert die Änderungen und exportiert die Auswahl mit Gestaltung als MP4."))
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

private struct VideoPresentationOptions: View {
    @Bindable var model: VideoEditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(String(localized: "Gestaltung"), systemImage: "paintpalette").font(.headline)
                Spacer()
                Button { model.setPresentation(VideoPresentation()) } label: { Image(systemName: "arrow.counterclockwise") }
                    .help(String(localized: "Gestaltung zurücksetzen")).disabled(model.presentation.isIdentity)
            }
            Picker(String(localized: "Hintergrund"), selection: backdrop) {
                Text(String(localized: "Keiner")).tag(VideoPresentation.Backdrop.none)
                Text(String(localized: "Farbe")).tag(VideoPresentation.Backdrop.solid)
                Text(String(localized: "Verlauf")).tag(VideoPresentation.Backdrop.gradient)
            }.accessibilityIdentifier("video.presentation.background")
            if model.presentation.backdrop != .none {
                ColorPicker(String(localized: "Farbe"), selection: color(\.color), supportsOpacity: false)
                if model.presentation.backdrop == .gradient {
                    ColorPicker(String(localized: "Zweite Farbe"), selection: color(\.secondColor), supportsOpacity: false)
                }
            }
            Picker(String(localized: "Seitenverhältnis"), selection: binding(\.aspectRatio)) {
                Text(String(localized: "Original")).tag(PresentationAspectRatio.natural)
                Text(verbatim: "16:9").tag(PresentationAspectRatio.wide)
                Text(verbatim: "9:16").tag(PresentationAspectRatio.portrait)
                Text(verbatim: "1:1").tag(PresentationAspectRatio.square)
                Text(verbatim: "4:3").tag(PresentationAspectRatio.landscape)
            }.accessibilityIdentifier("video.presentation.aspectRatio")
            Divider()
            slider(String(localized: "Außenabstand"), value: Binding(get: { Double(model.presentation.padding) }, set: {
                var style = model.presentation; style.padding = Int($0.rounded()); model.setPresentation(style)
            }), range: 0...240, unit: "px", id: "padding")
            slider(String(localized: "Eckenradius"), value: binding(\.cornerRadius), range: 0...120, unit: "px", id: "radius")
            slider(String(localized: "Schatten"), value: Binding(get: { model.presentation.shadow * 100 }, set: {
                var style = model.presentation; style.shadow = $0 / 100; model.setPresentation(style)
            }), range: 0...100, unit: "%", id: "shadow")
            if let size = model.document.pixelSize, let geometry = model.presentation.geometry(for: size) {
                Divider()
                Text(String(localized: "Ausgabe")).font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "\(geometry.outputSize.width) × \(geometry.outputSize.height) Pixel"))
                    .font(.caption.monospacedDigit()).accessibilityIdentifier("video.presentation.outputSize")
            }
        }.font(.callout).controlSize(.small)
            .disabled(model.isBusy || !model.hasProAccess())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("video.presentation")
    }
    private var backdrop: Binding<VideoPresentation.Backdrop> {
        Binding(get: { model.presentation.backdrop }, set: { value in
            var style = model.presentation
            if style.isIdentity && value != .none {
                style.padding = 32; style.cornerRadius = 12; style.shadow = 0.35
            }
            style.backdrop = value; model.setPresentation(style)
        })
    }
    private func binding<T>(_ key: WritableKeyPath<VideoPresentation, T>) -> Binding<T> {
        Binding(get: { model.presentation[keyPath: key] }, set: { value in
            var style = model.presentation; style[keyPath: key] = value; model.setPresentation(style)
        })
    }
    private func color(_ key: WritableKeyPath<VideoPresentation, EditorColor>) -> Binding<Color> {
        Binding(get: {
            let c = model.presentation[keyPath: key]
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
        }, set: { color in
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            var style = model.presentation
            style[keyPath: key] = EditorColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
            model.setPresentation(style)
        })
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, id: String) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(verbatim: "\(Int(value.wrappedValue)) \(unit)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(title)
                .accessibilityIdentifier("video.presentation.\(id)")
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
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        // Video metadata must not resize the surrounding editor when the item or aspect changes.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 640
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 360
        return CGSize(width: max(0, width), height: max(0, height))
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}

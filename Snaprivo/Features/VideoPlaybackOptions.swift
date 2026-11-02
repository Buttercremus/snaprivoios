import SwiftUI
import SnagForgeDomain

struct VideoPlaybackOptions: View {
    @Bindable var model: VideoEditorModel
    @State private var rangeEditor: VideoRangeDraft?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Tempo und Ton"), systemImage: "waveform").font(.headline)
            Picker(String(localized: "Tempo"), selection: Binding(get: { model.playback.speed }, set: { speed in
                var value = model.playback; value.speed = speed; model.setPlayback(value)
            })) {
                ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4], id: \.self) { speed in
                    Text(verbatim: speed.formatted(.number.precision(.fractionLength(0...2))) + "×").tag(speed)
                }
            }.accessibilityIdentifier("video.playback.speed")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "Lautstärke"))
                    Spacer()
                    Text(model.playback.volume, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { model.playback.volume }, set: { volume in
                    var value = model.playback; value.volume = volume; model.setPlayback(value)
                }), in: 0...1)
                .accessibilityLabel(String(localized: "Lautstärke"))
                .accessibilityIdentifier("video.playback.volume")
            }.disabled(!model.document.hasAudio)
            Text(String(localized: "Ausgabedauer: \(VideoTimeText.clock(model.outputDuration))"))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityIdentifier("video.playback.duration")
            Divider()
            HStack {
                Text(String(localized: "Abschnitte")).font(.headline)
                Spacer()
                Button(String(localized: "Bereich entfernen …"), systemImage: "scissors") { rangeEditor = draft(zoom: false) }
                    .labelStyle(.iconOnly).help(String(localized: "Bereich entfernen …"))
                    .accessibilityIdentifier("video.playback.removeRange")
            }
            ForEach(Array(model.playback.removed.enumerated()), id: \.offset) { index, range in
                HStack(spacing: 8) {
                    Text(rangeText(range)).font(.caption.monospacedDigit())
                    Spacer()
                    Button(String(localized: "Abschnitt wieder einsetzen"), systemImage: "arrow.uturn.backward") {
                        var value = model.playback; value.removed.remove(at: index); model.setPlayback(value)
                    }.labelStyle(.iconOnly).help(String(localized: "Abschnitt wieder einsetzen"))
                }
            }
            Divider()
            HStack {
                Text(String(localized: "Zoomabschnitte")).font(.headline)
                Spacer()
                Button(String(localized: "Zoom hinzufügen …"), systemImage: "plus") { rangeEditor = draft(zoom: true) }
                    .labelStyle(.iconOnly).help(String(localized: "Zoom hinzufügen …"))
                    .disabled(model.playback.zooms.count >= 32)
                    .accessibilityIdentifier("video.playback.addZoom")
            }
            ForEach(model.playback.zooms) { zoom in
                HStack(spacing: 8) {
                    Button { rangeEditor = .init(id: zoom.id, start: zoom.range.start, end: zoom.range.end, zoom: zoom) } label: {
                        Text(rangeText(zoom.range)).font(.caption.monospacedDigit())
                    }.buttonStyle(.link).accessibilityLabel(String(localized: "Zoom bearbeiten"))
                    Spacer()
                    Button(String(localized: "Zoom entfernen"), systemImage: "minus.circle") {
                        var value = model.playback; value.zooms.removeAll { $0.id == zoom.id }; model.setPlayback(value)
                    }.labelStyle(.iconOnly).help(String(localized: "Zoom entfernen"))
                }
            }
            Text(String(localized: "Zeitangaben und Zoompositionen beziehen sich auf das Original."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(model.isBusy || !model.hasProAccess())
        .popover(item: $rangeEditor) { value in VideoRangeEditor(model: model, value: value) { rangeEditor = nil } }
    }
    private func rangeText(_ range: VideoTrim) -> String { VideoTimeText.clock(range.start) + " – " + VideoTimeText.clock(range.end) }
    private func draft(zoom: Bool) -> VideoRangeDraft {
        let start = min(max(model.start, model.position), max(model.start, model.end - min(1.0 / 30, model.duration)))
        let end = min(model.end, start + 1)
        return .init(start: start, end: end, zoom: zoom ? .init(range: .init(start: start, end: end)) : nil)
    }
}

private struct VideoRangeDraft: Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var zoom: VideoZoom?
}

private struct VideoRangeEditor: View {
    let model: VideoEditorModel
    @State var value: VideoRangeDraft
    let close: () -> Void
    private var candidate: VideoPlayback? {
        let range = VideoTrim(start: value.start, end: value.end)
        guard (try? range.validated(duration: model.duration)) != nil else { return nil }
        var next = model.playback
        if var zoom = value.zoom {
            zoom.range = range
            next.zooms.removeAll { $0.id == zoom.id }; next.zooms.append(zoom)
            next.zooms.sort { $0.range.start < $1.range.start }
        } else {
            guard let removed = try? next.removing(range, duration: model.duration) else { return nil }
            next = removed
        }
        return try? next.validated(duration: model.duration, selection: model.draft)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(value.zoom == nil ? String(localized: "Abschnitt entfernen") : String(localized: "Zoom bearbeiten"))
                .font(.headline)
            HStack(spacing: 16) {
                timeField(start: true)
                timeField(start: false)
            }
            if value.zoom != nil {
                focusSlider(String(localized: "Vergrößerung"), key: \.scale, range: 1...3)
                focusSlider(String(localized: "Horizontal"), key: \.centerX, range: 0...1)
                focusSlider(String(localized: "Vertikal"), key: \.centerY, range: 0...1)
                Text(String(localized: "Nach dem Übernehmen zeigt die Vorschau die Abschnittsmitte."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if candidate == nil {
                Text(String(localized: "Behalte mindestens ein Videobild. Zoomabschnitte dürfen sich nicht überschneiden."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(String(localized: "Abbrechen"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Übernehmen")) {
                    if let candidate, model.setPlayback(candidate) {
                        if value.zoom != nil {
                            let begin = candidate.outputTime(for: value.start, duration: model.duration)
                            let end = candidate.outputTime(for: value.end, duration: model.duration)
                            model.scrub(to: candidate.sourceTime(for: (begin + end) / 2, duration: model.duration))
                        }
                        close()
                    }
                }.keyboardShortcut(.defaultAction).disabled(candidate == nil || model.isBusy || !model.hasProAccess())
                    .accessibilityIdentifier("video.range.apply")
            }
        }.padding(20).frame(width: 360)
    }
    private func timeField(start: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(start ? String(localized: "Beginn") : String(localized: "Ende")).font(.caption).foregroundStyle(.secondary)
            VideoSecondsField(value: start ? value.start : value.end,
                label: start ? String(localized: "Beginn in Sekunden") : String(localized: "Ende in Sekunden"),
                identifier: start ? "video.range.start" : "video.range.end") { seconds in
                let bounded = min(max(0, seconds), model.duration)
                if start { value.start = bounded } else { value.end = bounded }
                return bounded
            }.frame(width: 120, height: 24)
        }
    }
    private func focusSlider(_ title: String, key: WritableKeyPath<VideoZoom, Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(key == \VideoZoom.scale
                     ? (value.zoom?.scale ?? 1).formatted(.number.precision(.fractionLength(1))) + "×"
                     : (value.zoom?[keyPath: key] ?? 0.5).formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value.zoom?[keyPath: key] ?? range.lowerBound }, set: { value.zoom?[keyPath: key] = $0 }), in: range)
                .accessibilityLabel(title)
        }
    }
}

import SwiftUI
import AVFoundation

enum VideoTimeText {
    static func selection(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 0.05 { return String(localized: "Auswahl: 1 Videobild") }
        return String(localized: "Auswahl: \(clock(seconds))")
    }
    static func clock(_ seconds: Double, locale: Locale = .current) -> String {
        let tenths = Int((min(max(seconds.isFinite ? seconds : 0, 0), 31_536_000) * 10).rounded())
        let whole = tenths / 10, minutes = whole / 60, hours = whole / 3600
        let body = hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes % 60, whole % 60)
            : String(format: "%d:%02d", minutes, whole % 60)
        return body + (locale.decimalSeparator ?? ".") + String(tenths % 10)
    }
}

enum VideoTimelineZoom: Int, CaseIterable {
    case fit = 1, twice = 2, fourTimes = 4, eightTimes = 8
    var title: String { self == .fit ? String(localized: "Gesamt") : "\(rawValue)×" }
    func contentWidth(in viewport: CGFloat) -> CGFloat {
        guard viewport.isFinite, viewport > 32 else { return 32 }
        return (viewport - 32) * CGFloat(rawValue) + 32
    }
}

/// One scale for the selection, playhead, pointer and keyboard interactions.
struct VideoTimelineScale {
    let duration: Double
    let width: CGFloat
    func x(for seconds: Double) -> CGFloat {
        guard duration.isFinite, duration > 0, width.isFinite, width > 0, seconds.isFinite else { return 0 }
        return CGFloat(min(max(seconds / duration, 0), 1)) * width
    }
    func seconds(at x: CGFloat) -> Double {
        guard duration.isFinite, duration > 0, width.isFinite, width > 0, x.isFinite else { return 0 }
        return Double(min(max(x / width, 0), 1)) * duration
    }
}

enum VideoTimelineFrames {
    /// Bounded, transient thumbnails; decoding runs away from the main actor.
    nonisolated static func load(url: URL, duration: Double) async -> [CGImage] {
        guard duration.isFinite, duration > 0, !Task.isCancelled else { return [] }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 96)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let times = (0..<8).map { CMTime(seconds: duration * (Double($0) + 0.5) / 8, preferredTimescale: 600) }
        var frames: [(Double, CGImage)] = []
        for await result in generator.images(for: times) {
            guard !Task.isCancelled else { generator.cancelAllCGImageGeneration(); return [] }
            if case let .success(requested, image, _) = result { frames.append((requested.seconds, image)) }
        }
        return frames.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

struct VideoTrimTimeline: View {
    @Bindable var model: VideoEditorModel
    var zoom: VideoTimelineZoom = .fit
    @State private var frames: [CGImage] = []
    @State private var playheadDragOrigin: Double?
    private enum Control: Hashable { case playhead }
    @FocusState private var focused: Control?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { viewport in
                let scale = VideoTimelineScale(duration: model.duration, width: zoom.contentWidth(in: viewport.size.width) - 32)
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        VStack(spacing: 8) {
                            ruler(scale: scale).frame(width: scale.width).padding(.horizontal, 16)
                            track(scale: scale).frame(width: scale.width + 32, height: 64)
                        }.padding(.bottom, 12)
                    }
                    .onChange(of: zoom) { scroll.scrollTo("video.timeline.playhead", anchor: .center) }
                }
            }.frame(height: 100)
            Text(String(localized: "Ziehe die Griffe, um Anfang und Ende zu kürzen."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Videoschnitt"))
        .accessibilityIdentifier("video.editor.timeline")
        .task(id: model.id) { frames = await VideoTimelineFrames.load(url: model.originalURL, duration: model.duration) }
    }
    private func ruler(scale: VideoTimelineScale) -> some View {
        let intervals = zoom.rawValue * 2
        let labelWidth = min(90, scale.width)
        return ZStack(alignment: .topLeading) {
            ForEach(0...intervals, id: \.self) { tick in
                let seconds = model.duration * Double(tick) / Double(intervals)
                Text(VideoTimeText.clock(seconds))
                    .frame(width: labelWidth, alignment: tick == 0 ? .leading : tick == intervals ? .trailing : .center)
                    .position(x: min(max(scale.x(for: seconds), labelWidth / 2), scale.width - labelWidth / 2), y: 7)
            }
        }.frame(height: 14).font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityHidden(true)
    }
    private func track(scale: VideoTimelineScale) -> some View {
        let start = scale.x(for: model.start), end = scale.x(for: model.end)
        return ZStack(alignment: .topLeading) {
            filmstrip
                .frame(width: scale.width, height: 48)
                .clipShape(.rect(cornerRadius: 4))
                .overlay(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.6)).frame(width: start).allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.black.opacity(0.6)).frame(width: max(0, scale.width - end)).allowsHitTesting(false)
                }
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: max(0, end - start)).offset(x: start).allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { model.scrub(to: scale.seconds(at: $0.location.x)) })
                .offset(x: 16, y: 8)
                .accessibilityHidden(true)
            playhead(x: scale.x(for: model.position) + 16, scale: scale).id("video.timeline.playhead")
            trimHandle(.start, x: start + 10, scale: scale)
            trimHandle(.end, x: end + 22, scale: scale)
        }.coordinateSpace(name: "video.timeline")
    }

    private var filmstrip: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    Image(decorative: frame, scale: 1).resizable().scaledToFill()
                        .frame(width: proxy.size.width / CGFloat(max(frames.count, 1)), height: 48).clipped()
                }
            }
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private func trimHandle(_ edge: VideoTrimEdge, x: CGFloat, scale: VideoTimelineScale) -> some View {
        VideoTrimHandle(model: model, edge: edge, timelineWidth: scale.width)
        .frame(width: 24, height: 64).position(x: x, y: 32)
        .disabled(model.isBusy || !model.hasProAccess())
    }
    private func playhead(x: CGFloat, scale: VideoTimelineScale) -> some View {
        VStack(spacing: 0) {
            Button { focused = .playhead } label: {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10))
                    .frame(width: 24, height: 16).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .focusable().focused($focused, equals: .playhead).disabled(model.isBusy)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("video.timeline"))
                .onChanged { value in
                    focused = .playhead
                    if playheadDragOrigin == nil { playheadDragOrigin = model.position }
                    model.scrub(to: (playheadDragOrigin ?? 0) + Double(value.translation.width / max(scale.width, 1)) * model.duration)
                }.onEnded { _ in playheadDragOrigin = nil })
            .accessibilityLabel(String(localized: "Abspielposition"))
            .accessibilityValue(VideoTimeText.clock(model.position))
            .accessibilityIdentifier("video.editor.playhead")
            .accessibilityAdjustableAction { direction in model.stepFrame(direction == .increment ? 1 : -1) }
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { key in
                model.stepFrame(key.key == .leftArrow ? -1 : 1); return .handled
            }
            Rectangle().frame(width: 2, height: 48).allowsHitTesting(false)
        }.foregroundStyle(.primary).position(x: x, y: 32)
    }
}

import Foundation

/// All edit times refer to the immutable original, never a previously rendered movie.
public struct VideoPlayback: Codable, Equatable, Sendable {
    public var speed = 1.0
    public var volume = 1.0
    public var removed: [VideoTrim] = []
    public var zooms: [VideoZoom] = []
    public init() {}
    public var isIdentity: Bool { speed == 1 && volume == 1 && removed.isEmpty && zooms.isEmpty }

    public func validated(duration: Double, selection: VideoTrim? = nil) throws -> Self {
        guard duration.isFinite, duration > 0, duration <= 31_536_000, speed.isFinite, (0.25...4).contains(speed),
              volume.isFinite, (0...1).contains(volume), removed.count <= 64, zooms.count <= 32 else {
            throw ProjectError.invalidDocument
        }
        var end = 0.0
        for range in removed {
            _ = try range.validated(duration: duration)
            guard range.start >= end else { throw ProjectError.invalidDocument }
            end = range.end
        }
        end = 0
        guard Set(zooms.map(\.id)).count == zooms.count else { throw ProjectError.invalidDocument }
        for zoom in zooms {
            _ = try zoom.range.validated(duration: duration)
            guard zoom.range.start >= end, zoom.scale.isFinite, (1...3).contains(zoom.scale),
                  zoom.centerX.isFinite, zoom.centerY.isFinite,
                  (0...1).contains(zoom.centerX), (0...1).contains(zoom.centerY) else { throw ProjectError.invalidDocument }
            end = zoom.range.end
        }
        let selection = try (selection ?? .init(start: 0, end: duration)).validated(duration: duration)
        let remaining = keptRanges(duration: duration).reduce(0.0) {
            $0 + max(0, min($1.end, selection.end) - max($1.start, selection.start))
        }
        guard remaining >= min(1.0 / 30, selection.duration) - 0.000_001 else { throw ProjectError.invalidDocument }
        return self
    }

    public func keptRanges(duration: Double) -> [VideoTrim] {
        guard duration.isFinite, duration > 0 else { return [] }
        var ranges: [VideoTrim] = [], cursor = 0.0
        for cut in removed {
            if cut.start > cursor { ranges.append(.init(start: cursor, end: cut.start)) }
            cursor = cut.end
        }
        if cursor < duration { ranges.append(.init(start: cursor, end: duration)) }
        return ranges
    }
    /// Removed source positions collapse to the splice point.
    public func outputTime(for source: Double, duration: Double) -> Double {
        guard source.isFinite, speed.isFinite, speed > 0 else { return 0 }
        var time = 0.0
        for range in keptRanges(duration: duration) {
            if source < range.start { break }
            time += max(0, min(source, range.end) - range.start) / speed
            if source <= range.end { break }
        }
        return time
    }
    /// A splice chooses the next retained source frame. The final endpoint stays bounded.
    public func sourceTime(for output: Double, duration: Double) -> Double {
        guard output.isFinite, speed.isFinite, speed > 0 else { return 0 }
        let ranges = keptRanges(duration: duration)
        var time = max(0, output)
        for range in ranges {
            let length = range.duration / speed
            if time < length { return range.start + time * speed }
            time -= length
        }
        return ranges.last?.end ?? 0
    }
    public func outputDuration(selection: VideoTrim, duration: Double) -> Double {
        outputTime(for: selection.end, duration: duration) - outputTime(for: selection.start, duration: duration)
    }
    public func removing(_ range: VideoTrim, duration: Double) throws -> Self {
        _ = try range.validated(duration: duration)
        var copy = self, merged: [VideoTrim] = []
        for cut in (removed + [range]).sorted(by: { $0.start < $1.start }) {
            if let previous = merged.last, cut.start <= previous.end {
                merged[merged.count - 1] = .init(start: previous.start, end: max(previous.end, cut.end))
            } else { merged.append(cut) }
        }
        copy.removed = merged
        return try copy.validated(duration: duration)
    }
    public func focus(at sourceTime: Double) -> VideoZoom.Transform {
        guard sourceTime.isFinite, let zoom = zooms.first(where: { $0.range.start <= sourceTime && sourceTime <= $0.range.end }) else { return .identity }
        let ramp = min(0.25, zoom.range.duration / 3)
        guard ramp > 0 else { return .identity }
        let progress = min(1, max(0, min(sourceTime - zoom.range.start, zoom.range.end - sourceTime) / ramp))
        let eased = progress * progress * (3 - 2 * progress)
        return .init(scale: 1 + (zoom.scale - 1) * eased, centerX: zoom.centerX, centerY: zoom.centerY)
    }
}

public struct VideoZoom: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var range: VideoTrim
    public var scale: Double
    /// Normalized coordinates in the displayed original, from its top-left corner.
    public var centerX: Double
    public var centerY: Double
    public init(id: UUID = UUID(), range: VideoTrim, scale: Double = 2, centerX: Double = 0.5, centerY: Double = 0.5) {
        self.id = id; self.range = range; self.scale = scale; self.centerX = centerX; self.centerY = centerY
    }
    public struct Transform: Equatable, Sendable {
        public let scale: Double
        public let centerX: Double
        public let centerY: Double
        public static let identity = Self(scale: 1, centerX: 0.5, centerY: 0.5)
    }
}

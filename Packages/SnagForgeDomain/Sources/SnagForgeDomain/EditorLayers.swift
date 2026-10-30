import Foundation
import CoreGraphics

public enum EditorLayerMove: CaseIterable, Hashable, Sendable { case forward, backward, front, back }

/// Original-image filters form the lower stratum; vectors form the upper one.
/// Within each stratum, document order is back to front for both painting and picking.
public enum EditorLayers {
    private static func stratum(_ object: EditorObject) -> Int { object.kind == .blur ? 0 : object.kind == .spotlight ? 1 : object.kind == .redact ? 3 : 2 }
    public static func paintOrder(_ objects: [EditorObject]) -> [EditorObject] {
        objects.filter { $0.kind == .blur } + objects.filter { $0.kind == .spotlight }
            + objects.filter { $0.kind != .blur && $0.kind != .redact && $0.kind != .spotlight } + objects.filter { $0.kind == .redact }
    }
    public static func canMove(_ id: UUID, in objects: [EditorObject], direction: EditorLayerMove) -> Bool {
        guard let object = objects.first(where: { $0.id == id }) else { return false }
        let peers = objects.filter { stratum($0) == stratum(object) }
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return false }
        switch direction {
        case .forward, .front: return index < peers.count - 1
        case .backward, .back: return index > 0
        }
    }
    public static func moving(_ id: UUID, in objects: [EditorObject], direction: EditorLayerMove) -> [EditorObject] {
        guard canMove(id, in: objects, direction: direction), let object = objects.first(where: { $0.id == id }) else { return objects }
        var peers = objects.filter { stratum($0) == stratum(object) }
        let index = peers.firstIndex(where: { $0.id == id })!
        let target: Int = switch direction {
        case .forward: index + 1
        case .backward: index - 1
        case .front: peers.count - 1
        case .back: 0
        }
        peers.insert(peers.remove(at: index), at: target)
        var iterator = peers.makeIterator()
        return objects.map { stratum($0) == stratum(object) ? iterator.next()! : $0 }
    }
    /// Keep copies visible at crop edges. Oversized objects retain that axis unchanged.
    public static func duplicateOffset(bounds: CGRect, visible: CGRect, preferred: CGSize) -> CGSize {
        func offset(start: CGFloat, length: CGFloat, min: CGFloat, max: CGFloat, delta: CGFloat) -> CGFloat {
            guard [start, length, min, max, delta].allSatisfy(\.isFinite), length >= 0, length <= max - min else { return 0 }
            func clamped(_ value: CGFloat) -> CGFloat { Swift.min(max - length, Swift.max(min, value)) }
            let next = clamped(start + delta)
            return abs(next - start) > 0.001 ? next - start : clamped(start - delta) - start
        }
        return CGSize(width: offset(start: bounds.minX, length: bounds.width, min: visible.minX, max: visible.maxX, delta: preferred.width),
                      height: offset(start: bounds.minY, length: bounds.height, min: visible.minY, max: visible.maxY, delta: preferred.height))
    }
}

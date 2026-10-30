import CoreGraphics
import SnagForgeDomain

extension EditorModel {
    var canArrangeSelection: Bool {
        canActOnSelection && selectedIDs.count >= 2 && preview == nil && editingTextObject == nil &&
        !isSwitchingImage && !isShowingTextRecognition && !isShowingRedactionSuggestions && !isExportingPNG
    }

    func alignSelection(_ alignment: EditorArrangement.Alignment) {
        guard canArrangeSelection else { return }
        let ids = selectedIDs
        let selected = history.objects.filter { ids.contains($0.id) }
        let bounds = selected.map(EditorRenderer.bounds)
        guard !bounds.isEmpty else { return }
        let target: CGFloat
        switch alignment {
        case .left: target = bounds.map(\.minX).min()!
        case .center: target = (bounds.map(\.minX).min()! + bounds.map(\.maxX).max()!) / 2
        case .right: target = bounds.map(\.maxX).max()!
        case .top: target = bounds.map(\.minY).min()!
        case .middle: target = (bounds.map(\.minY).min()! + bounds.map(\.maxY).max()!) / 2
        case .bottom: target = bounds.map(\.maxY).max()!
        }
        var next = history.objects
        for (object, rect) in zip(selected, bounds) {
            let delta: CGSize
            switch alignment {
            case .left: delta = CGSize(width: target - rect.minX, height: 0)
            case .center: delta = CGSize(width: target - rect.midX, height: 0)
            case .right: delta = CGSize(width: target - rect.maxX, height: 0)
            case .top: delta = CGSize(width: 0, height: target - rect.minY)
            case .middle: delta = CGSize(width: 0, height: target - rect.midY)
            case .bottom: delta = CGSize(width: 0, height: target - rect.maxY)
            }
            if let index = next.firstIndex(where: { $0.id == object.id }) { next[index] = object.translated(by: delta) }
        }
        commit(next, expandingCanvas: true)
    }

    func distributeSelection(_ distribution: EditorArrangement.Distribution) {
        guard canArrangeSelection, selectedIDs.count >= 3 else { return }
        let ids = selectedIDs
        let selected = history.objects.filter { ids.contains($0.id) }
        let pairs = selected.map { ($0, EditorRenderer.bounds($0)) }.sorted {
            distribution == .horizontal ? ($0.1.minX, $0.0.id.uuidString) < ($1.1.minX, $1.0.id.uuidString) : ($0.1.minY, $0.0.id.uuidString) < ($1.1.minY, $1.0.id.uuidString)
        }
        guard let first = pairs.first else { return }
        let total = pairs.reduce(CGFloat(0)) { $0 + (distribution == .horizontal ? $1.1.width : $1.1.height) }
        let overallMax = pairs.map { distribution == .horizontal ? $0.1.maxX : $0.1.maxY }.max()!
        let span = overallMax - (distribution == .horizontal ? first.1.minX : first.1.minY)
        let gap = (span - total) / CGFloat(pairs.count - 1)
        guard gap.isFinite else { return }
        var cursor = distribution == .horizontal ? first.1.minX : first.1.minY
        var next = history.objects
        for (index, pair) in pairs.enumerated() {
            let rect = pair.1
            let delta = distribution == .horizontal ? CGSize(width: cursor - rect.minX, height: 0) : CGSize(width: 0, height: cursor - rect.minY)
            if let objectIndex = next.firstIndex(where: { $0.id == pair.0.id }) { next[objectIndex] = pair.0.translated(by: delta) }
            cursor += (distribution == .horizontal ? rect.width : rect.height) + (index == pairs.count - 1 ? 0 : gap)
        }
        commit(next, expandingCanvas: true)
    }

    func scaleSelection(width: CGFloat, height: CGFloat) {
        guard canArrangeSelection, width.isFinite, height.isFinite, width > 0, height > 0, width <= 32768, height <= 32768 else { return }
        let ids = selectedIDs
        let selected = history.objects.filter { ids.contains($0.id) }
        var source: CGRect?
        for object in selected {
            let rect = EditorRenderer.bounds(object)
            source = source.map { $0.union(rect) } ?? rect
        }
        guard let source, source.width > 0, source.height > 0 else { return }
        let target = CGRect(x: source.minX, y: source.minY, width: width, height: height)
        let next = history.objects.map { object in
            guard ids.contains(object.id) else { return object }
            var value = object
            if value.kind == .callout { value.calloutTip = EditorRenderer.calloutTip(value) }
            return EditorArrangement.scaled(object: value, from: source, to: target)
        }
        commit(next, expandingCanvas: true)
    }

    func snapSelectionDelta(for rect: CGRect, candidates: [CGRect], canvas: CGRect, tolerance: CGSize, allowsSnapping: Bool = true) -> EditorArrangement.SnapResult {
        guard allowsSnapping else { return .init() }
        return EditorArrangement.snap(rect: rect, candidates: candidates, canvas: canvas, tolerance: tolerance)
    }
}

import Foundation

public enum ScrollStitchError: LocalizedError, Equatable {
    case dimensions, unchanged, uncertain, fixedContent, moving, limit
    public var errorDescription: String? {
        switch self {
        case .dimensions: String(localized: "Der Aufnahmebereich wurde verändert oder ist zu groß. Bitte neu beginnen.", bundle: DomainLocalization.bundle)
        case .unchanged: String(localized: "Noch keine Scrollbewegung erkannt. Scrolle langsam nach unten.", bundle: DomainLocalization.bundle)
        case .uncertain: String(localized: "Der Übergang ist nicht eindeutig. Scrolle zurück und dann weniger weit nach unten. Mindestens ein Drittel des bisherigen Inhalts muss sichtbar bleiben.", bundle: DomainLocalization.bundle)
        case .fixedContent: String(localized: "Ein feststehender Kopf- oder Fußbereich stört den Übergang. Bitte neu beginnen und nur den scrollenden Inhalt auswählen.", bundle: DomainLocalization.bundle)
        case .moving: String(localized: "Der Inhalt bewegt sich noch. Scrolle langsamer oder warte kurz.", bundle: DomainLocalization.bundle)
        case .limit: String(localized: "Die Grenze von 20.000 Pixeln Höhe oder 40 Millionen Pixeln ist erreicht. Klicke auf Fertig, um das bisherige Bild zu übernehmen.", bundle: DomainLocalization.bundle)
        }
    }
}

/// Top-left-origin grayscale pixels, independent of capture/UI frameworks.
public struct ScrollFrame: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width >= 40, height >= 80, width <= 4096, height <= 4096,
              pixels.count == width * height else { throw ScrollStitchError.dimensions }
        self.width = width; self.height = height; self.pixels = pixels
    }
}

public enum ScrollStitcher {
    public static func validateSize(width: Int, height: Int, count: Int) throws {
        try validateOutputSize(width: width, height: height)
        guard count > 0, count <= 50 else { throw ScrollStitchError.limit }
    }
    /// Live sampling keeps only the latest frame and composed result. Its memory
    /// bound depends on output pixels, not the number of overlapping samples.
    public static func validateOutputSize(width: Int, height: Int) throws {
        guard width > 0, width <= 4096, height > 0, height <= 20_000,
              width * height <= 40_000_000 else { throw ScrollStitchError.limit }
    }
    public static func requireStable(_ a: ScrollFrame, _ b: ScrollFrame) throws {
        guard a.width == b.width, a.height == b.height else { throw ScrollStitchError.dimensions }
        guard difference(a, b, shift: 0) < 0.5 else { throw ScrollStitchError.moving }
    }
    /// Downward vertical motion with >= 30% overlap. Every vertical pixel is
    /// retained in analysis, including small movements during smooth scrolling.
    public static func displacement(from first: ScrollFrame, to next: ScrollFrame) throws -> Int {
        guard first.width == next.width, first.height == next.height else { throw ScrollStitchError.dimensions }
        if difference(first, next, shift: 0) < 0.5 { throw ScrollStitchError.unchanged }
        let a = try matchingFrame(first), b = try matchingFrame(next)
        let maximum = a.height * 7 / 10
        // Test every pixel displacement. Coarse shift strides miss sharp text and
        // arbitrary image patterns when the true displacement falls between samples.
        let integerRanked = (1...maximum).map {
            ($0, difference(a, b, shift: $0, rows: 32, columns: 32))
        }.sorted { $0.1 < $1.1 }
        // Browsers often stop at fractional CSS offsets. Test subpixel phases in
        // the strongest candidates; only matching is interpolated, never output pixels.
        let ranked = integerRanked.prefix(16).flatMap { candidate in
            [-0.5, -0.25, 0, 0.25, 0.5].map { phase in
                (shift: candidate.0, phase: phase, score: difference(a, b, shift: candidate.0, phase: phase))
            }
        }.sorted { $0.score < $1.score }
        guard let best = ranked.first else { throw ScrollStitchError.uncertain }
        if hasFixedEdge(first, next, shift: best.shift) { throw ScrollStitchError.fixedContent }
        guard best.score <= 4,
              !ranked.contains(where: { abs($0.shift - best.shift) > 3 && $0.score < best.score + 1.5 }) else { throw ScrollStitchError.uncertain }
        guard difference(a, b, shift: best.shift, rows: 240, columns: 128, phase: best.phase) <= 4 else { throw ScrollStitchError.uncertain }
        return best.shift
    }
    /// A one-pixel analysis blur reduces font-rasterization differences between
    /// fractional browser positions. Capture/output pixels are never filtered.
    private static func matchingFrame(_ frame: ScrollFrame) throws -> ScrollFrame {
        // Matching needs a bounded number of columns, not a full Retina-width
        // blur for every sample. Keep the original vertical resolution so the
        // returned displacement and unmodified output remain pixel precise.
        let width = min(128, frame.width), height = frame.height, sourceWidth = frame.width
        let positions = (0..<width).map { x -> (Int, Int, Int, Int, Int) in
            let sourceX = x * (sourceWidth - 1) / (width - 1)
            return (max(0, sourceX - 2), max(0, sourceX - 1), sourceX,
                    min(sourceWidth - 1, sourceX + 1), min(sourceWidth - 1, sourceX + 2))
        }
        var horizontal = [UInt8](repeating: 0, count: width * height)
        var result = horizontal
        // Scope pointer access to these owned arrays. Unroll the fixed kernel and
        // calculate row/column bounds once, including in unoptimized Mac builds.
        frame.pixels.withUnsafeBufferPointer { source in
            horizontal.withUnsafeMutableBufferPointer { target in
                var y = 0
                while y < height {
                    let row = y * sourceWidth, destination = y * width
                    for x in 0..<width {
                        let p = positions[x]
                        let value = Int(source[row + p.0]) + 4 * Int(source[row + p.1]) + 6 * Int(source[row + p.2])
                            + 4 * Int(source[row + p.3]) + Int(source[row + p.4])
                        target[destination + x] = UInt8(value / 16)
                    }
                    y += 1
                }
            }
        }
        horizontal.withUnsafeBufferPointer { source in
            result.withUnsafeMutableBufferPointer { target in
                for y in 0..<height {
                    let r0 = max(0, y - 2) * width, r1 = max(0, y - 1) * width, r2 = y * width
                    let r3 = min(height - 1, y + 1) * width, r4 = min(height - 1, y + 2) * width
                    for x in 0..<width {
                        let value = Int(source[r0 + x]) + 4 * Int(source[r1 + x]) + 6 * Int(source[r2 + x])
                            + 4 * Int(source[r3 + x]) + Int(source[r4 + x])
                        target[r2 + x] = UInt8(value / 16)
                    }
                }
            }
        }
        return try ScrollFrame(width: width, height: height, pixels: result)
    }
    private static func difference(_ a: ScrollFrame, _ b: ScrollFrame, shift: Int, rows: Int = 80, columns: Int = 64, phase: Double = 0) -> Double {
        let overlap = a.height - shift, inset = max(1, a.width / 20)
        let span = a.width - 2 * inset, samples = min(columns, span), step = max(1, overlap / rows)
        let positions = (0..<samples).map { inset + $0 * span / samples }
        return a.pixels.withUnsafeBufferPointer { source in
            b.pixels.withUnsafeBufferPointer { target in
                positions.withUnsafeBufferPointer { xs in
                    var count = 0, y = 0
                    if phase == 0 {
                        // Most candidates are integer shifts. Keep this hot path
                        // entirely in integers rather than interpolating every pixel.
                        var sum = 0
                        while y < overlap {
                            let rowA = (y + shift) * a.width, rowB = y * b.width
                            var column = 0
                            while column < samples {
                                let ai = rowA + xs[column], bi = rowB + xs[column]
                                let av = Int(source[ai]), bv = Int(target[bi]), delta = abs(av - bv)
                                if delta >= 2 || abs(av - Int(source[ai + 1])) >= 2 || abs(bv - Int(target[bi + 1])) >= 2 {
                                    sum += delta; count += 1
                                }
                                column += 1
                            }
                            y += step
                        }
                        return Double(sum) / Double(max(1, count))
                    }
                    var sum = 0.0
                    let fraction = abs(phase), direction = phase < 0 ? -1 : 1
                    while y < overlap {
                        let sourceY = y + shift, adjacentY = sourceY + direction
                        if adjacentY >= 0 && adjacentY < a.height {
                            let rowA = sourceY * a.width, rowAdjacent = adjacentY * a.width, rowB = y * b.width
                            var column = 0
                            while column < samples {
                                let x = xs[column], ai = rowA + x, bi = rowB + x
                                let av = Double(source[ai]) * (1 - fraction) + Double(source[rowAdjacent + x]) * fraction
                                let bv = Double(target[bi]), delta = abs(av - bv)
                                if delta >= 2 || abs(av - Double(source[ai + 1])) >= 2 || abs(bv - Double(target[bi + 1])) >= 2 {
                                    sum += delta; count += 1
                                }
                                column += 1
                            }
                        }
                        y += step
                    }
                    return sum / Double(max(1, count))
                }
            }
        }
    }
    private static func hasFixedEdge(_ a: ScrollFrame, _ b: ScrollFrame, shift: Int) -> Bool {
        guard shift >= 4 else { return false }
        let band = min(a.height / 5, 100), inset = a.width / 20
        var fixedRows = 0
        for y in Array(0..<band) + Array((a.height - band)..<a.height) {
            var same = 0, changed = 0, low = 255, high = 0, count = 0
            // At the bottom the corresponding old pixel is found *earlier in
            // the new frame*. Looking backwards in the old frame compares two
            // unrelated sections and mistakes repeated text for a sticky footer.
            let forward = y + shift < a.height
            let movedY = forward ? y + shift : y - shift
            guard movedY >= 0 else { continue }
            for x in stride(from: inset, to: a.width - inset, by: max(1, a.width / 64)) {
                let value = Int(b.pixels[y * b.width + x])
                same += abs(Int(a.pixels[y * a.width + x]) - value)
                changed += forward
                    ? abs(Int(a.pixels[movedY * a.width + x]) - value)
                    : abs(Int(a.pixels[y * a.width + x]) - Int(b.pixels[movedY * b.width + x]))
                low = min(low, value); high = max(high, value); count += 1
            }
            if high - low > 30 && same < count && changed > count * 5 { fixedRows += 1 }
        }
        return fixedRows >= 8
    }
}

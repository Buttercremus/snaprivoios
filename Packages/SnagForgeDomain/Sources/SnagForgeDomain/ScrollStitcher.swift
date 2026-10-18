import Foundation

public enum ScrollStitchError: LocalizedError, Equatable {
    case dimensions, unchanged, uncertain, fixedContent, moving, limit
    public var errorDescription: String? {
        switch self {
        case .dimensions: String(localized: "Der Aufnahmebereich wurde verändert oder ist zu groß. Bitte neu beginnen.", bundle: DomainLocalization.bundle)
        case .unchanged: String(localized: "Noch kein neuer Abschnitt. Scrolle etwas nach unten und füge ihn erneut hinzu.", bundle: DomainLocalization.bundle)
        case .uncertain: String(localized: "Der Übergang ist nicht eindeutig. Scrolle zurück und dann weniger weit nach unten. Mindestens ein Drittel des bisherigen Inhalts muss sichtbar bleiben.", bundle: DomainLocalization.bundle)
        case .fixedContent: String(localized: "Ein feststehender Kopf- oder Fußbereich stört den Übergang. Bitte neu beginnen und nur den scrollenden Inhalt auswählen.", bundle: DomainLocalization.bundle)
        case .moving: String(localized: "Der Inhalt bewegt sich noch. Warte, bis Scrollen und Animationen stillstehen, und versuche es erneut.", bundle: DomainLocalization.bundle)
        case .limit: String(localized: "Die Grenze von 20.000 Pixeln Höhe, 40 Millionen Pixeln oder 50 Abschnitten ist erreicht. Öffne das bisherige Ergebnis im Editor.", bundle: DomainLocalization.bundle)
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
        guard width > 0, width <= 4096, height > 0, height <= 20_000,
              width * height <= 40_000_000, count <= 50 else { throw ScrollStitchError.limit }
    }
    public static func requireStable(_ a: ScrollFrame, _ b: ScrollFrame) throws {
        guard a.width == b.width, a.height == b.height else { throw ScrollStitchError.dimensions }
        guard difference(a, b, shift: 0) < 0.5 else { throw ScrollStitchError.moving }
    }
    /// Only downward vertical motion with >= 30% overlap is supported in T01.
    public static func displacement(from first: ScrollFrame, to next: ScrollFrame) throws -> Int {
        guard first.width == next.width, first.height == next.height else { throw ScrollStitchError.dimensions }
        if difference(first, next, shift: 0) < 0.5 { throw ScrollStitchError.unchanged }
        let a = try matchingFrame(first), b = try matchingFrame(next)
        let maximum = a.height * 7 / 10
        // Test every pixel displacement. Coarse shift strides miss sharp text and
        // arbitrary image patterns when the true displacement falls between samples.
        let integerRanked = (4...maximum).map { ($0, difference(a, b, shift: $0)) }.sorted { $0.1 < $1.1 }
        // Browsers often stop at fractional CSS offsets. Test subpixel phases in
        // the strongest candidates; only matching is interpolated, never output pixels.
        let ranked = integerRanked.prefix(8).flatMap { candidate in
            [-0.5, -0.25, 0, 0.25, 0.5].map { phase in
                (shift: candidate.0, phase: phase, score: difference(a, b, shift: candidate.0, phase: phase))
            }
        }.sorted { $0.score < $1.score }
        guard let best = ranked.first else { throw ScrollStitchError.uncertain }
        if hasFixedEdge(first, next, shift: best.shift) { throw ScrollStitchError.fixedContent }
        guard best.score <= 4,
              !integerRanked.contains(where: { abs($0.0 - best.shift) > 3 && $0.1 < best.score + 1.5 }) else { throw ScrollStitchError.uncertain }
        guard difference(a, b, shift: best.shift, rows: 240, columns: 128, phase: best.phase) <= 4 else { throw ScrollStitchError.uncertain }
        return best.shift
    }
    /// A one-pixel analysis blur reduces font-rasterization differences between
    /// fractional browser positions. Capture/output pixels are never filtered.
    private static func matchingFrame(_ frame: ScrollFrame) throws -> ScrollFrame {
        let weights = [1, 4, 6, 4, 1], width = frame.width, height = frame.height
        var horizontal = [UInt8](repeating: 0, count: frame.pixels.count)
        var result = horizontal
        for y in 0..<height {
            for x in 0..<width {
                var value = 0
                for i in 0..<5 { value += Int(frame.pixels[y * width + max(0, min(width - 1, x + i - 2))]) * weights[i] }
                horizontal[y * width + x] = UInt8(value / 16)
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var value = 0
                for i in 0..<5 { value += Int(horizontal[max(0, min(height - 1, y + i - 2)) * width + x]) * weights[i] }
                result[y * width + x] = UInt8(value / 16)
            }
        }
        return try ScrollFrame(width: width, height: height, pixels: result)
    }
    private static func difference(_ a: ScrollFrame, _ b: ScrollFrame, shift: Int, rows: Int = 80, columns: Int = 64, phase: Double = 0) -> Double {
        let overlap = a.height - shift, inset = max(1, a.width / 20)
        var sum: Double = 0
        var count = 0
        for y in stride(from: 0, to: overlap, by: max(1, overlap / rows)) {
            let sourceY = y + shift, adjacentY = sourceY + (phase < 0 ? -1 : 1)
            guard phase == 0 || (0..<a.height).contains(adjacentY) else { continue }
            let span = a.width - 2 * inset, samples = min(columns, span)
            for column in 0..<samples {
                let x = inset + column * span / samples
                let ai = sourceY * a.width + x, bi = y * b.width + x
                let av = Double(a.pixels[ai]) * (1 - abs(phase)) + (phase == 0 ? 0 : Double(a.pixels[adjacentY * a.width + x]) * abs(phase))
                let bv = Double(b.pixels[bi]), delta = abs(av - bv)
                if delta < 2 && abs(av - Double(a.pixels[ai + 1])) < 2 && abs(bv - Double(b.pixels[bi + 1])) < 2 { continue }
                sum += delta; count += 1
            }
        }
        return sum / Double(max(1, count))
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

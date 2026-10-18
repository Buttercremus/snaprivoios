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
    public static func displacement(from a: ScrollFrame, to b: ScrollFrame) throws -> Int {
        guard a.width == b.width, a.height == b.height else { throw ScrollStitchError.dimensions }
        if difference(a, b, shift: 0) < 0.5 { throw ScrollStitchError.unchanged }
        let maximum = a.height * 7 / 10
        // Test every pixel displacement. Coarse shift strides miss sharp text and
        // arbitrary image patterns when the true displacement falls between samples.
        let ranked = (4...maximum).map { ($0, difference(a, b, shift: $0)) }.sorted { $0.1 < $1.1 }
        guard let best = ranked.first else { throw ScrollStitchError.uncertain }
        if hasFixedEdge(a, b, shift: best.0) { throw ScrollStitchError.fixedContent }
        guard best.1 <= 3,
              !ranked.contains(where: { abs($0.0 - best.0) > 3 && $0.1 < best.1 + 1.5 }) else { throw ScrollStitchError.uncertain }
        // Recheck at a denser grid before accepting the actual seam.
        guard difference(a, b, shift: best.0, rows: 240, columns: 128) <= 3 else { throw ScrollStitchError.uncertain }
        return best.0
    }
    private static func difference(_ a: ScrollFrame, _ b: ScrollFrame, shift: Int, rows: Int = 80, columns: Int = 64) -> Double {
        let overlap = a.height - shift, inset = max(1, a.width / 20)
        var sum = 0, count = 0
        for y in stride(from: 0, to: overlap, by: max(1, overlap / rows)) {
            let span = a.width - 2 * inset, samples = min(columns, span)
            for column in 0..<samples {
                let x = inset + column * span / samples
                let ai = (y + shift) * a.width + x, bi = y * b.width + x
                let av = Int(a.pixels[ai]), bv = Int(b.pixels[bi]), delta = abs(av - bv)
                // Empty margins must not dilute text differences into a false match.
                if delta < 2 && abs(av - Int(a.pixels[ai + 1])) < 2 && abs(bv - Int(b.pixels[bi + 1])) < 2 { continue }
                sum += delta; count += 1
            }
        }
        return Double(sum) / Double(max(1, count))
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

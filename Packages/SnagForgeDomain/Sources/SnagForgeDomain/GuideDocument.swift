import Foundation

public enum GuideStyle: String, Codable, CaseIterable, Sendable { case standard, compact }

/// Only flattened, visible image pixels are retained. Source references are local conveniences.
public struct GuideStep: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var caption: String
    public var png: Data
    public var sourceProjectID: UUID?
    public var sourceLibrary: String?
    public var sourceRevision: Int?
    public init(id: UUID = UUID(), title: String, caption: String = "", png: Data,
                sourceProjectID: UUID? = nil, sourceLibrary: String? = nil, sourceRevision: Int? = nil) {
        self.id = id; self.title = title; self.caption = caption; self.png = png
        self.sourceProjectID = sourceProjectID; self.sourceLibrary = sourceLibrary
        self.sourceRevision = sourceRevision
    }
}

public struct GuideDocument: Codable, Identifiable, Equatable, Sendable {
    public var version = 2
    public var id: UUID
    public var revision: Int
    public var title: String
    public var introduction: String
    public var style: GuideStyle
    public var includesCover: Bool
    public var modifiedAt: Date
    public var steps: [GuideStep]
    public static let maximumBytes = 256_000_000
    public init(id: UUID = UUID(), title: String, introduction: String = "", style: GuideStyle = .standard,
                steps: [GuideStep] = [], revision: Int = 0, modifiedAt: Date = .now, includesCover: Bool = true) {
        self.id = id; self.title = title; self.introduction = introduction; self.style = style
        self.steps = steps; self.revision = revision; self.modifiedAt = modifiedAt
        self.includesCover = includesCover
    }
    private enum CodingKeys: String, CodingKey { case version, id, revision, title, introduction, style, includesCover, modifiedAt, steps }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard (1...2).contains(version) else { throw ProjectError.unsupportedVersion }
        id = try c.decode(UUID.self, forKey: .id); revision = try c.decode(Int.self, forKey: .revision)
        title = try c.decode(String.self, forKey: .title); introduction = try c.decode(String.self, forKey: .introduction)
        style = try c.decode(GuideStyle.self, forKey: .style); includesCover = try c.decodeIfPresent(Bool.self, forKey: .includesCover) ?? true
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt); steps = try c.decode([GuideStep].self, forKey: .steps)
        version = 2
    }
    /// Metadata-only validation also supports the local store's external image assets.
    public func validatedMetadata() throws -> Self {
        func validText(_ text: String) -> Bool { !text.unicodeScalars.contains { $0.value < 32 && ![9, 10, 13].contains($0.value) } }
        guard (1...2).contains(version) else { throw ProjectError.unsupportedVersion }
        guard revision >= 0, revision < Int.max - 1, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 256, introduction.count <= 8_000, steps.count <= 100,
              Set(steps.map(\.id)).count == steps.count, modifiedAt.timeIntervalSince1970.isFinite,
              validText(title), validText(introduction) else { throw ProjectError.invalidDocument }
        for step in steps {
            guard step.title.count <= 256, step.caption.count <= 8_000, validText(step.title), validText(step.caption),
                  step.sourceLibrary == nil || (step.sourceLibrary!.count == 64 && step.sourceLibrary!.allSatisfy(\.isHexDigit)),
                  step.sourceRevision.map({ $0 >= 0 && $0 < Int.max - 1 }) ?? true else { throw ProjectError.invalidDocument }
        }
        var value = self; value.version = 2; return value
    }
    public func validated() throws -> Self {
        let value = try validatedMetadata()
        var bytes = 0
        for step in steps {
            guard step.png.count <= 32_000_000, Self.pngSize(step.png) != nil else { throw ProjectError.invalidDocument }
            bytes += step.png.count
        }
        guard bytes <= Self.maximumBytes - 8_000_000 else { throw ProjectError.fileTooLarge }
        return value
    }
    public static func pngSize(_ data: Data) -> PixelSize? {
        guard data.count >= 33, Array(data.prefix(8)) == [137,80,78,71,13,10,26,10],
              Array(data[12..<16]) == [73,72,68,82] else { return nil }
        func integer(_ start: Int) -> Int { data[start..<start+4].reduce(0) { ($0 << 8) | Int($1) } }
        let width = integer(16), height = integer(20)
        guard width > 0, height > 0, width <= 2560, height <= 2560 else { return nil }
        return PixelSize(width: width, height: height)
    }
    public func encoded(portable: Bool = false) throws -> Data {
        var value = try validated()
        if portable {
            for i in value.steps.indices { value.steps[i].sourceProjectID = nil; value.steps[i].sourceLibrary = nil; value.steps[i].sourceRevision = nil }
        }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumBytes else { throw ProjectError.fileTooLarge }
        return data
    }
    public static func read(_ url: URL) throws -> Self {
        try PropertyListDecoder().decode(Self.self, from: ProjectArchive.readRegularFile(url, limit: maximumBytes)).validated()
    }
    public mutating func moveStep(_ id: UUID, by distance: Int) {
        guard let from = steps.firstIndex(where: { $0.id == id }), distance == -1 || distance == 1,
              steps.indices.contains(from + distance) else { return }
        steps.swapAt(from, from + distance)
    }
    public mutating func moveStep(_ id: UUID, before target: UUID?) {
        guard id != target, let from = steps.firstIndex(where: { $0.id == id }),
              target == nil || steps.contains(where: { $0.id == target }) else { return }
        let step = steps.remove(at: from)
        let destination = target.flatMap { target in steps.firstIndex { $0.id == target } } ?? steps.endIndex
        steps.insert(step, at: destination)
    }
}

public enum GuideInsertion: Equatable, Sendable {
    case end, before(UUID), after(UUID)
}

extension GuideDocument {
    /// Validate the whole prospective document before changing its order or assets.
    public mutating func insertSteps(_ additions: [GuideStep], at position: GuideInsertion = .end) throws {
        guard !additions.isEmpty else { return }
        let index: Int
        switch position {
        case .end: index = steps.count
        case .before(let id):
            guard let found = steps.firstIndex(where: { $0.id == id }) else { throw ProjectError.invalidDocument }
            index = found
        case .after(let id):
            guard let found = steps.firstIndex(where: { $0.id == id }) else { throw ProjectError.invalidDocument }
            index = found + 1
        }
        guard steps.count + additions.count <= 100 else { throw ProjectError.documentTooLarge }
        var next = self
        next.steps.insert(contentsOf: additions, at: index)
        self = try next.validated()
    }
    @discardableResult public mutating func duplicateStep(_ id: UUID) throws -> UUID {
        guard var copy = steps.first(where: { $0.id == id }) else { throw ProjectError.invalidDocument }
        copy.id = UUID()
        try insertSteps([copy], at: .after(id))
        return copy.id
    }
}

/// Searchable user text only; neither PNG data nor local source references are indexed.
public struct GuideSearchMatch: Identifiable, Equatable, Sendable {
    public var id: String { documentID.uuidString + ":" + (stepID?.uuidString ?? "header") }
    public let documentID: UUID
    public let documentTitle: String
    public let stepID: UUID?
    public let stepNumber: Int?
    public let stepTitle: String?
    public let excerpt: String

    public static func matches(in document: GuideDocument, query: String) -> [Self] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        func matches(_ texts: String...) -> Bool {
            terms.allSatisfy { term in texts.contains { $0.localizedStandardContains(term) } }
        }
        func excerpt(_ text: String) -> String {
            let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let match = terms.compactMap { flat.localizedStandardRange(of: $0) }.min { $0.lowerBound < $1.lowerBound }
            let start = match.map { flat.index($0.lowerBound, offsetBy: -48, limitedBy: flat.startIndex) ?? flat.startIndex } ?? flat.startIndex
            let end = flat.index(start, offsetBy: 160, limitedBy: flat.endIndex) ?? flat.endIndex
            return (start > flat.startIndex ? "…" : "") + String(flat[start..<end]) + (end < flat.endIndex ? "…" : "")
        }
        var results: [Self] = []
        if matches(document.title, document.introduction) {
            results.append(Self(documentID: document.id, documentTitle: document.title, stepID: nil, stepNumber: nil, stepTitle: nil,
                                excerpt: excerpt(document.introduction.isEmpty ? document.title : document.introduction)))
        }
        for (index, step) in document.steps.enumerated() where matches(step.title, step.caption) {
            results.append(Self(documentID: document.id, documentTitle: document.title, stepID: step.id, stepNumber: index + 1,
                                stepTitle: step.title, excerpt: excerpt(step.caption.isEmpty ? step.title : step.caption)))
        }
        return results
    }
}

public enum GuideMarkdown {
    /// Treat all user text as literal prose, including HTML, links and Markdown controls.
    public static func literal(_ text: String, singleLine: Bool = false) -> String {
        let value = singleLine ? text.components(separatedBy: .newlines).joined(separator: " ") : text
        let controls = Set("\\`*_{}[]()#+-.!|>~=")
        return value.map { char -> String in
            switch char {
            case "&": "&amp;"
            case "<": "&lt;"
            case ">": "&gt;"
            default: controls.contains(char) ? "\\\(char)" : String(char)
            }
        }.joined()
    }
    public static func text(_ document: GuideDocument) throws -> String {
        _ = try document.validated()
        var result = "# \(literal(document.title, singleLine: true))\n\n"
        if !document.introduction.isEmpty { result += literal(document.introduction) + "\n\n" }
        for (index, step) in document.steps.enumerated() {
            result += "## \(index + 1). \(literal(step.title, singleLine: true))\n\n"
            result += "![\(literal(step.title, singleLine: true))](images/\(String(format: "%04d", index + 1)).png)\n\n"
            if !step.caption.isEmpty { result += literal(step.caption) + "\n\n" }
        }
        return result
    }
}

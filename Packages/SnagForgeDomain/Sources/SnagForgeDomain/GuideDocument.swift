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
    public init(id: UUID = UUID(), title: String, caption: String = "", png: Data,
                sourceProjectID: UUID? = nil, sourceLibrary: String? = nil) {
        self.id = id; self.title = title; self.caption = caption; self.png = png
        self.sourceProjectID = sourceProjectID; self.sourceLibrary = sourceLibrary
    }
}

public struct GuideDocument: Codable, Identifiable, Equatable, Sendable {
    public var version = 1
    public var id: UUID
    public var revision: Int
    public var title: String
    public var introduction: String
    public var style: GuideStyle
    public var modifiedAt: Date
    public var steps: [GuideStep]
    public static let maximumBytes = 256_000_000
    public init(id: UUID = UUID(), title: String, introduction: String = "", style: GuideStyle = .standard,
                steps: [GuideStep] = [], revision: Int = 0, modifiedAt: Date = .now) {
        self.id = id; self.title = title; self.introduction = introduction; self.style = style
        self.steps = steps; self.revision = revision; self.modifiedAt = modifiedAt
    }
    public func validated() throws -> Self {
        func validText(_ text: String) -> Bool { !text.unicodeScalars.contains { $0.value < 32 && ![9, 10, 13].contains($0.value) } }
        guard version == 1 else { throw ProjectError.unsupportedVersion }
        guard revision >= 0, revision < Int.max - 1, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 256, introduction.count <= 8_000, steps.count <= 100,
              Set(steps.map(\.id)).count == steps.count, modifiedAt.timeIntervalSince1970.isFinite,
              validText(title), validText(introduction) else { throw ProjectError.invalidDocument }
        var bytes = 0
        for step in steps {
            guard step.title.count <= 256, step.caption.count <= 8_000, validText(step.title), validText(step.caption), step.png.count <= 32_000_000,
                  step.sourceLibrary == nil || (step.sourceLibrary!.count == 64 && step.sourceLibrary!.allSatisfy(\.isHexDigit)),
                  Self.pngSize(step.png) != nil else { throw ProjectError.invalidDocument }
            bytes += step.png.count
        }
        guard bytes <= Self.maximumBytes - 8_000_000 else { throw ProjectError.fileTooLarge }
        return self
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
            for i in value.steps.indices { value.steps[i].sourceProjectID = nil; value.steps[i].sourceLibrary = nil }
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

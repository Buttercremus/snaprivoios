import Foundation

public enum ProjectOrganization {
    public static let maximumTags = 32
    public static let maximumCollections = 16
    public static func normalized(_ names: [String], limit: Int) throws -> [String] {
        guard names.count <= 256 else { throw ProjectError.invalidDocument }
        var seen = Set<String>(), result: [String] = []
        for name in names {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            guard !name.isEmpty else { continue }
            guard name.count <= 80, name.utf8.count <= 320,
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ProjectError.invalidDocument }
            if seen.insert(LibrarySearch.fold(name)).inserted { result.append(name) }
        }
        guard result.count <= limit else { throw ProjectError.invalidDocument }
        return result
    }
}

public enum LibrarySearch {
    public static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
    public static func metadata(_ document: ProjectDocument) -> String {
        fold(([document.title] + document.tags + document.collections).joined(separator: "\n"))
    }
    public static func matches(_ document: ProjectDocument, query: String, content: String = "") -> Bool {
        let metadata = metadata(document), content = fold(content)
        return terms(query).allSatisfy { metadata.contains($0) || content.contains($0) }
    }
    /// Only visible-image inputs affect OCR. Renaming and organizing reuse valid results.
    public static func imageKey(_ document: ProjectDocument) throws -> String {
        struct ImageState: Encodable {
            let size: PixelSize
            let objects: [EditorObject]
            let crop: CGRect?
            let resizedSize: PixelSize?
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ProjectArchive.hash(try encoder.encode(ImageState(size: document.pixelSize, objects: document.objects,
                                                                 crop: document.crop, resizedSize: document.resizedSize)))
    }
}

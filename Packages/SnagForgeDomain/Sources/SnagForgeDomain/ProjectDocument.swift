import Foundation

/// Source pixels and annotations always use the immutable original's top-left coordinates.
public struct ProjectDocument: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = 19
    public let schemaVersion: Int
    public let id: UUID
    public var favorite: Bool?
    public var isFavorite: Bool { get { favorite ?? false } set { favorite = newValue ? true : nil } }
    public var title: String
    private var storedTags: [String]?
    private var storedCollections: [String]?
    public var tags: [String] { get { storedTags ?? [] } set { storedTags = newValue.isEmpty ? nil : newValue } }
    public var collections: [String] { get { storedCollections ?? [] } set { storedCollections = newValue.isEmpty ? nil : newValue } }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, favorite, title, createdAt, modifiedAt, revision, pixelSize, objects, crop, resizedSize, canvasRect, imageTransform, presentation
        case storedTags = "tags", storedCollections = "collections"
    }
    public let createdAt: Date
    public var modifiedAt: Date
    public var revision: Int
    public let pixelSize: PixelSize
    public var objects: [EditorObject]
    public var canvasRect: CGRect?
    public var fullCanvasRect: CGRect { canvasRect ?? EditorCrop.fullRect(pixelSize) }
    public var crop: CGRect?
    public var resizedSize: PixelSize?
    public var presentation: EditorPresentation?
    public var imageTransform: EditorImageTransform?
    public var transform: EditorImageTransform { imageTransform ?? .identity }
    public var untransformedOutputPixelSize: PixelSize { resizedSize ?? PixelSize(width: Int(outputRect.width), height: Int(outputRect.height))! }
    public var contentPixelSize: PixelSize { transform.applying(to: untransformedOutputPixelSize) }
    public var outputPixelSize: PixelSize { presentation?.geometry(for: contentPixelSize)?.outputSize ?? contentPixelSize }
    public var outputRect: CGRect { crop ?? fullCanvasRect }

    public init(id: UUID = UUID(), title: String, pixelSize: PixelSize, objects: [EditorObject] = [],
                createdAt: Date = .now, modifiedAt: Date = .now, revision: Int = 0, crop: CGRect? = nil, resizedSize: PixelSize? = nil, isFavorite: Bool = false,
                tags: [String] = [], collections: [String] = [], canvasRect: CGRect? = nil, transform: EditorImageTransform = .identity, presentation: EditorPresentation? = nil) {
        self.presentation = presentation?.isIdentity == true ? nil : presentation
        favorite = isFavorite ? true : nil
        schemaVersion = Self.currentVersion
        self.id = id; self.title = title; self.pixelSize = pixelSize; self.objects = objects
        self.createdAt = createdAt; self.modifiedAt = modifiedAt; self.revision = revision
        self.crop = crop; self.resizedSize = resizedSize; self.canvasRect = canvasRect; self.imageTransform = transform == .identity ? nil : transform
        storedTags = tags.isEmpty ? nil : tags; storedCollections = collections.isEmpty ? nil : collections
    }

    public func validated() throws -> Self {
        guard schemaVersion == Self.currentVersion else { throw ProjectError.unsupportedVersion }
        guard try ProjectOrganization.normalized(tags, limit: ProjectOrganization.maximumTags) == tags,
              try ProjectOrganization.normalized(collections, limit: ProjectOrganization.maximumCollections) == collections else { throw ProjectError.invalidDocument }
        if let resizedSize, !EditorResize.isValid(resizedSize) { throw ProjectError.invalidDocument }
        if let canvasRect, !EditorCanvasExtent.isValid(canvasRect) || !canvasRect.contains(EditorCrop.fullRect(pixelSize)) { throw ProjectError.invalidDocument }
        if let crop, !EditorCrop.isValid(crop, in: fullCanvasRect) { throw ProjectError.invalidDocument }
        guard revision >= 0, revision < Int.max - 1, !title.isEmpty, title.count <= 1024,
              pixelSize.width <= 32768, pixelSize.height <= 32768,
              Int64(pixelSize.width) * Int64(pixelSize.height) <= 100_000_000,
              objects.count <= 10_000, Set(objects.map(\.id)).count == objects.count,
              createdAt.timeIntervalSince1970.isFinite, modifiedAt.timeIntervalSince1970.isFinite else {
            throw ProjectError.invalidDocument
        }
        if let presentation, !presentation.isValid || presentation.geometry(for: contentPixelSize) == nil { throw ProjectError.invalidDocument }
        guard objects.compactMap(\.imageAsset).reduce(0, { $0 + $1.png.count }) <= 16_000_000 else { throw ProjectError.documentTooLarge }
        for object in objects {
            if object.kind == .image {
                guard let asset = object.imageAsset, asset.isValid, object.rect.width >= 1, object.rect.height >= 1 else { throw ProjectError.invalidDocument }
            } else if object.imageAsset != nil { throw ProjectError.invalidDocument }
            guard object.drawingStyle == nil || object.supportsHandDrawn else { throw ProjectError.invalidDocument }
            if let pen = object.penStroke {
                guard object.kind == .pen, !pen.points.isEmpty, pen.points.count <= EditorPenStroke.maximumPoints,
                      pen.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { throw ProjectError.invalidDocument }
            } else if object.kind == .pen { throw ProjectError.invalidDocument }
            if let spotlight = object.spotlightStyle {
                guard object.kind == .spotlight, spotlight.opacity.isFinite, (0...0.95).contains(spotlight.opacity) else { throw ProjectError.invalidDocument }
            } else if object.kind == .spotlight { throw ProjectError.invalidDocument }
            if object.kind == .spotlight, object.rect.width <= 0 || object.rect.height <= 0 { throw ProjectError.invalidDocument }
            if let bend = object.arrowBend {
                guard object.kind == .arrow, [bend.x, bend.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { throw ProjectError.invalidDocument }
            }
            if let source = object.magnifierSource {
                guard object.kind == .magnifier, [source.x, source.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { throw ProjectError.invalidDocument }
            }
            if let zoom = object.magnification {
                guard object.kind == .magnifier, zoom.isFinite, (1.5...5).contains(zoom) else { throw ProjectError.invalidDocument }
            }
            if object.kind == .magnifier, object.rect.width < 1 || object.rect.height < 1 { throw ProjectError.invalidDocument }
            if let highlight = object.highlightStyle {
                guard object.kind == .highlight, highlight.opacity.isFinite, (0...1).contains(highlight.opacity),
                      highlight.points.count <= EditorHighlightStyle.maximumPoints,
                      highlight.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),
                      highlight.mode == .rectangle ? highlight.points.isEmpty : !highlight.points.isEmpty else { throw ProjectError.invalidDocument }
            }
            if object.kind == .highlight, object.highlightStyle == nil { throw ProjectError.invalidDocument }
            if let step = object.stepStyle {
                guard object.kind == .step, (1...EditorSteps.maximumIndex).contains(step.index),
                      [step.textColor.red, step.textColor.green, step.textColor.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw ProjectError.invalidDocument }
            }
            if object.kind == .step {
                guard object.stepStyle != nil, object.rect.width >= 1, object.rect.height >= 1 else { throw ProjectError.invalidDocument }
            }
            if let family = object.textStyle?.family {
                guard !family.isEmpty, family.utf8.count <= 256 else { throw ProjectError.invalidDocument }
            }
            if let tip = object.calloutTip {
                guard [tip.x, tip.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { throw ProjectError.invalidDocument }
            }
            if let fill = object.fill {
                guard fill.opacity.isFinite, (0...1).contains(fill.opacity),
                      [fill.color.red, fill.color.green, fill.color.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    throw ProjectError.invalidDocument
                }
            }
            if let radius = object.cornerRadius {
                guard radius.isFinite, (0...1000).contains(radius) else { throw ProjectError.invalidDocument }
            }
            if let width = object.textWidth {
                guard width.isFinite, (1...1_000_000).contains(width) else { throw ProjectError.invalidDocument }
            }
            if let height = object.textHeight {
                guard height.isFinite, (1...1_000_000).contains(height) else { throw ProjectError.invalidDocument }
            }
            guard object.name.map({ $0.count <= 120 && !$0.unicodeScalars.contains(where: { $0.value < 32 }) }) != false else { throw ProjectError.invalidDocument }
            if let angle = object.imageRotationDegrees {
                guard object.kind == .image, angle.isFinite, (-180...180).contains(angle) else { throw ProjectError.invalidDocument }
            }
            let values = [object.start.x, object.start.y, object.end.x, object.end.y, object.fontSize, object.lineWidth, object.blurRadius]
            guard values.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                  (1...1000).contains(object.fontSize), (0.1...1000).contains(object.lineWidth),
                  (0...1000).contains(object.blurRadius), object.blurStyle == nil || object.kind == .blur, object.text.utf8.count <= 1_000_000,
                  [object.color.red, object.color.green, object.color.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw ProjectError.invalidDocument
            }
        }
        return self
    }

    public static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: data).schemaVersion
        guard (1...currentVersion).contains(version) else {
            throw ProjectError.unsupportedVersion
        }
        let value = try decoder.decode(Self.self, from: data)
        if version < currentVersion {
            guard version >= 19 || value.objects.allSatisfy({ $0.imageRotationDegrees == nil }) else { throw ProjectError.invalidDocument }
            guard version >= 18 || value.objects.allSatisfy({ $0.blurStyle == nil }) else { throw ProjectError.invalidDocument }
            guard version >= 16 || value.presentation == nil else { throw ProjectError.invalidDocument }
            guard version >= 17 || value.presentation?.border == nil else { throw ProjectError.invalidDocument }
            guard version >= 15 || value.imageTransform == nil else { throw ProjectError.invalidDocument }
            guard version >= 14 || value.objects.allSatisfy({ $0.magnifierSource == nil }) else { throw ProjectError.invalidDocument }
            guard version >= 11 || value.canvasRect == nil else { throw ProjectError.invalidDocument }
            guard version >= 13 || value.objects.allSatisfy({ $0.kind != .pen && $0.kind != .spotlight && $0.penStroke == nil && $0.spotlightStyle == nil }) else { throw ProjectError.invalidDocument }
            guard version >= 12 || value.objects.allSatisfy({ $0.arrowBend == nil && $0.magnification == nil && $0.kind != .magnifier && ($0.drawingStyle == nil || $0.drawingStyle == .precise || $0.drawingStyle == .handDrawn) }) else { throw ProjectError.invalidDocument }
            // Migrate in memory. Older builds reject new formats rather than losing fields.
            guard (version >= 3 || value.resizedSize == nil), version != 1 || value.crop == nil else { throw ProjectError.invalidDocument }
            guard version >= 6 || value.objects.allSatisfy({ $0.kind != .highlight && $0.kind != .step && $0.highlightStyle == nil && $0.stepStyle == nil }) else {
                throw ProjectError.invalidDocument
            }
            guard version >= 7 || (value.tags.isEmpty && value.collections.isEmpty) else { throw ProjectError.invalidDocument }
            guard version >= 8 || value.objects.allSatisfy({ $0.drawingStyle == nil }) else { throw ProjectError.invalidDocument }
            guard version >= 10 || value.objects.allSatisfy({ $0.name == nil }) else { throw ProjectError.invalidDocument }
            guard version >= 9 || value.objects.allSatisfy({ $0.groupID == nil && $0.imageAsset == nil && $0.kind != .image }) else { throw ProjectError.invalidDocument }
            return try Self(id: value.id, title: value.title, pixelSize: value.pixelSize, objects: value.objects,
                            createdAt: value.createdAt, modifiedAt: value.modifiedAt, revision: value.revision, crop: value.crop, resizedSize: value.resizedSize, isFavorite: value.isFavorite, tags: value.tags, collections: value.collections, canvasRect: value.canvasRect, transform: value.transform, presentation: value.presentation).validated()
        }
        return try value.validated()
    }
}

public enum ProjectError: LocalizedError, Equatable {
    case unsupportedVersion, invalidDocument, missingOriginal, staleRevision, documentTooLarge, fileTooLarge, libraryBusy
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: String(localized: "Dieses Projekt benötigt eine andere Snaprivo-Version. Es wird nicht überschrieben.", bundle: DomainLocalization.bundle)
        case .invalidDocument: String(localized: "Das Projekt ist beschädigt oder enthält ungültige Bilddaten.", bundle: DomainLocalization.bundle)
        case .missingOriginal: String(localized: "Das Originalbild des Projekts fehlt.", bundle: DomainLocalization.bundle)
        case .staleRevision: String(localized: "Ein neuerer Projektstand wurde bereits gespeichert. Sichere deine Änderungen als Kopie.", bundle: DomainLocalization.bundle)
        case .documentTooLarge: String(localized: "Die Markierungen überschreiten die Projektgrenze von 32 MB. Kürze sehr lange Texte oder entferne Objekte.", bundle: DomainLocalization.bundle)
        case .fileTooLarge: String(localized: "Die gewählte Datei überschreitet die unterstützte Dateigröße. Sie wurde nicht übernommen.", bundle: DomainLocalization.bundle)
        case .libraryBusy: String(localized: "Die Snaprivo-Bibliothek wird gerade von einer anderen App-Instanz verwendet. Bitte erneut versuchen.", bundle: DomainLocalization.bundle)
        }
    }
}

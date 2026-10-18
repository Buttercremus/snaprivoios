/// User intent only. ScreenCaptureKit types belong in the platform adapter.
public struct CaptureConfiguration: Equatable, Sendable {
    public var media: CaptureMedia
    public var source: CaptureSource
    public var includesCursor: Bool
    public var delaySeconds: Int

    /// Images wait before freezing the desktop; video waits after explicit Start.
    public var selectionDelaySeconds: Int { media == .image ? delaySeconds : 0 }
    public var recordingDelaySeconds: Int { media == .video ? delaySeconds : 0 }

    public init(
        media: CaptureMedia = .image,
        source: CaptureSource = .automatic,
        includesCursor: Bool = false,
        delaySeconds: Int = 0
    ) {
        self.media = media
        self.source = source
        self.includesCursor = includesCursor
        self.delaySeconds = delaySeconds
    }
}

public enum CaptureMedia: String, CaseIterable, Sendable {
    case image, video
}

public enum CaptureSource: String, CaseIterable, Sendable {
    case automatic, region, window, display
}

public enum AnnotationTool: String, CaseIterable, Sendable {
    case selection, arrow, text, callout, rectangle, ellipse, crop, highlight, steps, blur, redact
}

/// All persisted image geometry uses pixels with a top-left origin.
/// Capture adapters must convert display points into this coordinate system.
public struct PixelSize: Equatable, Codable, Sendable {
    public let width: Int
    public let height: Int

    public init?(width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Int.self, forKey: .width)
        let height = try container.decode(Int.self, forKey: .height)
        guard let size = Self(width: width, height: height) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Image dimensions must be positive."
            ))
        }
        self = size
    }
}

import Foundation

public struct EditorImageAsset: Codable, Equatable, Sendable {
    public let digest: String
    public let png: Data
    public let size: PixelSize
    public init(png: Data, size: PixelSize) throws {
        self.png = png; self.size = size; digest = ProjectArchive.hash(png)
        guard isValid else { throw ProjectError.invalidDocument }
    }
    public var isValid: Bool {
        png.count <= 8_000_000 && size.width <= 4096 && size.height <= 4096
        && ProjectArchive.pngSize(png) == size && digest == ProjectArchive.hash(png)
    }
}

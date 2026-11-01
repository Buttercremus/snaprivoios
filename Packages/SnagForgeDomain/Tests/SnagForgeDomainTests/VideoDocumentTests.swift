import Foundation
import Testing
@testable import SnagForgeDomain

@Test func videoMetadataRoundTripRequiresFinalizedMediaFacts() throws {
    var document = VideoDocument(title: "Support video", fileName: "clip.mp4")
    #expect(try document.validated() == document)
    document.state = .finished
    #expect(throws: ProjectError.self) { try document.validated() }
    document.duration = 12.5; document.pixelSize = PixelSize(width: 1920, height: 1080); document.hasAudio = true
    #expect(try JSONDecoder().decode(VideoDocument.self, from: JSONEncoder().encode(document)).validated() == document)
    document.title = String(repeating: "🎬", count: 1024)
    #expect(try document.validated().title == document.title)
}
@Test func videoMetadataRejectsUnsafePathsNewerVersionsAndInvalidSizes() {
    for name in ["../clip.mp4", "a/b.mp4", "a\\b.mp4", "a:clip.mp4", "a\0.mp4", "clip.png"] {
        #expect(throws: ProjectError.self) { try VideoDocument(title: "Video", fileName: name).validated() }
    }
    var document = VideoDocument(title: "Video", fileName: "clip.mp4")
    document.schemaVersion = 999
    #expect(throws: ProjectError.self) { try document.validated() }
    document.schemaVersion = 4; document.duration = .infinity
    #expect(throws: ProjectError.self) { try document.validated() }
    document.duration = 1; document.pixelSize = PixelSize(width: Int.max, height: 1)
    #expect(throws: ProjectError.self) { try document.validated() }
}

@Test func videoPresentationGeometryAndVersionedStorage() throws {
    let source = PixelSize(width: 321, height: 181)!
    var style = VideoPresentation()
    #expect(style.isIdentity && style.isValid)
    style.backdrop = .gradient; style.padding = 24; style.cornerRadius = 18; style.shadow = 0.5
    let geometry = try #require(style.geometry(for: source))
    #expect(geometry.outputSize == PixelSize(width: 370, height: 230))
    #expect(geometry.videoFrame.width == 321 && geometry.videoFrame.minX == 24.5)
    style.aspectRatio = .portrait
    let portrait = try #require(style.geometry(for: source))
    #expect(portrait.outputSize.width % 2 == 0 && portrait.outputSize.height % 2 == 0)
    #expect(abs(Double(portrait.outputSize.width) / Double(portrait.outputSize.height) - 9.0 / 16) < 0.003)
    var document = VideoDocument(title: "Styled", fileName: "clip.mp4", state: .finished, duration: 2, pixelSize: source)
    document.presentation = style
    #expect(try JSONDecoder().decode(VideoDocument.self, from: JSONEncoder().encode(document)).validated() == document)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    json["schemaVersion"] = 3
    #expect(throws: ProjectError.self) { try JSONDecoder().decode(VideoDocument.self, from: JSONSerialization.data(withJSONObject: json)) }
    json.removeValue(forKey: "presentation")
    let legacy = try JSONDecoder().decode(VideoDocument.self, from: JSONSerialization.data(withJSONObject: json)).validated()
    #expect(legacy.presentation.isIdentity && legacy.schemaVersion == 4)
    for bad in [-1.0, .infinity, .nan, 121.0] {
        var invalid = style; invalid.cornerRadius = bad
        #expect(!invalid.isValid && invalid.geometry(for: source) == nil)
    }
    var oversized = style; oversized.padding = 241
    #expect(!oversized.isValid)
    #expect(style.geometry(for: PixelSize(width: 8192, height: 8192)!) == nil)
    document.presentation.color.red = .nan
    #expect(throws: ProjectError.self) { try document.validated() }
}
@Test func videoBackupRejectsPartialDuplicateAndUnverifiedEntries() throws {
    var document = VideoDocument(title: "Video", fileName: "clip.mp4", state: .finished, duration: 2, pixelSize: PixelSize(width: 320, height: 180))
    let entry = VideoBackup.Entry(document: document, sha256: String(repeating: "a", count: 64))
    #expect(try VideoBackup(entries: [entry]).validated().entries.count == 1)
    #expect(throws: ProjectError.self) { try VideoBackup(entries: [entry, entry]).validated() }
    #expect(throws: ProjectError.self) { try VideoBackup(entries: [.init(document: document, sha256: "bad")]).validated() }
    document.state = .recording
    #expect(throws: ProjectError.self) { try VideoBackup(entries: [.init(document: document, sha256: entry.sha256)]).validated() }
}

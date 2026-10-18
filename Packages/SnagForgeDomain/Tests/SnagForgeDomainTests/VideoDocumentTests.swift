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
    document.schemaVersion = 3; document.duration = .infinity
    #expect(throws: ProjectError.self) { try document.validated() }
    document.duration = 1; document.pixelSize = PixelSize(width: Int.max, height: 1)
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

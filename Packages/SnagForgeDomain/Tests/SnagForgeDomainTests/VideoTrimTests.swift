import Foundation
import Testing
@testable import SnagForgeDomain

@Test func videoTrimValidatesBoundsAndPreservesOriginalRange() throws {
    #expect(try VideoTrim(start: 0.25, end: 0.75).validated(duration: 1).duration == 0.5)
    #expect(try VideoTrim(start: 0, end: 1).normalized(duration: 1) == nil)
    for trim in [VideoTrim(start: -1, end: 1), .init(start: 0, end: 2), .init(start: 1, end: 0), .init(start: 0, end: 0), .init(start: .nan, end: 1), .init(start: 0, end: .infinity), .init(start: 0.5, end: 0.51)] {
        #expect(throws: ProjectError.self) { try trim.validated(duration: 1) }
    }
    #expect(try VideoTrim(start: 0, end: 0.02).validated(duration: 0.02).duration == 0.02)
    #expect(throws: ProjectError.self) { try VideoTrim(start: 0.000_000_1, end: 0).validated(duration: 0.000_000_1) }
    #expect(throws: ProjectError.self) { try VideoTrim(start: 0, end: 1).validated(duration: .nan) }
}
@Test func videoVersionOneMigratesAndVersionTwoRetainsTrim() throws {
    var document = VideoDocument(title: "Legacy", fileName: "clip.mp4", state: .finished, duration: 2, pixelSize: PixelSize(width: 320, height: 180))
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    json["schemaVersion"] = 1; json.removeValue(forKey: "revision")
    let migrated = try JSONDecoder().decode(VideoDocument.self, from: JSONSerialization.data(withJSONObject: json)).validated()
    #expect(migrated.schemaVersion == 5 && migrated.trim == nil && migrated.revision == 0 && migrated.presentation.isIdentity && migrated.playback.isIdentity)
    document.trim = .init(start: 0.5, end: 1.5); document.revision = 2
    #expect(try JSONDecoder().decode(VideoDocument.self, from: JSONEncoder().encode(document)).validated() == document)
    document.state = .failed
    #expect(throws: ProjectError.self) { try document.validated() }
}

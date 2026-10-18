import Foundation
import CoreGraphics
import Testing
@testable import SnagForgeDomain

@Test func namedObjectsPersistAndFormatNineKeepsGroupsDuringMigration() throws {
    var object = EditorObject(kind: .arrow, start: .zero, end: CGPoint(x: 30, y: 30))
    object.groupID = UUID(); object.name = "Navigation arrow"
    let document = ProjectDocument(title: "Synthetic", pixelSize: PixelSize(width: 100, height: 100)!, objects: [object])
    #expect(try ProjectDocument.decode(JSONEncoder().encode(document)).objects == [object])
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    legacy["schemaVersion"] = 9
    var objects = legacy["objects"] as! [[String: Any]]
    objects[0].removeValue(forKey: "name"); legacy["objects"] = objects
    let migrated = try ProjectDocument.decode(JSONSerialization.data(withJSONObject: legacy))
    #expect(migrated.objects[0].groupID == object.groupID && migrated.objects[0].name == nil)
    object.name = "Invalid\nname"
    #expect(throws: ProjectError.self) { try ProjectDocument(title: "Bad", pixelSize: document.pixelSize, objects: [object]).validated() }
}

@Test func videoTrashAndMissingInterruptedMediaRoundTrip() throws {
    var document = VideoDocument(title: "Interrupted", fileName: ".synthetic.recording.mp4", state: .interrupted)
    document.trashedAt = .now
    #expect(try JSONDecoder().decode(VideoDocument.self, from: JSONEncoder().encode(document)).validated() == document)
    let backup = VideoBackup(entries: [.init(document: document, sha256: "", hasFile: false)])
    #expect(try JSONDecoder().decode(VideoBackup.self, from: JSONEncoder().encode(backup)).validated() == backup)
    document.state = .recording
    #expect(throws: ProjectError.self) { try VideoBackup(entries: [.init(document: document, sha256: "", hasFile: false)]).validated() }
}

@Test func scrollMatchesFractionalBrowserOffsetsWithoutAcceptingMotion() throws {
    let width = 100, height = 240, delta = 63
    func value(_ x: Int, _ y: Int) -> UInt8 { UInt8(truncatingIfNeeded: (y * 7919 + x * 104729) ^ (y * x * 313)) }
    let a = try ScrollFrame(width: width, height: height, pixels: (0..<height).flatMap { y in (0..<width).map { value($0, y) } })
    let b = try ScrollFrame(width: width, height: height, pixels: (0..<height).flatMap { y in (0..<width).map { x in
        UInt8((Int(value(x, y + delta)) * 3 + Int(value(x, y + delta + 1))) / 4)
    } })
    #expect(try ScrollStitcher.displacement(from: a, to: b) == delta)
    #expect(throws: ScrollStitchError.moving) { try ScrollStitcher.requireStable(a, b) }
}

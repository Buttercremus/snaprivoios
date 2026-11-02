import Foundation
import Testing
@testable import SnagForgeDomain

struct VideoPlaybackTests {
    @Test func storageMigratesOldEditsAndRejectsMislabeledNewOnes() throws {
        var document = VideoDocument(title: "Sequence", fileName: "clip.mp4", state: .finished, duration: 10, pixelSize: PixelSize(width: 320, height: 180))
        document.playback = try VideoPlayback().removing(.init(start: 2, end: 4), duration: 10)
        #expect(try JSONDecoder().decode(VideoDocument.self, from: JSONEncoder().encode(document)).validated() == document)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        json["schemaVersion"] = 4
        #expect(throws: ProjectError.self) { try JSONDecoder().decode(VideoDocument.self, from: JSONSerialization.data(withJSONObject: json)) }
        json.removeValue(forKey: "playback")
        let legacy = try JSONDecoder().decode(VideoDocument.self, from: JSONSerialization.data(withJSONObject: json)).validated()
        #expect(legacy.schemaVersion == 5 && legacy.playback.isIdentity)
        document.trim = .init(start: 2, end: 4)
        #expect(throws: ProjectError.self) { try document.validated() }
    }
    @Test func splicesAndRetimeShareOneMapping() throws {
        var edit = try VideoPlayback().removing(.init(start: 2, end: 4), duration: 10)
        edit = try edit.removing(.init(start: 3, end: 5), duration: 10)
        edit = try edit.removing(.init(start: 8, end: 10), duration: 10)
        edit.speed = 2
        #expect(try edit.validated(duration: 10) == edit)
        #expect(edit.keptRanges(duration: 10) == [.init(start: 0, end: 2), .init(start: 5, end: 8)])
        #expect(edit.outputDuration(selection: .init(start: 1, end: 9), duration: 10) == 2)
        #expect(edit.outputTime(for: 3, duration: 10) == 1)
        #expect(edit.sourceTime(for: 1, duration: 10) == 5)
        #expect(edit.sourceTime(for: 99, duration: 10) == 8)
        for source in [0.0, 0.5, 1.9, 5, 6, 7.9] {
            #expect(abs(edit.sourceTime(for: edit.outputTime(for: source, duration: 10), duration: 10) - source) < 0.000001)
        }
        #expect(throws: ProjectError.self) { try edit.validated(duration: 10, selection: .init(start: 2, end: 5)) }
        #expect(throws: ProjectError.self) { try VideoPlayback().removing(.init(start: 0, end: 10), duration: 10) }
        #expect(try JSONDecoder().decode(VideoPlayback.self, from: JSONEncoder().encode(edit)) == edit)
    }
    @Test func rejectsInvalidAndUnboundedEdits() throws {
        for speed in [Double.nan, .infinity, 0, 4.01] {
            var edit = VideoPlayback(); edit.speed = speed
            #expect(throws: ProjectError.self) { try edit.validated(duration: 10) }
        }
        for volume in [Double.nan, -0.1, 1.1] {
            var edit = VideoPlayback(); edit.volume = volume
            #expect(throws: ProjectError.self) { try edit.validated(duration: 10) }
        }
        var edit = VideoPlayback()
        edit.removed = [.init(start: 2, end: 5), .init(start: 4, end: 6)]
        #expect(throws: ProjectError.self) { try edit.validated(duration: 10) }
        edit.removed = (0..<65).map { .init(start: Double($0), end: Double($0) + 0.5) }
        #expect(throws: ProjectError.self) { try edit.validated(duration: 100) }
        edit = VideoPlayback(); edit.zooms = [.init(range: .init(start: 1, end: 2), centerX: .infinity)]
        #expect(throws: ProjectError.self) { try edit.validated(duration: 10) }
        edit.zooms = [.init(range: .init(start: 1, end: 2)), .init(range: .init(start: 1.5, end: 3))]
        #expect(throws: ProjectError.self) { try edit.validated(duration: 10) }
    }
    @Test func focusUsesSourceTimeWithSmoothBoundedEdges() throws {
        var edit = VideoPlayback()
        edit.zooms = [.init(range: .init(start: 1, end: 3), scale: 3, centerX: 0.2, centerY: 0.7)]
        _ = try edit.validated(duration: 4)
        #expect(edit.focus(at: 0) == .identity && edit.focus(at: .nan) == .identity)
        #expect(edit.focus(at: 1).scale == 1 && edit.focus(at: 3).scale == 1)
        #expect(edit.focus(at: 2).scale == 3 && edit.focus(at: 2).centerX == 0.2)
        #expect(abs(edit.focus(at: 1.125).scale - 2) < 0.000001)
        #expect(edit.focus(at: 1.125) == edit.focus(at: 2.875))
    }
}

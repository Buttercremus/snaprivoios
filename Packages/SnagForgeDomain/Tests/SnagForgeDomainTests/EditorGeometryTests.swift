import Foundation
import CoreGraphics
import Testing
@testable import SnagForgeDomain

@Test func shapeConstraintsWorkInAllDrawingDirections() {
    let start = CGPoint(x: 100, y: 100)
    for kind in [EditorObject.Kind.rectangle, .ellipse] {
        for dx: CGFloat in [-80, 80] {
            for dy: CGFloat in [-35, 35] {
                let end = EditorGeometry.constrainedEnd(from: start, to: CGPoint(x: start.x + dx, y: start.y + dy), kind: kind)
                #expect(end == CGPoint(x: start.x + dx, y: start.y + (dy < 0 ? -80 : 80)))
            }
        }
    }
    #expect(EditorGeometry.constrainedEnd(from: start, to: start, kind: .ellipse) == start)
}

@Test func arrowConstraintPreservesLengthAndSnapsBothDirections() {
    let start = CGPoint(x: 150, y: 100)
    for vector in [CGPoint(x: 100, y: 10), CGPoint(x: 65, y: 80), CGPoint(x: -100, y: 10), CGPoint(x: 10, y: -100)] {
        let end = CGPoint(x: start.x + vector.x, y: start.y + vector.y)
        let constrained = EditorGeometry.constrainedEnd(from: start, to: end, kind: .arrow)
        let dx = constrained.x - start.x, dy = constrained.y - start.y
        #expect(abs(hypot(dx, dy) - hypot(vector.x, vector.y)) < 0.0001)
        let angle = atan2(dy, dx) / (.pi / 4)
        #expect(abs(angle - angle.rounded()) < 0.0001)
    }
}

@Test func allResizeHandlesKeepTheOppositeAnchorAndIgnoreGrabOffset() {
    let rect = CGRect(x: 20, y: 30, width: 100, height: 60)
    for handle in EditorResizeHandle.allCases {
        let next = EditorGeometry.resized(rect, handle: handle, delta: CGSize(width: 17, height: -9), minimum: CGSize(width: 4, height: 4))
        if handle.movesLeft { #expect(next.maxX == rect.maxX && next.minX == rect.minX + 17) }
        if handle.movesRight { #expect(next.minX == rect.minX && next.maxX == rect.maxX + 17) }
        if handle.movesTop { #expect(next.maxY == rect.maxY && next.minY == rect.minY - 9) }
        if handle.movesBottom { #expect(next.minY == rect.minY && next.maxY == rect.maxY - 9) }
        if !handle.movesLeft && !handle.movesRight { #expect(next.minX == rect.minX && next.width == rect.width) }
        if !handle.movesTop && !handle.movesBottom { #expect(next.minY == rect.minY && next.height == rect.height) }
        #expect(EditorGeometry.resized(rect, handle: handle, delta: .zero, minimum: CGSize(width: 4, height: 4), aspectRatio: 1) == rect)
    }
}

@Test func constrainedResizeUsesOppositeCornerOrSideCentreAndCannotInvert() {
    let rect = CGRect(x: 20, y: 30, width: 100, height: 60)
    for handle in EditorResizeHandle.allCases {
        let square = EditorGeometry.resized(rect, handle: handle, delta: CGSize(width: 18, height: 9), minimum: CGSize(width: 4, height: 4), aspectRatio: 1)
        #expect(square.width == square.height)
        if handle.movesLeft { #expect(square.maxX == rect.maxX) }
        if handle.movesRight { #expect(square.minX == rect.minX) }
        if handle.movesTop { #expect(square.maxY == rect.maxY) }
        if handle.movesBottom { #expect(square.minY == rect.minY) }
        if !handle.isCorner {
            if handle.movesLeft || handle.movesRight { #expect(square.midY == rect.midY) }
            else { #expect(square.midX == rect.midX) }
        }
        let tiny = EditorGeometry.resized(rect, handle: handle,
            delta: CGSize(width: handle.movesLeft ? 1000 : -1000, height: handle.movesTop ? 1000 : -1000),
            minimum: CGSize(width: 4, height: 4))
        #expect(tiny.width >= 4 && tiny.height >= 4)
    }
    let square = CGRect(x: 20, y: 30, width: 100, height: 100)
    #expect(EditorGeometry.resized(square, handle: .bottomRight, delta: CGSize(width: -25, height: 0),
        minimum: CGSize(width: 4, height: 4), aspectRatio: 1) == CGRect(x: 20, y: 30, width: 75, height: 75))
    #expect(EditorGeometry.resized(square, handle: .topLeft, delta: CGSize(width: 0, height: 25),
        minimum: CGSize(width: 4, height: 4), aspectRatio: 1) == CGRect(x: 45, y: 55, width: 75, height: 75))
}

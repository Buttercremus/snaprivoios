import Foundation
import CoreGraphics
import Testing
@testable import SnagForgeDomain

@Test func convertsDisplayAboveAndLeftOfPrimary() {
    let screen = CGRect(x: -1920, y: 1080, width: 1920, height: 1080)
    let selection = CGRect(x: -1820, y: 1880, width: 300, height: 200)
    #expect(CaptureGeometry.sourceRect(selection: selection, screen: screen, scale: 2)
        == CGRect(x: 100, y: 80, width: 300, height: 200))
    #expect(CaptureGeometry.quartzPoint(fromAppKit: CGPoint(x: -100, y: 2000), primaryHeight: 1080)
        == CGPoint(x: -100, y: -920))
}

@Test func windowConversionUsesPrimaryOriginRatherThanUnionOfDisplays() {
    #expect(CaptureGeometry.appKitRect(fromQuartz: CGRect(x: -800, y: -900, width: 600, height: 400), primaryHeight: 1080)
        == CGRect(x: -800, y: 1580, width: 600, height: 400))
}

@Test func reverseDragIsClampedToStartingDisplay() {
    #expect(CaptureGeometry.selection(from: CGPoint(x: 300, y: 200), to: CGPoint(x: -30, y: -10),
        within: CGRect(x: 0, y: 0, width: 1000, height: 800)) == CGRect(x: 0, y: 0, width: 300, height: 200))
}

@Test func alignsRetinaCropOutwards() {
    let rect = CaptureGeometry.sourceRect(selection: CGRect(x: 10.2, y: 20.2, width: 30.2, height: 40.2),
        screen: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
    #expect(rect == CGRect(x: 10, y: 39.5, width: 30.5, height: 40.5))
}

@Test func rejectsTinyOrOffscreenSelections() {
    let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
    #expect(CaptureGeometry.sourceRect(selection: CGRect(x: 0, y: 0, width: 1, height: 10), screen: screen, scale: 2) == nil)
    #expect(CaptureGeometry.sourceRect(selection: CGRect(x: 200, y: 0, width: 10, height: 10), screen: screen, scale: 2) == nil)
}

@Test func automaticCaptureDistinguishesClickJitterFromDragging() {
    #expect(CaptureConfiguration().source == .automatic)
    #expect(!CaptureGeometry.isSelectionDrag(from: CGPoint(x: -100, y: 50), to: CGPoint(x: -98, y: 52)))
    #expect(CaptureGeometry.isSelectionDrag(from: CGPoint(x: -100, y: 50), to: CGPoint(x: -104, y: 50)))
    #expect(CaptureGeometry.isSelectionDrag(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 70, y: 10)))
}

@Test func movingSelectionPreservesSizeAndStaysOnStartingScreen() {
    let screen = CGRect(x: -1000, y: 1080, width: 1000, height: 800)
    let draft = CaptureSelectionDraft(rect: CGRect(x: -800, y: 1200, width: 300, height: 200), windowID: 42)
    #expect(draft.moving(by: .zero, within: screen).windowID == 42)
    let moved = draft.moving(by: CGSize(width: 2000, height: -1000), within: screen)
    #expect(moved.rect == CGRect(x: -300, y: 1080, width: 300, height: 200))
    #expect(moved.windowID == nil)
    #expect(draft.windowID == 42)
}

@Test func resizingSelectionKeepsOppositeEdgesAndClearsWindowIdentity() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let draft = CaptureSelectionDraft(rect: CGRect(x: 100, y: 200, width: 300, height: 200), windowID: 42)
    let resized = draft.resizing(.topLeft, by: CGSize(width: -50, height: 80), within: screen)
    #expect(resized.rect == CGRect(x: 50, y: 200, width: 350, height: 280))
    #expect(resized.windowID == nil)
    #expect(draft.resizing(.topLeft, by: .zero, within: screen).windowID == 42)
    #expect(draft.resizing(.bottomRight, by: CGSize(width: 2000, height: -2000), within: screen).rect
        == CGRect(x: 100, y: 0, width: 900, height: 400))
}

@Test func everyResizeHandlePreventsInversionAndTinySelections() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let draft = CaptureSelectionDraft(rect: CGRect(x: 100, y: 200, width: 300, height: 200))
    for handle in CaptureSelectionHandle.allCases {
        for delta in [CGSize(width: 2000, height: 2000), CGSize(width: -2000, height: -2000)] {
            let rect = draft.resizing(handle, by: delta, within: screen).rect
            #expect(rect.width >= 2 && rect.height >= 2)
            #expect(screen.contains(rect))
            #expect(CaptureGeometry.sourceRect(selection: rect, screen: screen, scale: 2) != nil)
        }
    }
}

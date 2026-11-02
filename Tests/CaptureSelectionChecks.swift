import AppKit
import SnagForgeDomain

/// Offscreen view-handler checks, never input injection into another application.
@main
struct CaptureSelectionChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let window = SelectionPanel(screenFrame: CGRect(x: -800, y: 100, width: 800, height: 600))
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = view
        view.screenFrame = window.frame
        checkHoverMotion()
        checkFastGestureCursor()
        precondition(window.animationBehavior == .none, "Desktop snapshot must not zoom when ordered in/out")
        precondition(window.styleMask.contains(.nonactivatingPanel) && window.canBecomeKey && !window.canBecomeMain,
                     "Selection must accept keyboard focus without activating the app")
        precondition(window.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]),
                     "Selection must join the current desktop / full-screen Space / Stage Manager set")
        precondition(window.isOpaque && view.isOpaque && !window.ignoresMouseEvents,
                     "Selection must cover the desktop and receive mouse input")
        precondition(!window.isMovable && !view.mouseDownCanMoveWindow, "Overlay can steal capture drags for window movement")
        // Asymmetric Retina desktop: red top half, blue bottom half. A transparent
        // strip also checks that the view never leaves a click-through hole.
        let context = CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 20, y: 600, width: 1580, height: 600))
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 20, y: 0, width: 1580, height: 600))
        let frozen = FrozenDisplay(displayID: 17, screenFrame: window.frame, image: context.makeImage()!)
        view.frozenImage = frozen.image
        view.pixelScale = frozen.scale
        let desktop = FrozenDesktop(displays: [frozen])
        let windowDraft = CaptureSelectionDraft(rect: CGRect(x: -700, y: 200, width: 400, height: 300), windowID: 42)
        let windowVideo = ScreenshotSelection(displayID: 17, draft: windowDraft, screenFrame: window.frame, media: .video)
        precondition(windowVideo.windowID == 42 && windowVideo.videoSource == .window)
        let windowImage = ScreenshotSelection(displayID: 17, draft: windowDraft, screenFrame: window.frame, media: .image)
        precondition(windowImage.windowID == nil && windowImage.rect == windowDraft.rect, "Screenshot unexpectedly became a live window source")
        let adjustedVideo = ScreenshotSelection(displayID: 17, draft: windowDraft.moving(by: CGSize(width: 20, height: 0), within: window.frame), screenFrame: window.frame, media: .video)
        precondition(adjustedVideo.windowID == nil && adjustedVideo.videoSource == .region, "Adjusted window frame still captured the entire window")
        precondition(ScreenshotSelection(displayID: 17, rect: window.frame, screenFrame: window.frame).videoSource == .display)
        let topCrop = try desktop.crop(ScreenshotSelection(displayID: 17, rect: CGRect(x: -700, y: 500, width: 160, height: 100), screenFrame: window.frame))
        precondition(topCrop.width == 320 && topCrop.height == 200, "Frozen crop lost Retina resolution")
        let fractionalCrop = try frozen.crop(CGRect(x: -699.75, y: 500.25, width: 10.25, height: 20.25))
        precondition(fractionalCrop.width == 21 && fractionalCrop.height == 41, "Frozen crop did not round outwards to image pixels")
        let clippedCrop = try frozen.crop(CGRect(x: -805, y: 95, width: 20, height: 20))
        precondition(clippedCrop.width == 30 && clippedCrop.height == 30, "Frozen crop escaped the display bounds")
        precondition(NSBitmapImageRep(cgImage: topCrop).colorAt(x: 30, y: 30)!.usingColorSpace(.deviceRGB)!.redComponent > 0.9,
                     "Frozen crop is vertically flipped")
        context.setFillColor(NSColor.green.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        let bottomCrop = try frozen.crop(CGRect(x: -600, y: 160, width: 100, height: 100))
        precondition(NSBitmapImageRep(cgImage: bottomCrop).colorAt(x: 30, y: 30)!.usingColorSpace(.deviceRGB)!.blueComponent > 0.9,
                     "Final output changed after the desktop was frozen")
        do {
            _ = try desktop.crop(ScreenshotSelection(displayID: 18, rect: window.frame, screenFrame: window.frame))
            preconditionFailure("Unknown display accepted")
        } catch ScreenshotError.invalidRegion { }
        do {
            _ = try desktop.crop(ScreenshotSelection(displayID: 17, rect: window.frame, screenFrame: window.frame.offsetBy(dx: 1, dy: 0)))
            preconditionFailure("Changed display geometry accepted")
        } catch ScreenshotError.invalidRegion { }
        func checkOpaqueFrozenPixels() {
            let bitmap = renderSelectionMask(view)
            for x in stride(from: 2, to: bitmap.pixelsWide, by: 41) {
                for y in stride(from: 2, to: bitmap.pixelsHigh, by: 43) {
                    precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.99, "Transparent hole in the selection surface")
                }
            }
            let top = bitmap.colorAt(x: bitmap.pixelsWide / 3, y: bitmap.pixelsHigh / 5)!.usingColorSpace(.deviceRGB)!
            let bottom = bitmap.colorAt(x: bitmap.pixelsWide / 3, y: bitmap.pixelsHigh * 4 / 5)!.usingColorSpace(.deviceRGB)!
            precondition(top.redComponent > 0.45 && bottom.blueComponent > 0.45, "Overlay did not paint the frozen desktop upright")
            precondition(view.hitTest(CGPoint(x: 200, y: 380)) === view, "Window titlebar area did not hit the selector")
        }
        checkOpaqueFrozenPixels()
        // Background windows remain candidates, but front-to-back order owns
        // overlapping pixels. Eligibility and current CG bounds are independent
        // of the owning application's foreground status / SCK enumeration order.
        func entry(_ id: UInt32, _ frame: CGRect, pid: Int32 = 77, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowBounds as String: frame.dictionaryRepresentation,
             kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha]
        }
        let frontFrame = CGRect(x: 200, y: 150, width: 300, height: 250)
        let backFrame = CGRect(x: 50, y: 50, width: 700, height: 500)
        let entries = [entry(1, frontFrame), entry(2, backFrame, pid: 88), entry(3, backFrame),
                       entry(4, backFrame, pid: 999), entry(5, backFrame, layer: 3), entry(6, backFrame, alpha: 0),
                       entry(7, CGRect(x: 0, y: 0, width: 1, height: 100))]
        let regions = ScreenshotService.windowRegions(in: entries, eligibleIDs: [1, 2, 4, 5, 6, 7, 8], excludingPID: 999)
        precondition(regions == [CaptureWindowRegion(id: 1, frame: frontFrame), CaptureWindowRegion(id: 2, frame: backFrame)],
                     "Background geometry, front-to-back order or window eligibility was lost")
        precondition(regions.first { $0.frame.contains(CGPoint(x: 100, y: 100)) }?.id == 2, "Exposed background window cannot be targeted")
        precondition(regions.first { $0.frame.contains(CGPoint(x: 250, y: 200)) }?.id == 1, "Hidden background pixels won over the foreground window")
        precondition(!regions.contains { $0.id == 8 }, "Off-desktop SCK window entered the on-screen candidate list")

        func blue(at localPoint: CGPoint) -> CGFloat {
            let bitmap = renderSelectionMask(view)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            return bitmap.colorAt(x: Int(localPoint.x * scale), y: bitmap.pixelsHigh - 1 - Int(localPoint.y * scale))!.usingColorSpace(.deviceRGB)!.blueComponent
        }
        let highlighted = CGRect(x: -700, y: 200, width: 400, height: 300)
        view.highlight = highlighted
        let hoverOutside = blue(at: CGPoint(x: 650, y: 200))
        precondition(blue(at: CGPoint(x: 250, y: 200)) > 0.95 && hoverOutside > 0.5 && hoverOutside < 0.65,
                     "Hover must leave the selected pixels bright and clearly dim the surroundings")
        view.isReviewing = true; view.reviewDraft = CaptureSelectionDraft(rect: highlighted)
        let selectedBlue = blue(at: CGPoint(x: 250, y: 200)), reviewOutside = blue(at: CGPoint(x: 650, y: 200))
        precondition(selectedBlue > 0.95 && abs(reviewOutside - hoverOutside) < 0.01,
                     "Shade changed or selection darkened after the window click (selected=\(selectedBlue), hover=\(hoverOutside), review=\(reviewOutside))")
        let gripBitmap = renderSelectionMask(view)
        let gripScale = CGFloat(gripBitmap.pixelsWide) / view.bounds.width
        func isWhiteGrip(at point: CGPoint) -> Bool {
            let color = gripBitmap.colorAt(x: Int(point.x * gripScale),
                y: gripBitmap.pixelsHigh - 1 - Int(point.y * gripScale))!.usingColorSpace(.deviceRGB)!
            return color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95
        }
        let localSelection = highlighted.offsetBy(dx: -view.screenFrame.minX, dy: -view.screenFrame.minY)
        for handle in CaptureSelectionHandle.allCases {
            let point = handle.point(in: localSelection)
            precondition(isWhiteGrip(at: point), "Capture grip is no longer visibly white")
            if handle == .top || handle == .bottom {
                precondition(isWhiteGrip(at: CGPoint(x: point.x + 8, y: point.y)), "Horizontal grip is not a visible pill")
            } else if handle == .left || handle == .right {
                precondition(isWhiteGrip(at: CGPoint(x: point.x, y: point.y + 8)), "Vertical grip is not a visible pill")
            }
        }
        try gripBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/Snaprivo-CaptureGrips.png"))
        view.preparePresentation()
        precondition(abs(blue(at: CGPoint(x: 650, y: 200)) - reviewOutside) < 0.01,
                     "Initial selection waited for a chrome fade")
        NSAnimationContext.runAnimationGroup({ context in context.duration = 0; view.setChromeVisible(false) }, completionHandler: nil)
        precondition(blue(at: CGPoint(x: 650, y: 200)) > 0.95, "Hiding capture chrome also faded the frozen desktop")
        NSAnimationContext.runAnimationGroup({ context in context.duration = 0; view.setChromeVisible(true) }, completionHandler: nil)
        view.isReviewing = false; view.reviewDraft = nil; view.highlight = nil
        let cursor = view.selectionCursor(at: CGPoint(x: 400, y: 300))
        precondition(cursor.image.size == CGSize(width: 40, height: 40) && cursor.hotSpot == CGPoint(x: 20, y: 20),
                     "Capture cursor lost its larger hit-point-centered crosshair")
        var proposals = 0, captures = 0, restarts = 0, cancellations = 0
        var lastCapture: CaptureSelectionDraft?
        view.onPropose = { rect in
            proposals += 1
            view.isReviewing = true
            view.reviewDraft = CaptureSelectionDraft(rect: rect ?? CGRect(x: -700, y: 200, width: 400, height: 300),
                                                     windowID: rect == nil ? 42 : nil)
        }
        view.onConfirm = { captures += 1; lastCapture = $0 }
        view.onRestart = { restarts += 1; view.isReviewing = false; view.reviewDraft = nil }
        view.onCancel = { cancellations += 1 }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // Simulate a system cursor reset at the menu bar / Dock, without a
        // tracking-area transition. Moving across the frozen surface restores it.
        for point in [CGPoint(x: 400, y: 599), CGPoint(x: 400, y: 1), CGPoint(x: 400, y: 300)] {
            NSCursor.arrow.set()
            view.mouseMoved(with: event(.mouseMoved, point.x, point.y))
            precondition(NSCursor.current === view.selectionCursor(at: point), "System cursor reset survived capture movement")
        }
        NSCursor.arrow.set()
        view.mouseEntered(with: event(.mouseMoved, 400, 300))
        precondition(NSCursor.current === view.selectionCursor(at: CGPoint(x: 400, y: 300)), "Reentering capture did not restore the crosshair")
        // A click chooses the detected window, without taking a screenshot yet.
        view.mouseDown(with: event(.leftMouseDown, 200, 200))
        view.mouseUp(with: event(.leftMouseUp, 202, 202))
        precondition(proposals == 1 && captures == 0 && view.reviewDraft?.windowID == 42)
        checkOpaqueFrozenPixels()
        precondition(view.selectionCursor(at: CGPoint(x: 200, y: 380)) !== NSCursor.arrow,
                     "Capture area changed to the underlying titlebar's arrow cursor")
        precondition(view.selectionCursor(at: CGPoint(x: 100, y: 200)) === NSCursor.openHand,
                     "Selection border lost its move cursor")
        let toolbar = view.subviews.first { $0.accessibilityIdentifier() == "capture.reviewToolbar" }!
        precondition(view.selectionCursor(at: CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY)) === NSCursor.arrow,
                     "Native confirmation buttons should use the arrow cursor")
        view.mouseMoved(with: event(.mouseMoved, toolbar.frame.midX, toolbar.frame.midY))
        precondition(NSCursor.current === NSCursor.arrow, "Confirmation toolbar cursor was overwritten")
        view.mouseMoved(with: event(.mouseMoved, 200, 380))
        precondition(NSCursor.current === view.selectionCursor(at: CGPoint(x: 200, y: 380)), "Leaving the toolbar lost the crosshair")
        let buttons = (toolbar as! CaptureReviewToolbar).actionButtons
        precondition(buttons.count == 8, "Missing native confirmation controls/photo/source choices")
        toolbar.layoutSubtreeIfNeeded()
        for button in buttons {
            precondition(toolbar.bounds.contains(button.convert(button.bounds, to: toolbar)), "Compact capture control is clipped")
        }
        precondition(view.bounds.contains(toolbar.frame), "Controls outside the display")
        // The pixel size itself opens the exact-size editor; there is no separate gear for it.
        let reviewToolbar = toolbar as! CaptureReviewToolbar
        let sizeButton = buttons.first { $0.accessibilityIdentifier() == "capture.size" }!
        precondition(buttons.allSatisfy { $0.accessibilityIdentifier() != "capture.settings" } && sizeButton.title.contains("×")
                     && sizeButton.accessibilityValue() as? String == sizeButton.title, "The selection size is not its own control")
        let showSize = reviewToolbar.onEditSize
        var sizeEdits = 0
        reviewToolbar.onEditSize = { button in sizeEdits += 1; precondition(button === sizeButton) }
        sizeButton.performClick(nil); precondition(sizeEdits == 1, "Clicking the size did not open its editor")
        reviewToolbar.onEditSize = showSize
        // Moving the frame is live and becomes a crop, with no capture on release.
        view.mouseDown(with: event(.leftMouseDown, 100, 200))
        view.mouseDragged(with: event(.leftMouseDragged, 150, 230))
        precondition(view.reviewDraft?.rect.origin == CGPoint(x: -650, y: 230))
        precondition(view.reviewDraft?.windowID == nil && captures == 0)
        view.mouseUp(with: event(.leftMouseUp, 150, 230))
        precondition(captures == 0)
        // Resize the top-right grip, then invoke the actual native capture button.
        view.mouseDown(with: event(.leftMouseDown, 550, 430))
        view.mouseDragged(with: event(.leftMouseDragged, 650, 480))
        precondition(view.reviewDraft?.rect.size == CGSize(width: 500, height: 350))
        view.mouseUp(with: event(.leftMouseUp, 650, 480))
        let adjusted = view.reviewDraft!
        for handle in CaptureSelectionHandle.allCases {
            view.reviewDraft = adjusted
            let rect = adjusted.rect.offsetBy(dx: -view.screenFrame.minX, dy: -view.screenFrame.minY)
            var point = handle.point(in: rect)
            switch handle {
            case .top, .bottom: point.x += 9
            case .left, .right: point.y += 9
            default: point.x += point.x == rect.minX ? -8 : 8; point.y += point.y == rect.minY ? -8 : 8
            }
            view.mouseDown(with: event(.leftMouseDown, point.x, point.y))
            view.mouseDragged(with: event(.leftMouseDragged, point.x + 10, point.y + 10))
            view.mouseUp(with: event(.leftMouseUp, point.x + 10, point.y + 10))
            precondition(view.reviewDraft == adjusted.resizing(handle, by: CGSize(width: 10, height: 10), within: view.screenFrame),
                         "Expanded grip hit area picked the wrong handle or started a new selection")
        }
        let tiny = CaptureSelectionDraft(rect: CGRect(x: -200, y: 400, width: 14, height: 18))
        view.reviewDraft = tiny
        let tinyRight = CaptureSelectionHandle.right.point(in: tiny.rect.offsetBy(dx: -view.screenFrame.minX, dy: -view.screenFrame.minY))
        view.mouseDown(with: event(.leftMouseDown, tinyRight.x, tinyRight.y))
        view.mouseDragged(with: event(.leftMouseDragged, tinyRight.x + 30, tinyRight.y))
        view.mouseUp(with: event(.leftMouseUp, tinyRight.x + 30, tinyRight.y))
        precondition(view.reviewDraft == tiny.resizing(.right, by: CGSize(width: 30, height: 0), within: view.screenFrame),
                     "Overlapping grip hit areas must choose the nearest handle")
        view.reviewDraft = adjusted
        buttons.first { $0.accessibilityIdentifier() == "capture.confirm" }!.performClick(nil)
        precondition(captures == 1 && lastCapture == view.reviewDraft, "Capture lost adjusted geometry")
        buttons.first { $0.accessibilityIdentifier() == "capture.restart" }!.performClick(nil)
        precondition(restarts == 1 && view.reviewDraft == nil && view.subviews.allSatisfy { $0.accessibilityIdentifier() != "capture.reviewToolbar" })
        // AppKit can coalesce movement. The release location must still distinguish
        // a free region from a window click, even without an intermediate drag.
        view.mouseDown(with: event(.leftMouseDown, 150, 120))
        view.mouseUp(with: event(.leftMouseUp, 370, 280))
        precondition(view.reviewDraft?.windowID == nil, "Release displacement was mistaken for a window click")
        precondition(view.reviewDraft?.rect == CGRect(x: -650, y: 220, width: 220, height: 160))
        view.onRestart?()
        // A free drag overrides the hovered window and paints before release.
        let detectedWindow = CGRect(x: -700, y: 200, width: 400, height: 300)
        view.onHover = { _ in view.highlight = detectedWindow }
        view.mouseDown(with: event(.leftMouseDown, 500, 400))
        view.mouseDragged(with: event(.leftMouseDragged, 120, 110))
        let liveRect = CGRect(x: -680, y: 210, width: 380, height: 290)
        precondition(view.highlight == liveRect && view.isSelectingRegion)
        view.mouseMoved(with: event(.mouseMoved, 300, 200))
        precondition(view.highlight == liveRect, "Hover detection replaced a live region with a window")
        precondition(proposals == 2 && captures == 1)
        // Returning near the origin must shrink the live frame, not leave it stuck.
        view.mouseDragged(with: event(.leftMouseDragged, 498, 398))
        precondition(view.highlight?.size == CGSize(width: 2, height: 2), "Reverse drag left a stale preview")
        view.mouseDragged(with: event(.leftMouseDragged, 200, 150))
        view.mouseUp(with: event(.leftMouseUp, 200, 150))
        precondition(proposals == 3 && captures == 1 && view.reviewDraft?.windowID == nil)
        precondition(view.reviewDraft?.rect == CGRect(x: -600, y: 250, width: 300, height: 250))
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: "\r",
                                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        view.keyDown(with: enter)
        precondition(captures == 2)
        view.cancelOperation(nil)
        precondition(cancellations == 1 && captures == 2)
        // A second drag INSIDE a selected window creates a free region rather
        // than trapping the user in whole-window movement.
        view.onRestart?()
        view.mouseDown(with: event(.leftMouseDown, 200, 200))
        view.mouseUp(with: event(.leftMouseUp, 200, 200))
        precondition(view.reviewDraft?.windowID == 42)
        view.mouseDown(with: event(.leftMouseDown, 180, 180))
        view.mouseDragged(with: event(.leftMouseDragged, 310, 270))
        precondition(view.reviewDraft == nil && view.highlight?.size == CGSize(width: 130, height: 90))
        view.mouseUp(with: event(.leftMouseUp, 310, 270))
        precondition(view.reviewDraft?.rect == CGRect(x: -620, y: 280, width: 130, height: 90))
        precondition(view.reviewDraft?.windowID == nil && captures == 2)
        precondition(window.frame == view.screenFrame, "Capture gesture moved the overlay panel")
        // Immediate capture: releasing a region or clicking a window confirms at once; ⌥ keeps the bar, video always does.
        var immediate: [CaptureSelectionDraft] = []
        view.onConfirm = { immediate.append($0) }
        view.onRestart?(); view.confirmsImmediately = true
        view.mouseDown(with: event(.leftMouseDown, 150, 120))
        view.mouseDragged(with: event(.leftMouseDragged, 370, 280))
        precondition(view.caption.contains(String(localized: "Loslassen: Aufnehmen")), "The release hint still promised a review")
        view.mouseUp(with: event(.leftMouseUp, 370, 280))
        precondition(immediate.map(\.rect) == [CGRect(x: -650, y: 220, width: 220, height: 160)], "Releasing a region did not capture at once")
        view.onRestart?()
        view.mouseDown(with: event(.leftMouseDown, 200, 200)); view.mouseUp(with: event(.leftMouseUp, 200, 200))
        precondition(immediate.count == 2 && immediate[1].windowID == 42, "A window click did not capture at once")
        view.onRestart?()
        view.mouseDown(with: event(.leftMouseDown, 150, 120))
        view.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 370, y: 280), modifierFlags: .option, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        precondition(immediate.count == 2 && view.reviewDraft != nil
                     && view.subviews.contains { $0.accessibilityIdentifier() == "capture.reviewToolbar" }, "⌥ on release did not keep the bar")
        // Once the bar is shown, a further gesture adjusts or reselects instead of capturing.
        view.mouseDown(with: event(.leftMouseDown, 400, 300)); view.mouseUp(with: event(.leftMouseUp, 420, 320))
        precondition(immediate.count == 2, "A gesture while reviewing captured at once")
        view.onRestart?(); view.isVideo = true
        view.mouseDown(with: event(.leftMouseDown, 150, 120)); view.mouseUp(with: event(.leftMouseUp, 370, 280))
        precondition(immediate.count == 2 && view.reviewDraft != nil, "Video skipped its confirmation bar")
        view.onRestart?(); view.isVideo = false; view.confirmsImmediately = false
        view.onConfirm = { captures += 1; lastCapture = $0 }
        view.mouseDown(with: event(.leftMouseDown, 200, 200)); view.mouseUp(with: event(.leftMouseUp, 200, 200))
        // Former window-only entry points must also allow free drawing.
        view.onRestart?()
        view.mode = .window
        view.mouseDown(with: event(.leftMouseDown, 400, 300))
        view.mouseDragged(with: event(.leftMouseDragged, 650, 500))
        view.mouseUp(with: event(.leftMouseUp, 650, 500))
        precondition(view.reviewDraft?.windowID == nil && view.reviewDraft?.rect.size == CGSize(width: 250, height: 200))
        view.onRestart?(); view.isVideo = true
        view.mouseDown(with: event(.leftMouseDown, 200, 200)); view.mouseUp(with: event(.leftMouseUp, 200, 200))
        precondition(view.reviewDraft?.windowID == 42 && view.caption.contains("Fenster"))
        precondition(!view.caption.contains("neuer Bereich"), "Window selection was presented as a fixed region")
        let preservedDraft = view.reviewDraft!
        let actionToolbar = view.subviews.first { $0.accessibilityIdentifier() == "capture.reviewToolbar" }!
        precondition(!actionToolbar.subviews.contains { $0 is NSSegmentedControl })
        let photoButton = (actionToolbar as! CaptureReviewToolbar).actionButtons.first { $0.accessibilityIdentifier() == "capture.confirm" }!
        let videoButton = (actionToolbar as! CaptureReviewToolbar).actionButtons.first { $0.accessibilityIdentifier() == "capture.video" }!
        photoButton.performClick(nil)
        precondition(!view.isVideo && view.reviewDraft == preservedDraft && captures == 3,
                     "Photo must immediately confirm the existing selection")
        let imageSelection = ScreenshotSelection(displayID: 1, draft: preservedDraft, screenFrame: view.screenFrame, media: .image)
        precondition(imageSelection.media == .image && imageSelection.windowID == nil)
        videoButton.performClick(nil)
        let selectedVideo = ScreenshotSelection(displayID: 1, draft: preservedDraft, screenFrame: view.screenFrame, media: .video)
        precondition(view.isVideo && view.reviewDraft == preservedDraft && captures == 4)
        precondition(selectedVideo.media == .video && selectedVideo.windowID == 42)
        let videoDraft = view.reviewDraft!
        view.reviewDraft = videoDraft.moving(by: CGSize(width: 20, height: 0), within: view.screenFrame)
        precondition(view.reviewDraft?.windowID == nil && view.caption.contains("neuer Bereich"))
        view.onRestart?(); view.isVideo = false
        // Full-display selections keep controls onscreen and use the same review.
        view.onRestart?()
        view.mode = .display
        view.mouseDown(with: event(.leftMouseDown, 400, 300))
        view.mouseUp(with: event(.leftMouseUp, 400, 300))
        precondition(view.reviewDraft?.rect == window.frame && captures == 4)
        precondition(view.bounds.contains(view.subviews.first { $0.accessibilityIdentifier() == "capture.reviewToolbar" }!.frame))
        view.isFinishing = true
        view.confirm(); view.mouseDown(with: event(.leftMouseDown, 200, 200)); view.mouseUp(with: event(.leftMouseUp, 200, 200))
        precondition(captures == 4 && view.reviewDraft?.rect == window.frame, "Input changed the selection during dismissal")
        view.isFinishing = false
        view.reviewDraft = nil
        view.allowsVideoAction = false
        view.reviewDraft = preservedDraft
        let scrollToolbar = view.subviews.first { $0.accessibilityIdentifier() == "capture.reviewToolbar" }!
        precondition(!(scrollToolbar as! CaptureReviewToolbar).actionButtons.contains { $0.accessibilityIdentifier() == "capture.video" },
                     "Scroll capture must only offer the photo action")
        let choices = (scrollToolbar as! CaptureReviewToolbar).photoChoicesMenu()
        let captureCount = captures
        precondition((scrollToolbar as! CaptureReviewToolbar).actionButtons.contains { $0.accessibilityIdentifier() == "capture.photoChoices" })
        _ = NSApp.sendAction(choices.items[3].action!, to: choices.items[3].target, from: choices.items[3])
        precondition(view.isScrolling && !view.isVideo && captures == captureCount + 1 && view.reviewDraft == preservedDraft)
        let scrollSelection = ScreenshotSelection(displayID: 1, draft: preservedDraft, screenFrame: view.screenFrame, media: .image, isScrolling: view.isScrolling)
        precondition(scrollSelection.isScrolling && scrollSelection.windowID == nil && scrollSelection.rect == preservedDraft.rect)
        _ = NSApp.sendAction(choices.items[0].action!, to: choices.items[0].target, from: choices.items[0])
        precondition(!view.isScrolling && !view.isVideo && captures == captureCount + 2, "Photo choice kept the scrolling route")
        for (index, destination) in [(1, CaptureImageDestination.text), (2, .code)] {
            _ = NSApp.sendAction(choices.items[index].action!, to: choices.items[index].target, from: choices.items[index])
            precondition(view.imageDestination == destination && !view.isVideo && !view.isScrolling)
            let result = ScreenshotSelection(displayID: 1, draft: preservedDraft, screenFrame: view.screenFrame, media: .image, destination: view.imageDestination)
            precondition(result.destination == destination && result.rect == preservedDraft.rect)
        }
        let textToolbar = CaptureReviewToolbar(allowsVideoAction: false, allowsScrolling: false)
        textToolbar.setDestination(.text)
        precondition(textToolbar.actionButtons.first { $0.accessibilityIdentifier() == "capture.confirm" }?.title == String(localized: "Text"))
        precondition(textToolbar.photoChoicesMenu().items.count == 3, "Direct OCR must expose photo/text/code without video/scroll")
        precondition(ScreenshotSelection(displayID: 1, rect: preservedDraft.rect, screenFrame: view.screenFrame, media: .video, destination: .text).destination == .image)

        precondition(!ScreenshotSelection(displayID: 1, draft: preservedDraft, screenFrame: view.screenFrame, media: .video, isScrolling: true).isScrolling)
        checkExactSizeEditing()
        let screenMenu = (scrollToolbar as! CaptureReviewToolbar)
        screenMenu.screenChoices = [CaptureScreenChoice(id: 11, name: "Display A", frame: CGRect(x: -800, y: 0, width: 800, height: 600)),
                                    CaptureScreenChoice(id: 22, name: "Display B", frame: CGRect(x: 0, y: 600, width: 1200, height: 800))]
        screenMenu.selectedScreenID = 22
        var chosen: UInt32?
        screenMenu.onSelectScreen = { chosen = $0 }
        let displays = screenMenu.screenChoicesMenu()
        precondition(displays.items.count == 3 && displays.items[2].state == .on)
        _ = NSApp.sendAction(displays.items[1].action!, to: displays.items[1].target, from: displays.items[1])
        precondition(chosen == 11, "Display menu selected an index rather than the actual display ID")
        try await checkImmediatePhotoConfirmation()
        print("Capture selection checks passed: interruptible 180 ms window-hover motion, immediate target/click/drag/review, gap fades, reduced motion and display boundaries; round/pill white grips, expanded hit targets/all 8 resize directions and nearest small-selection handles; background-window ordering/current bounds/eligibility, consistent bright selection and shaded surroundings, chrome-only fading, larger centered cursor, dismissal input guard, nonzooming/nonactivating opaque overlay, immutable Retina crops, click/drag, adjustment, native controls, Enter and cancel.")
    }

    @MainActor private static func checkFastGestureCursor() {
        let panel = SelectionPanel(screenFrame: CGRect(x: -800, y: 100, width: 800, height: 600))
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        panel.contentView = view; view.screenFrame = panel.frame
        defer {
            view.onRestart = nil; view.onPropose = nil
            panel.contentView = nil; panel.close(); NSCursor.arrow.set()
        }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let crosshair = view.selectionCursor(at: CGPoint(x: 400, y: 300))
        view.onRestart = { view.isReviewing = false; view.reviewDraft = nil }
        view.onPropose = { rect in
            view.isReviewing = true; view.reviewDraft = rect.map { CaptureSelectionDraft(rect: $0) }
        }
        // Shortcut -> immediate press/drag: no mouseEntered/mouseMoved/cursorUpdate.
        for _ in 0..<16 {
            view.isReviewing = false; view.reviewDraft = nil
            NSCursor.arrow.set()
            view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 120, y: 130)))
            precondition(NSCursor.current === crosshair, "Fast capture press kept the previous application's arrow")
            NSCursor.arrow.set()
            view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 500, y: 450)))
            precondition(NSCursor.current === crosshair, "A system cursor reset survived capture dragging")
            view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 600, y: 470)))
            precondition(NSCursor.current === view.selectionCursor(at: CGPoint(x: 600, y: 470)), "Release did not restore the selection handle cursor")
        }
        view.reviewDraft = CaptureSelectionDraft(rect: CGRect(x: -700, y: 200, width: 350, height: 260))
        let corner = CGPoint(x: 100, y: 100), resize = view.selectionCursor(at: corner)
        NSCursor.arrow.set(); view.mouseDown(with: event(.leftMouseDown, corner))
        precondition(NSCursor.current === resize, "Fast resize press lost the handle cursor")
        let toolbar = view.subviews.first { $0.accessibilityIdentifier() == "capture.reviewToolbar" }!
        let toolbarPoint = CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY)
        view.cursorUpdate(with: event(.mouseMoved, toolbarPoint))
        precondition(NSCursor.current === resize, "A toolbar cursor update interrupted the active resize")
        NSCursor.arrow.set(); view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 150, y: 150)))
        precondition(NSCursor.current === resize)
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 150, y: 150)))
        view.reviewDraft = CaptureSelectionDraft(rect: CGRect(x: -700, y: 200, width: 350, height: 260))
        let edge = CGPoint(x: 100, y: 200)
        NSCursor.arrow.set(); view.mouseDown(with: event(.leftMouseDown, edge))
        precondition(NSCursor.current === NSCursor.openHand, "Frame movement lost its hand cursor")
        NSCursor.arrow.set(); view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 150, y: 230)))
        precondition(NSCursor.current === NSCursor.openHand)
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 150, y: 230)))
        view.prepareForLiveCapture()
        NSCursor.arrow.set(); view.cursorUpdate(with: event(.mouseMoved, CGPoint(x: 400, y: 300)))
        precondition(NSCursor.current === NSCursor.arrow, "Live/pass-through capture restored the selection cursor")
        print("Fast capture cursor checks passed: immediate press/drag without movement, 16 repeated resets, release, resize/move cursor ownership and live-overlay handoff.")
    }

    @MainActor private static func checkImmediatePhotoConfirmation() async throws {
        let pixel = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let desktop = FrozenDesktop(displays: NSScreen.screens.map {
            FrozenDisplay(displayID: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32,
                          screenFrame: $0.frame, image: pixel)
        })
        let selector = ScreenshotSelector()
        let primaryHeight = NSScreen.screens.first!.frame.height
        let windows = desktop.displays.enumerated().map { index, display in
            CapturableWindow(id: UInt32(index + 1), processID: 77, applicationName: "Synthetic",
                frame: CaptureGeometry.appKitRect(fromQuartz: display.screenFrame, primaryHeight: primaryHeight))
        }
        NSCursor.arrow.set()
        let selected = Task { try await selector.select(source: .automatic, windows: windows, desktop: desktop) }
        var panels: [NSWindow] = []
        for _ in 0..<100 {
            panels = NSApp.windows.filter { ($0.contentView as? SelectionView)?.frozenImage === pixel && $0.isVisible }
            if panels.count == desktop.displays.count { break }
            await Task.yield()
        }
        precondition(!panels.isEmpty && panels.count == desktop.displays.count)
        let active = panels.first { $0.frame.contains(NSEvent.mouseLocation) }!
        let activeView = active.contentView as! SelectionView
        let firstFrame = activeView.hoverPresentation()
        precondition(firstFrame.rect == activeView.screenFrame && firstFrame.visibility == 1,
                     "Initial window frame was still fading or moving after the panel appeared")
        let firstPixels = renderSelectionMask(activeView)
        let edge = firstPixels.colorAt(x: firstPixels.pixelsWide / 2, y: 1)!.usingColorSpace(.deviceRGB)!
        precondition(max(edge.redComponent, edge.greenComponent, edge.blueComponent) > 0.1,
                     "The first displayed snapshot was missing its selection border")
        let point = activeView.convert(active.mouseLocationOutsideOfEventStream, from: nil)
        precondition(NSCursor.current === activeView.selectionCursor(at: point), "Opening the selector waited for a mouse movement to set its cursor")
        NSCursor.arrow.set(); active.resignKey(); active.makeKey()
        precondition(NSCursor.current === activeView.selectionCursor(at: point), "Focus handoff did not restore the capture cursor")
        let view = panels[0].contentView as! SelectionView
        let draft = CaptureSelectionDraft(rect: view.screenFrame.insetBy(dx: 40, dy: 40))
        view.onConfirm?(draft)
        precondition(panels.allSatisfy { !$0.isVisible }, "Confirmed photo waited for the exit animation before opening")
        view.onConfirm?(draft) // A repeated event must not resume the continuation twice.
        let result = try await selected.value
        precondition(result?.rect == draft.rect && result?.media == .image)
        selector.cancel()
        NSCursor.arrow.set(); activeView.refreshCursorAtMouseLocation()
        precondition(NSCursor.current === NSCursor.arrow, "A deferred cursor refresh outlived the closed selector")
        print("Photo confirmation closes all synthetic desktop panels immediately and completes exactly once.")
    }

    @MainActor private static func checkExactSizeEditing() {
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.screenFrame = CGRect(x: -800, y: 100, width: 800, height: 600); view.pixelScale = 2
        view.isReviewing = true
        view.reviewDraft = CaptureSelectionDraft(rect: CGRect(x: -699.75, y: 200.25, width: 200.5, height: 200.5), windowID: 42)
        view.resizeSelection(to: CGSize(width: 501, height: 303))
        let rect = view.reviewDraft!.rect
        precondition(rect == CGRect(x: -700, y: 249.5, width: 250.5, height: 151.5) && view.reviewDraft?.windowID == nil)
        let source = CaptureGeometry.sourceRect(selection: rect, screen: view.screenFrame, scale: 2)!
        precondition(source.width * 2 == 501 && source.height * 2 == 303, "Entered pixels differ from the captured Retina crop")
        view.resizeSelection(to: CGSize(width: 1e9, height: 1e9))
        precondition(view.reviewDraft?.rect == CGRect(x: -700, y: 100, width: 700, height: 301))
        let bounded = view.reviewDraft!
        view.resizeSelection(to: CGSize(width: CGFloat.infinity, height: 100))
        precondition(view.reviewDraft == bounded, "Invalid numeric size damaged the selection")
        view.resizeSelection(to: .zero)
        precondition(view.reviewDraft?.rect.size == CGSize(width: 2, height: 2))
        view.reviewDraft = CaptureSelectionDraft(rect: CGRect(x: -700, y: 200, width: 300, height: 200), windowID: 42)
        view.resizeSelection(to: CGSize(width: 600, height: 400))
        precondition(view.reviewDraft?.windowID == 42, "Applying unchanged size discarded the video window source")
        view.pixelScale = 1; view.resizeSelection(to: CGSize(width: 123, height: 77))
        precondition(view.reviewDraft?.rect.size == CGSize(width: 123, height: 77))
        print("Capture size/display controls passed: exact 1x/2x pixel dimensions, fractional/negative origin, bounds/minimum/invalid input, window identity and display-ID routing.")
    }

    @MainActor private static func checkHoverMotion() {
        let display = CGRect(x: -800, y: 100, width: 800, height: 600)
        let a = CGRect(x: -750, y: 140, width: 300, height: 220)
        let b = CGRect(x: -440, y: 220, width: 400, height: 380)
        let c = CGRect(x: -680, y: 180, width: 250, height: 180)
        var motion = CaptureHoverHighlight()
        motion.setTarget(a, within: display, at: 1, animated: false)
        motion.setTarget(b, within: display, at: 2, animated: true)
        precondition(motion.target == b && motion.presentation(at: 2).rect == a,
                     "Hit target must change immediately while the visible frame starts at its current position")
        let halfway = motion.presentation(at: 2.09)
        precondition(halfway.rect!.minX > a.minX && halfway.rect!.minX < b.minX && halfway.visibility == 1)
        precondition(halfway.rect!.width > a.width && halfway.rect!.width < b.width,
                     "Window size must glide together with its position")
        let earlyDistance = motion.presentation(at: 2.045).rect!.minX - a.minX
        let lateDistance = b.minX - motion.presentation(at: 2.135).rect!.minX
        precondition(earlyDistance > lateDistance, "Hover should respond immediately and ease to a stop")
        precondition(!motion.setTarget(b, within: display, at: 2.05, animated: true),
                     "Movement within one window restarted the animation")
        precondition(motion.presentation(at: 2.181).rect == b, "Window hover did not settle within 180 ms")

        // Fast A → B → C movement continues from the in-flight rectangle.
        let interrupted = motion.presentation(at: 2.06)
        motion.setTarget(c, within: display, at: 2.06, animated: true)
        precondition(motion.target == c && motion.presentation(at: 2.06) == interrupted,
                     "Retargeting jumped back to the previous window")
        for offset in stride(from: 0.0, through: 0.18, by: 0.01) {
            let value = motion.presentation(at: 2.06 + offset).rect!
            precondition(value.minX >= min(interrupted.rect!.minX, c.minX) && value.minX <= max(interrupted.rect!.minX, c.minX),
                         "Hover overshot the chosen window")
        }
        motion.advance(to: 2.25)
        precondition(!motion.isAnimating && motion.presentation(at: 2.25).rect == c)

        // A brief desktop gap fades the old frame; arriving at another window
        // redirects that visible frame rather than popping in a second outline.
        motion.setTarget(nil, within: display, at: 3, animated: true)
        let fading = motion.presentation(at: 3.03)
        precondition(motion.target == nil && fading.rect == c && fading.visibility > 0 && fading.visibility < 1)
        motion.setTarget(a, within: display, at: 3.03, animated: true)
        precondition(motion.presentation(at: 3.03) == fading, "Crossing a desktop gap broke continuity")
        motion.setTarget(nil, within: display, at: 4, animated: true)
        precondition(motion.presentation(at: 4.101).rect == nil && motion.presentation(at: 4.101).visibility == 0)
        motion.setTarget(b, within: display, at: 5, animated: false)
        precondition(!motion.isAnimating && motion.presentation(at: 5) == .init(rect: b, visibility: 1),
                     "Reduced motion did not snap to the real target")
        motion.setTarget(display.offsetBy(dx: 900, dy: 0), within: display, at: 6, animated: true)
        precondition(motion.presentation(at: 6.03).rect == b,
                     "A window on another display swept a frame across this display")
        precondition(motion.presentation(at: 6.101).visibility == 0)
        motion.setTarget(a, within: display, at: 7, animated: false)
        motion.setTarget(b, within: display, at: 8, animated: true)
        let beforeDismissal = motion.presentation(at: 8.04)
        motion.freeze(at: 8.04)
        precondition(!motion.isAnimating && motion.presentation(at: 9) == beforeDismissal && motion.target == b,
                     "Dismissal jumped to the destination instead of freezing the visible frame")

        // Exercise the production view handlers, not just the interpolation.
        let panel = SelectionPanel(screenFrame: display)
        let view = SelectionView(frame: CGRect(origin: .zero, size: display.size))
        panel.contentView = view; view.screenFrame = display
        view.highlight = a
        let now = CACurrentMediaTime()
        view.setHoveredWindow(b, animated: true, at: now)
        precondition(view.highlight == b && view.hoverPresentation(at: now).rect == a)
        view.onHover = { _ in view.setHoveredWindow(b, animated: true) }
        view.onPropose = { _ in
            view.isReviewing = true
            view.reviewDraft = CaptureSelectionDraft(rect: view.highlight!, windowID: 42)
        }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 500, y: 300)))
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 500, y: 300)))
        precondition(view.reviewDraft?.rect == b && view.hoverPresentation().rect == b,
                     "Clicking during motion captured intermediate geometry or delayed review")
        view.isReviewing = false; view.reviewDraft = nil; view.highlight = a
        view.setHoveredWindow(b, animated: true)
        view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 240, y: 210)))
        precondition(view.highlight == CGRect(x: -700, y: 200, width: 140, height: 110))
        precondition(view.hoverPresentation().rect == view.highlight && view.hoverPresentation().visibility == 1,
                     "A free region inherited lag from window-hover motion")
        view.isFinishing = true
        panel.contentView = nil

        weak var releasedView: SelectionView?
        autoreleasepool {
            let transient = SelectionView(frame: CGRect(origin: .zero, size: display.size))
            transient.screenFrame = display
            panel.contentView = transient
            transient.highlight = a
            transient.setHoveredWindow(b, animated: true)
            releasedView = transient
            panel.contentView = nil
        }
        precondition(releasedView == nil, "The hover display link retained a closed capture view")
    }
}

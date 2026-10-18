import AppKit
import CoreTransferable
import ImageIO
import ScreenCaptureKit
import SnagForgeDomain

@main struct TransferPrivacyChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        try await checkEditorExportLifecycle()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Transfer-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let suite = "Snaprivo-Transfer-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = WorkspaceModel(root: base.appendingPathComponent("library"), defaults: defaults)
        func source(_ color: NSColor) -> CGImage {
            let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
            context.translateBy(x: 0, y: 80); context.scaleBy(x: 1, y: -1)
            context.setFillColor(color.cgColor); context.fill(CGRect(x: 21, y: 21, width: 48, height: 28))
            return context.makeImage()!
        }
        let red = source(.red), blue = source(.blue)
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 20.3, y: 20.2), end: CGPoint(x: 69.8, y: 49.8))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        // Malicious/irrelevant shape properties must never make a redaction translucent.
        mask.fill = EditorFill(isEnabled: false, opacity: 0); mask.cornerRadius = 100
        var text = EditorObject(kind: .text, start: CGPoint(x: 25, y: 25), text: "ALPHA", fontSize: 8)
        let crop = CGRect(x: 10, y: 10, width: 80, height: 60)
        let resized = PixelSize(width: 41, height: 29)!
        let a = try EditorRenderer.png(image: red, objects: [mask, text], crop: crop, resizedSize: resized)
        text.text = "BETA"
        let b = try EditorRenderer.png(image: blue, objects: [text, mask], crop: crop, resizedSize: resized)
        precondition(a == b, "Covered original pixels/text leaked into flattened output")
        let rep = NSBitmapImageRep(data: a)!
        precondition(rep.pixelsWide == 41 && rep.pixelsHigh == 29)
        for y in 5..<20 { for x in 5..<31 {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            precondition(c.redComponent == 0 && c.greenComponent == 0 && c.blueComponent == 0 && c.alphaComponent == 1)
        } }
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(a as CFData, nil)!, 0, nil)! as NSDictionary
        precondition(!props.description.contains("ALPHA") && !props.description.contains("BETA"))
        let doc = ProjectDocument(title: "Transfer fixture", pixelSize: PixelSize(width: 100, height: 80)!, objects: [text, mask], crop: crop, resizedSize: resized, isFavorite: true)
        let png = try EditorRenderer.png(image: red, objects: [])
        try await workspace.store.create(doc, original: png, thumbnail: a)
        workspace.openProject(doc.id)
        while workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        workspace.editor!.editText(at: CGPoint(x: 1, y: 1)); workspace.editor!.updateText("Pending export text")
        let portable = base.appendingPathComponent("test.snaprivo")
        let action1 = await workspace.transfer(.exportProject(doc.id), at: portable); precondition(action1)
        let imported = WorkspaceModel(root: base.appendingPathComponent("new"), defaults: defaults)
        let action2 = await imported.transfer(.importProject, at: portable); precondition(action2)
        precondition(imported.editor!.document.id != doc.id)
        precondition(imported.editor!.document.objects.last!.text == "Pending export text")
        precondition(imported.editor!.document.isFavorite && imported.editor!.document.crop == crop && imported.editor!.document.resizedSize == resized)
        let importedID = imported.editor!.document.id
        let action3 = await imported.changeTrash(importedID, action: .trash); precondition(action3)
        let backup = base.appendingPathComponent("test.snaprivobackup")
        let action4 = await imported.transfer(.backup, at: backup); precondition(action4)
        let restored = WorkspaceModel(root: base.appendingPathComponent("restored"), defaults: defaults)
        let action5 = await restored.transfer(.restoreBackup, at: backup); precondition(action5)
        precondition(restored.trashItems.count == 1 && restored.items.isEmpty)
        let action6 = await restored.changeTrash(importedID, action: .restore); precondition(action6)
        restored.openProject(importedID)
        while restored.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        precondition(restored.editor!.document.objects == imported.trashItems.first?.document.objects || restored.editor!.document.objects == workspace.editor!.document.objects)
        let reloaded = try await ProjectStore(root: restored.store.root).load(importedID)
        precondition(reloaded.original == png && reloaded.document.crop == crop && reloaded.document.resizedSize == resized)
        // macOS may synthesize TIFF from our flattened PNG. Both must contain only flattened pixels.
        let board = NSPasteboard(name: NSPasteboard.Name("Snaprivo-Privacy-\(UUID())"))
        defer { board.releaseGlobally() }
        let editor = EditorModel(image: red, document: doc, generation: 0, store: workspace.store, onSaved: {})
        editor.copyPNG(to: board, animateFeedback: true)
        precondition(editor.copyState == .copying && editor.animateCopyFeedback)
        precondition(!editor.isExportingPNG, "Clipboard copy must not disable/fade the PNG toolbar controls")
        while editor.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        precondition(editor.copyState == .copied, "Successful clipboard write did not confirm copying")
        editor.copyPNG(to: board)
        precondition(editor.copyState == .copying && !editor.animateCopyFeedback, "Keyboard copy should not animate")
        while editor.isExporting { try await Task.sleep(for: .milliseconds(10)) }
        precondition(editor.copyState == .copied)
        try await Task.sleep(for: .milliseconds(1750))
        precondition(editor.copyState == .idle, "Copy confirmation did not reset")
        let allowedTypes = Set(["public.png", "Apple PNG pasteboard type", "public.tiff", "NeXT TIFF v4.0 pasteboard type"])
        precondition(Set((board.types ?? []).map(\.rawValue)).isSubset(of: allowedTypes))
        precondition(board.data(forType: .png) != nil)
        precondition(board.data(forType: .png) == b)
        if let tiff = board.data(forType: .tiff) {
            let converted = NSBitmapImageRep(data: tiff)!
            let center = converted.colorAt(x: 15, y: 10)!.usingColorSpace(.deviceRGB)!
            precondition(center.alphaComponent == 1 && center.redComponent == 0 && center.greenComponent == 0 && center.blueComponent == 0)
        }
        // Exercise the same Transferable used by ShareLink, without sending to any service.
        let share = editor.pngShareItem!
        precondition(EditorPNGShare.exportedContentTypes() == [.png])
        let shareBytes = try await share.exported(as: .png)
        precondition(shareBytes == b, "Sharing differs from the flattened PNG/clipboard, or exposes covered pixels")
        let provider = NSItemProvider(); provider.register(share)
        precondition(provider.hasItemConformingToTypeIdentifier("public.png"))
        let providerBytes: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: "public.png") { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
        precondition(providerBytes == b, "System item provider exported different pixels")
        let shareDirectory = base.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
        let shareURL = try await share.export(to: shareDirectory, contentType: .png)
        let sharedFile = try Data(contentsOf: shareURL)
        precondition(shareURL.pathExtension == "png" && sharedFile == b && share.suggestedFilename == share.fileName)
        let sharedPixels = NSBitmapImageRep(data: sharedFile)!
        precondition(sharedPixels.pixelsWide == 41 && sharedPixels.pixelsHigh == 29)
        editor.commit([]); editor.updateMetadata(title: "Later edits")
        let stableBytes = try await share.exported(as: .png)
        precondition(stableBytes == b, "An open share picked up later edits or a changed project")
        editor.beginCrop(); precondition(editor.pngShareItem == nil); editor.cancelCrop()
        editor.isShowingImageSize = true; precondition(editor.pngShareItem == nil); editor.isShowingImageSize = false
        editor.preview = [mask]; precondition(editor.pngShareItem == nil); editor.preview = nil
        editor.isCanvasGestureActive = true; precondition(editor.pngShareItem == nil); editor.isCanvasGestureActive = false
        for title in ["../Ordner/Bild:Test\n.png", String(repeating: "📸", count: 400), ""] {
            let named = EditorPNGShare(image: red, objects: [], crop: nil, resizedSize: nil, title: title)
            precondition(named.fileName.hasSuffix(".png") && named.fileName.utf8.count <= 184
                         && !named.fileName.contains("/") && !named.fileName.contains(":") && !named.fileName.contains("\n"))
        }
        precondition(NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil) != nil)
        print("Sharing checks passed: PNG-only Transferable/item-provider/file export matches clipboard and covered pixels after crop/resize; stable snapshot, confirmed-state guards and bounded PNG filename. No service was invoked.")
        // Permission decisions are exercised without changing macOS privacy settings.
        @MainActor final class PermissionProbe { var granted = false; var asks = 0 }
        let probe = PermissionProbe()
        let coordinator = ScreenshotCoordinator(preflight: { probe.granted }, requestAccess: { probe.asks += 1; return false })
        precondition(!coordinator.checkPermission(requestIfNeeded: false) && probe.asks == 0)
        precondition(!coordinator.checkPermission(requestIfNeeded: true) && probe.asks == 1)
        precondition(!coordinator.checkPermission(requestIfNeeded: true) && probe.asks == 1)
        probe.granted = true; coordinator.refreshPermission()
        precondition(coordinator.hasPermission && !coordinator.needsPermission && coordinator.errorMessage == nil)
        coordinator.handleCaptureFailure(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue))
        precondition(coordinator.needsRestart && coordinator.needsPermission && !coordinator.hasPermission)
        let afterRestart = ScreenshotCoordinator(preflight: { probe.granted })
        precondition(afterRestart.checkPermission(requestIfNeeded: false))
        probe.granted = false
        afterRestart.handleCaptureFailure(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue))
        precondition(afterRestart.needsPermission && !afterRestart.needsRestart)
        workspace.openScreenshot(red)
        while workspace.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        precondition(AppPreferences(defaults: defaults).completedFirstCapture)
        if let fixture = CommandLine.arguments.dropFirst().first {
            try FileManager.default.copyItem(at: backup, to: URL(fileURLWithPath: fixture))
        }
        print("Transfer/privacy checks passed: PNG/clipboard opaque pixels after crop/resize, project import/export pending text, backup/trash/restart, permission denial/return/restart and first-capture persistence.")
    }
}

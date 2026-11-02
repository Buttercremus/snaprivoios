import AppKit
import ImageIO
import SnagForgeDomain

@main struct QuickLookChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--verify-thumbnail" {
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!, bitmap = NSBitmapImageRep(cgImage: image)
            check(isBlack(bitmap, x: image.width / 2, y: image.height / 2), "System thumbnail lost its redaction or used a generic icon")
            let edge = bitmap.colorAt(x: image.width / 6, y: image.height / 2)!.usingColorSpace(.sRGB)!
            check(edge.redComponent > 0.8 && edge.greenComponent < 0.2, "System thumbnail did not contain the fixture")
            print("System Quick Look thumbnail passed: actual service output contains the redacted synthetic project.")
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QuickLook-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let width = 240, height = 160
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let original = try EditorRenderer.png(image: context.makeImage()!, objects: [])
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 60, y: 40), end: CGPoint(x: 180, y: 120))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        var doc = ProjectDocument(title: "Synthetic Quick Look", pixelSize: PixelSize(width: width, height: height)!, objects: [mask])
        let file = root.appendingPathComponent("Synthetic.snaprivo")
        let archive = try ProjectArchive(document: doc, original: original)
        try archive.encoded().write(to: file)
        let bytes = try Data(contentsOf: file)
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--export-fixture" {
            try bytes.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
            print("Synthetic Quick Look fixture exported.")
            return
        }
        let renderer = ProjectPreviewRenderer.shared
        let preview = try await renderer.image(at: file, maximumDimension: 120)
        check(preview.width == 120 && preview.height == 80)
        let bitmap = NSBitmapImageRep(cgImage: preview)
        check(isBlack(bitmap, x: 60, y: 40), "Quick Look exposed original pixels under a redaction")
        check(bitmap.colorAt(x: 5, y: 5)!.redComponent > 0.8)
        check(try Data(contentsOf: file) == bytes, "Preview changed its source archive")
        let fit = ProjectPreviewRenderer.fittedRect(image: preview, in: CGSize(width: 200, height: 200))
        check(fit.width == 200 && abs(fit.height - 133.333333) < 0.001 && abs(fit.midY - 100) < 0.001)
        check(try ProjectPreviewRenderer.thumbnailDimension(size: CGSize(width: 256, height: 256), scale: 2) == 512)
        do { _ = try ProjectPreviewRenderer.thumbnailDimension(size: CGSize(width: CGFloat.infinity, height: 100), scale: 2); preconditionFailure("Infinite request accepted") } catch { }
        do { _ = try ProjectPreviewRenderer.thumbnailDimension(size: CGSize(width: 1024, height: 1024), scale: 4); preconditionFailure("Unbounded drawing context accepted") } catch { }

        doc.crop = CGRect(x: 60, y: 40, width: 120, height: 80)
        var style = EditorPresentation(); style.padding = 10; style.background = .solid(EditorColor(red: 1, green: 1, blue: 1))
        doc.presentation = style
        let cropped = root.appendingPathComponent("Cropped.snaprivo")
        try ProjectArchive(document: doc, original: original).encoded().write(to: cropped)
        let cropPreview = try await renderer.image(at: cropped, maximumDimension: 70)
        check(cropPreview.width == 70 && cropPreview.height == 50)
        let croppedBitmap = NSBitmapImageRep(cgImage: cropPreview)
        check(isBlack(croppedBitmap, x: 35, y: 25) && croppedBitmap.colorAt(x: 1, y: 1)!.redComponent > 0.8,
            "Crop, scale or presentation bypassed the redacted composition")

        var plist = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as! [String: Any]
        func write(_ value: [String: Any], _ name: String) throws -> URL {
            let url = root.appendingPathComponent(name).appendingPathExtension("snaprivo")
            try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: url)
            return url
        }
        plist["digest"] = String(repeating: "0", count: 64)
        await rejected(renderer, file: try write(plist, "BadDigest"))
        plist = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as! [String: Any]
        plist["version"] = 999
        await rejected(renderer, file: try write(plist, "NewerVersion"))
        plist["version"] = 1; plist["document"] = Data(repeating: 32, count: 8_000_001)
        await rejected(renderer, file: try write(plist, "LargeMetadata"), expected: .documentTooLarge)

        var fakePNG = original
        func put(_ value: UInt32, at index: Int) {
            for offset in 0..<4 { fakePNG[index + offset] = UInt8((value >> (24 - 8 * offset)) & 255) }
        }
        put(8000, at: 16); put(4000, at: 20)
        let largeDoc = ProjectDocument(title: "Oversized decoded fixture", pixelSize: PixelSize(width: 8000, height: 4000)!)
        let large = root.appendingPathComponent("LargePixels.snaprivo")
        try ProjectArchive(document: largeDoc, original: fakePNG).encoded().write(to: large)
        await rejected(renderer, file: large, expected: .fileTooLarge)
        let sparse = root.appendingPathComponent("LargeFile.snaprivo")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: UInt64(ProjectPreviewRenderer.maximumArchiveBytes + 1)); try handle.close()
        await rejected(renderer, file: sparse, expected: .fileTooLarge)
        let link = root.appendingPathComponent("Link.snaprivo")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        await rejected(renderer, file: link)
        await rejected(renderer, file: root)
        let canceled = Task { try await renderer.image(at: file, maximumDimension: 120) }
        canceled.cancel()
        do { _ = try await canceled.value; preconditionFailure("Cancelled request rendered") } catch is CancellationError { }

        var completions = 0
        let completion = QuickLookCompletion<Int> { reply, error in
            check(reply == 1 && error == nil); completions += 1
        }
        completion.finish(1); completion.finish(2)
        check(completions == 1)
        print("Quick Look core passed: redaction before thumbnail/crop, presentation, bounded fit/scale, unchanged archives, invalid digest/version, bounded metadata/files/decoded pixels, symlink/directory rejection, cancellation and one completion.")
    }
    private static func isBlack(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> Bool {
        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return color.redComponent < 0.05 && color.greenComponent < 0.05 && color.blueComponent < 0.05 && color.alphaComponent > 0.95
    }
    private static func rejected(_ renderer: ProjectPreviewRenderer, file: URL, expected: ProjectError? = nil) async {
        do { _ = try await renderer.image(at: file, maximumDimension: 256); preconditionFailure("Invalid archive produced a preview") }
        catch { if let expected { check((error as? ProjectError) == expected) } }
    }
}
private func check(_ value: Bool, _ message: String = "Quick Look check failed", file: StaticString = #fileID, line: UInt = #line) {
    precondition(value, message, file: file, line: line)
}

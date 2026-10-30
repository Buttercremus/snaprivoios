import AppKit
import SnagForgeDomain
import ImageIO

func checkPresentationBackgroundPixels() throws {
    let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 120, height: 80)); let input = context.makeImage()!
    var options = ImageOutputOptions(); options.padding = 20; options.aspectRatio = .square; options.backgroundStyle = .gradient(PresentationGradient(colors: [EditorColor(red: 0, green: 0, blue: 1), EditorColor(red: 0, green: 1, blue: 0)], angle: 45))
    let output = try ImageOutput.compose(input, options: options); precondition(output.width == output.height); precondition(output.width > input.width)
    let rep = NSBitmapImageRep(cgImage: output); precondition(rep.colorAt(x: 0, y: 0) != rep.colorAt(x: output.width / 2, y: output.height / 2), "gradient did not affect output pixels")
}

func checkPresentationBackwardsCompatibility() throws {
    let data = try JSONSerialization.data(withJSONObject: ["format": "jpeg", "quality": 0.9, "background": ["red": 1.0, "green": 1.0, "blue": 1.0], "padding": 0, "cornerRadius": 0.0, "shadow": false])
    let value = try JSONDecoder().decode(ImageOutputOptions.self, from: data); precondition(value.aspectRatio == .natural); precondition(value.backgroundStyle == .solid(EditorColor(red: 1, green: 1, blue: 1)))
}

@main struct PresentationBackgroundChecksMain {
    static func main() throws {
        try checkPresentationBackgroundPixels(); try checkPresentationBackwardsCompatibility(); try checkPresentationImportsAndBlur()
        let suite = "PresentationBackgroundChecks-\(UUID())", defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let presets = [PresentationPreset(name: "Test", options: ImageOutputOptions())]; PresentationPresetStore.save(presets, defaults: defaults); precondition(PresentationPresetStore.load(defaults: defaults) == presets)
        var renamed = presets; renamed[0].name = "Renamed"; PresentationPresetStore.save(renamed, defaults: defaults); precondition(PresentationPresetStore.load(defaults: defaults)[0].name == "Renamed")
        PresentationPresetStore.save([], defaults: defaults); precondition(PresentationPresetStore.load(defaults: defaults).isEmpty)
        defaults.set(Data("corrupt".utf8), forKey: "image.output.presets.v1"); precondition(PresentationPresetStore.load(defaults: defaults).isEmpty)
        var invalidPreset = presets
        invalidPreset[0].options.background = EditorColor(red: 100,green:0,blue:0)
        PresentationPresetStore.save(invalidPreset, defaults: defaults)
        precondition(PresentationPresetStore.load(defaults: defaults).isEmpty, "Corrupt preset colors were accepted")
        var invalid = ImageOutputOptions(); invalid.padding = 10_000; let clamped = try ImageOutput.compose(inputImage(), options: invalid); precondition(clamped.width == 1100, "padding must clamp to safe maximum")
        print("Presentation background checks passed: pixel compositing, ratios, legacy decoding and preset persistence")
    }

    private static func inputImage() -> CGImage { let c = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!; c.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 100, height: 80)); return c.makeImage()! }
}


private func checkPresentationImportsAndBlur() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-BackgroundChecks-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ctx = CGContext(data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x:0,y:0,width:100,height:40))
    ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x:50,y:0,width:50,height:40))
    let input = ctx.makeImage()!, source = root.appendingPathComponent("input.png")
    let destination = CGImageDestinationCreateWithURL(source as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, input, [kCGImagePropertyOrientation:6] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    let copy = try PresentationBackgroundStorage.importImage(from:source, storingIn:root.appendingPathComponent("Managed"))
    precondition(copy != source && copy.deletingLastPathComponent().lastPathComponent == "Managed")
    let imported = CGImageSourceCreateWithURL(copy as CFURL, nil)!
    let normalized = CGImageSourceCreateImageAtIndex(imported,0,nil)!
    precondition(normalized.width == 40 && normalized.height == 100, "Imported orientation was not normalized")
    try FileManager.default.removeItem(at:source)
    precondition(FileManager.default.fileExists(atPath:copy.path), "Background still depended on original URL")
    // Use a transparent foreground so background pixels can be compared directly.
    let transparentCtx = CGContext(data:nil,width:100,height:80,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let foreground = transparentCtx.makeImage()!
    var options = ImageOutputOptions(); options.format = .png
    let bare = try ImageOutput.compose(foreground,options:options)
    precondition(NSBitmapImageRep(cgImage:bare).colorAt(x:10,y:10)!.alphaComponent == 0, "Bare PNG lost alpha")
    for ratio in PresentationAspectRatio.allCases {
        options.aspectRatio = ratio; options.padding = 43
        let result = try ImageOutput.compose(foreground,options:options)
        if let ratio = ratio.value { precondition(abs(CGFloat(result.width)-CGFloat(result.height)*ratio) <= max(1,ratio), "Padded canvas ratio is wrong") }
    }
    options = ImageOutputOptions(); options.format = .png; options.backgroundStyle = .image(path:copy.path,blur:0)
    let sharp = try ImageOutput.compose(foreground,options:options)
    options.backgroundStyle = .image(path:copy.path,blur:16)
    let blurred = try ImageOutput.compose(foreground,options:options)
    let a = NSBitmapImageRep(cgImage:sharp), b = NSBitmapImageRep(cgImage:blurred)
    let edgeSharp = a.colorAt(x:50,y:35)!, edgeBlur = b.colorAt(x:50,y:35)!
    precondition(abs(edgeSharp.redComponent-edgeBlur.redComponent)>0.05, "Blur did not smooth actual image pixels")
    precondition(b.colorAt(x:0,y:0)!.alphaComponent > 0.99, "Blur edges became transparent")
    let missing = root.appendingPathComponent("missing.png")
    options.backgroundStyle = .image(path:missing.path,blur:0)
    do { _ = try ImageOutput.compose(foreground,options:options); preconditionFailure("Missing background silently exported") } catch { }
    let link = root.appendingPathComponent("link.png"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:copy)
    do { _ = try PresentationBackgroundStorage.importImage(from:link,storingIn:root); preconditionFailure("Import followed a symlink") } catch { }
    let bad = root.appendingPathComponent("invalid.png"); try Data("not an image".utf8).write(to:bad)
    do { _ = try PresentationBackgroundStorage.importImage(from:bad,storingIn:root); preconditionFailure("Invalid image imported") } catch { }
    print("Background import/blur checks passed: orientation, own copies, alpha, padded ratios, actual blur, opaque edges and failed inputs")
}

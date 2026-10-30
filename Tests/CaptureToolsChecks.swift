import AppKit
import CoreImage
import VisionKit
import SnagForgeDomain

@MainActor private final class AccessState { var granted = true }

@main struct CaptureToolsChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let payload = "https://example.com/synthetic-qr"
        let filter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(payload.utf8), "inputCorrectionLevel": "M"])!
        let qr = filter.outputImage!.transformed(by: .init(scaleX: 8, y: 8))
        let qrImage = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(qr, from: qr.extent)!
        let snapshot = EditorPNGShare(image: qrImage, objects: [], crop: nil, resizedSize: nil, title: "Synthetic")
        let recognition = QuickImageRecognitionModel(service: TextRecognitionService(perform: { _, _ in [] }))
        var writes: [String] = []
        func awaitCompletion() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while recognition.isBusy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            precondition(!recognition.isBusy, "Recognition did not finish")
        }
        recognition.recognize(snapshot, codesOnly: true, canUse: { true }, copy: { writes.append($0); return true })
        try await awaitCompletion()
        precondition(recognition.codes == [payload] && writes.isEmpty, "QR reading must not overwrite the clipboard")
        var mask = EditorObject(kind: .redact, start: .zero, end: CGPoint(x: qrImage.width, y: qrImage.height)); mask.color = EditorColor(red: 0, green: 0, blue: 0)
        var masked = snapshot
        masked = EditorPNGShare(image: qrImage, objects: [mask], crop: nil, resizedSize: nil, title: "Synthetic", transform: .clockwise90)
        recognition.recognize(masked, codesOnly: true, canUse: { true }, copy: { writes.append($0); return true })
        try await awaitCompletion()
        precondition(recognition.codes.isEmpty && writes.isEmpty, "QR reader leaked covered pixels")
        let access = AccessState()
        recognition.recognize(snapshot, codesOnly: true, canUse: { access.granted }, copy: { writes.append($0); return true })
        access.granted = false
        try await awaitCompletion(); precondition(recognition.codes.isEmpty && writes.isEmpty, "Revoked access published a result")
        recognition.recognize(snapshot, codesOnly: false, canUse: { true }, copy: { writes.append($0); return true })
        recognition.cancel()
        try await Task.sleep(for: .milliseconds(200))
        precondition(!recognition.isBusy && recognition.codes.isEmpty && writes.isEmpty)

        print("QR, masks, cancellation and access checks passed")
        let ctx = CGContext(data: nil, width: 900, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 400))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSString(string: "SYNTHETIC PUBLIC TEXT").draw(at: CGPoint(x: 40, y: 270), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        NSString(string: "HIDDEN DEMO SECRET").draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let image = ctx.makeImage()!
        var textMask = mask; textMask.start = CGPoint(x: 0, y: 240); textMask.end = CGPoint(x: 900, y: 400)
        var presentation = EditorPresentation(); presentation.rotationDegrees = 8; presentation.padding = 30
        let textSnapshot = EditorPNGShare(image: image, objects: [textMask], crop: nil, resizedSize: nil, title: "Synthetic text", presentation: presentation)
        let flattened = try await textSnapshot.recognitionImage()
        precondition(flattened.width > image.width && flattened.height > image.height, "Recognition omitted presentation")
        let live = InlineTextRecognitionModel()
        await live.prepare(textSnapshot, canUse: { true })
        if ImageAnalyzer.isSupported {
            precondition(live.error == nil, "Native Live Text analysis failed")
            let recognized = live.transcript.uppercased()
            print("Live Text validation: public token found=\(recognized.contains("SYNTHETIC") || recognized.contains("PUBLIC")), covered token found=\(recognized.contains("SECRET")), character count=\(recognized.count)")
            precondition(!recognized.contains("SECRET"), "Live Text leaked masked text")
            precondition(recognized.contains("SYNTHETIC") || recognized.contains("PUBLIC"), "Live Text did not recognize the visible synthetic text")
        }
        live.clear(); precondition(live.transcript.isEmpty && live.selectedText.isEmpty)
        print("Capture tool checks passed: real QR reader, flattened presentation/masks, explicit clipboard writes, cancellation, revoked access and native Live Text")
    }
}

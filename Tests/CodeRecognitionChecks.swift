import AppKit
import CoreImage
import SnagForgeDomain

private actor RecognitionStart {
    var started = false
    func mark() { started = true }
}

@main struct CodeRecognitionChecks {
    static func main() async throws {
        let payload = "https://example.com/synthetic-snaprivo-test"
        let filter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage":Data(payload.utf8), "inputCorrectionLevel":"M"])!
        let qr = filter.outputImage!.transformed(by:CGAffineTransform(scaleX:8,y:8))
        let image = CIContext(options:[.useSoftwareRenderer:true]).createCGImage(qr,from:qr.extent)!
        let service = TextRecognitionService(perform: { _,_ in [] })
        let codes = try await service.recognizeCodes(image)
        precondition(codes.contains(payload), "Vision did not read the synthetic QR")
        let result = try await service.recognizeDirect(image)
        precondition(result.text.isEmpty && result.codes.contains(payload), "Direct capture did not expose QR result")
        var mask = EditorObject(kind:.redact,start:.zero,end:CGPoint(x:image.width,y:image.height)); mask.color = EditorColor(red:0,green:0,blue:0)
        let snapshot = TextRecognitionSnapshot(image:image,objects:[mask],crop:nil,resizedSize:nil,transform:.clockwise90)
        let covered = try snapshot.render(snapshot.plan())
        let coveredCodes = try await service.recognizeCodes(covered)
        precondition(coveredCodes.isEmpty, "Covered QR was recognized from hidden original pixels")
        let signal = RecognitionStart()
        let slow = TextRecognitionService(perform: { _,_ in
            await signal.mark()
            try await Task.sleep(for:.seconds(2))
            return []
        })
        let pending = Task { try await slow.recognizeDirect(image) }
        let deadline = ContinuousClock.now.advanced(by:.seconds(3))
        while !(await signal.started), ContinuousClock.now < deadline { await Task.yield() }
        let started = await signal.started
        precondition(started, "Synthetic delayed recognition never started")
        let queued = Task { try await slow.recognizeCodes(image) }
        let cancelledWaiter = Task { try await slow.recognizeDirect(image, includeCodes: false) }
        try await Task.sleep(for: .milliseconds(30))
        cancelledWaiter.cancel()
        do { _ = try await cancelledWaiter.value; preconditionFailure("Cancelled queued job escaped") }
        catch is CancellationError { }
        pending.cancel()
        do { _ = try await pending.value; preconditionFailure("Cancelled direct result escaped") }
        catch is CancellationError { }
        let queuedCodes = try await queued.value
        precondition(queuedCodes.contains(payload), "Queued QR request was lost while an OCR request cancelled")
        let textOnly = try await service.recognizeDirect(image, includeCodes: false)
        precondition(textOnly.codes.isEmpty, "Text-only capture ran barcode recognition")
        let nextCodes = try await slow.recognizeCodes(image)
        precondition(nextCodes.contains(payload), "Queue did not release its slot")
        let textImage = await MainActor.run {
            let context = CGContext(data: nil, width: 1000, height: 220, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 220))
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSString(string: "Snaprivo capture 42").draw(at: CGPoint(x: 40, y: 95), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            return context.makeImage()!
        }
        let realText = try await TextRecognitionService().recognizeDirect(textImage, includeCodes: false)
        precondition(realText.text.contains("Snaprivo") && realText.text.contains("42"), "Real on-device OCR failed on clear synthetic screenshot text")
        print("Code recognition checks passed: real Vision QR, direct result, opaque masks, serialized jobs and cancellation; payloads not logged")
    }
}

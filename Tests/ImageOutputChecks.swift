import AppKit
import PDFKit
import SnagForgeDomain
@main struct ImageOutputChecks {
    static func main() throws {
        let ctx = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 1])!); ctx.fill(CGRect(x: 20, y: 20, width: 30, height: 40))
        let input = ctx.makeImage()!
        let color = EditorRenderer.pixelColor(input, x: 30, y: 30)!
        precondition(color.redComponent > 0.99 && color.greenComponent < 0.01)
        precondition(EditorRenderer.pixelColor(input, x: 0, y: 0)!.alphaComponent == 0)
        precondition(EditorRenderer.pixelColor(input, x: Int.min, y: 0) == nil && EditorRenderer.pixelColor(input, x: 120, y: 0) == nil)
        for format in ImageOutputFormat.allCases {
            var options = ImageOutputOptions(); options.format = format
            let image = try ImageOutput.compose(input, options: options)
            let data = try ImageOutput.encode(image, options: options)
            if format == .pdf {
                let pdf = PDFDocument(data: data)!
                precondition(pdf.pageCount == 1 && pdf.page(at: 0)!.bounds(for: .mediaBox).size == CGSize(width: 120, height: 80))
                precondition(pdf.string?.isEmpty != false, "PDF embedded hidden searchable text")
            } else {
                let bitmap = NSBitmapImageRep(data: data)!
                precondition(bitmap.pixelsWide == 120 && bitmap.pixelsHigh == 80)
                let corner = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
                precondition(format == .jpeg ? corner.alphaComponent > 0.99 && corner.redComponent > 0.95 : corner.alphaComponent < 0.01)
            }
        }
        var styled = ImageOutputOptions(); styled.format = .png; styled.padding = 32; styled.cornerRadius = 14; styled.shadow = true
        let styledImage = try ImageOutput.compose(input, options: styled)
        precondition(styledImage.width == 184 && styledImage.height == 144)
        print("Image output checks passed: PNG alpha, opaque JPEG, PDF page size/no hidden text, presentation dimensions.")
    }
}

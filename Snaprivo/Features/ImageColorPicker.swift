import SwiftUI
import AppKit
import SnagForgeDomain

struct ImageColorPicker: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var x = 0
    @State private var y = 0
    @State private var failure: String?
    @State private var copied = false
    private var color: NSColor? {
        guard let image, x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        return EditorRenderer.pixelColor(image, x: x, y: y)
    }
    private var hex: String {
        guard let color else { return "—" }
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Farbpipette & Pixellupe")).font(.title2.bold())
            if let image {
                GeometryReader { geo in
                    let factor = min(geo.size.width / CGFloat(image.width), geo.size.height / CGFloat(image.height))
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
                        .contentShape(.rect)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            x = min(image.width - 1, max(0, Int(value.location.x / factor)))
                            y = min(image.height - 1, max(0, Int(value.location.y / factor)))
                            copied = false
                        })
                        .accessibilityLabel(String(localized: "Pixel im Bild wählen; alternativ X und Y eingeben"))
                }.frame(height: 300)
                HStack(spacing: 16) {
                    if x >= 0, y >= 0, x < image.width, y < image.height, let crop = image.cropping(to: CGRect(x: max(0, x - 5), y: max(0, y - 5), width: min(11, image.width - max(0, x - 5)), height: min(11, image.height - max(0, y - 5)))) {
                        Image(decorative: crop, scale: 1).resizable().interpolation(.none).scaledToFit().frame(width: 110, height: 110)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("X")
                            TextField("X", value: $x, format: .number).textFieldStyle(.roundedBorder)
                            Text("Y")
                            TextField("Y", value: $y, format: .number).textFieldStyle(.roundedBorder)
                        }
                        if let color {
                            HStack {
                                Rectangle().fill(Color(nsColor: color)).frame(width: 26, height: 26).border(.secondary)
                                Text(hex).monospaced().textSelection(.enabled)
                            }
                            Text(String(format: "sRGB: %d, %d, %d · Alpha: %.0f %%", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()), color.alphaComponent * 100)).font(.caption)
                        }
                    }
                }
            } else if let failure { Text(failure).foregroundStyle(.red) }
            else { ProgressView() }
            HStack {
                Button(String(localized: "Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? String(localized: "Kopiert") : String(localized: "HEX kopieren")) {
                    NSPasteboard.general.clearContents(); copied = NSPasteboard.general.setString(hex, forType: .string)
                }.disabled(color == nil)
                Button(String(localized: "Als Werkzeugfarbe übernehmen")) {
                    if let color { model.updateStyle(color: EditorColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)); dismiss() }
                }.disabled(color == nil)
            }
        }.padding(24).frame(width: 650, height: 540)
        .task {
            let source = model.image, objects = model.history.objects, crop = model.history.crop, resized = model.history.resizedSize
            do { image = try await Task.detached { try EditorRenderer.render(image: source, objects: objects, crop: crop, resizedSize: resized) }.value }
            catch { failure = error.localizedDescription }
        }
    }
}

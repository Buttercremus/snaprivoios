import SwiftUI
import AppKit
import Observation
import SnagForgeDomain

@MainActor @Observable
final class ImageColorPickerState {
    private(set) var isActive = false
    private(set) var image: CGImage?
    private(set) var x = 0
    private(set) var y = 0
    private(set) var color: NSColor?
    private(set) var isFixed = false
    private(set) var failure: String?
    var copied = false

    var hex: String {
        guard let color else { return "—" }
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    func activate() { isActive = true }
    func end() {
        isActive = false; image = nil; color = nil; failure = nil; isFixed = false; copied = false
    }
    func prepare(_ model: EditorModel) async {
        image = nil; color = nil; failure = nil; isFixed = false; copied = false
        let source = model.image, objects = model.history.objects, crop = model.history.crop,
            resized = model.history.resizedSize, canvasRect = model.history.canvasRect,
            transform = model.history.transform, presentation = model.history.presentation
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try EditorRenderer.render(image: source, objects: objects, crop: crop, resizedSize: resized,
                canvasRect: canvasRect, transform: transform, presentation: presentation)
        }
        do {
            let rendered = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, isActive else { return }
            image = rendered
            setPixel(x: rendered.width / 2, y: rendered.height / 2, fixed: false)
        } catch {
            if !Task.isCancelled, isActive { failure = error.localizedDescription }
        }
    }
    /// Normalized coordinates come from the actual canvas viewport, independent of Retina scale.
    func sample(_ point: CGPoint, fixed: Bool) {
        guard let image, fixed || !isFixed, point.x.isFinite, point.y.isFinite,
              (0..<1).contains(point.x), (0..<1).contains(point.y) else { return }
        setPixel(x: Int(point.x * CGFloat(image.width)), y: Int(point.y * CGFloat(image.height)), fixed: fixed)
    }
    func setPixel(x: Int, y: Int, fixed: Bool = true) {
        guard let image else { return }
        let nextX = min(image.width - 1, max(0, x)), nextY = min(image.height - 1, max(0, y))
        guard nextX != self.x || nextY != self.y || color == nil || fixed != isFixed else { return }
        self.x = nextX; self.y = nextY; isFixed = fixed; copied = false
        color = EditorRenderer.pixelColor(image, x: nextX, y: nextY)
    }
    func move(_ delta: CGSize) { setPixel(x: x + Int(delta.width), y: y + Int(delta.height)) }
    func resume() { isFixed = false; copied = false }
}

struct ImageColorPicker: View {
    let model: EditorModel
    @Bindable var picker: ImageColorPickerState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(String(localized: "Pipette"), systemImage: "eyedropper").font(.headline)
                    Spacer()
                    Text(picker.isFixed ? String(localized: "Festgehalten") : String(localized: "Live-Vorschau"))
                        .font(.caption2).foregroundStyle(.secondary)
                    Button { picker.end(); model.focusRequest += 1 } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Pipette beenden (Esc)"))
                        .accessibilityLabel(String(localized: "Pipette beenden (Esc)"))
                        .accessibilityIdentifier("editor.colorPicker.close")
                }
                if let image = picker.image {
                    HStack(spacing: 12) {
                        PixelColorLoupe(image: image, x: picker.x, y: picker.y)
                            .frame(width: 110, height: 110)
                            .accessibilityLabel(String(localized: "Pixellupe"))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("X")
                                TextField("X", value: Binding(get: { picker.x }, set: { picker.setPixel(x: $0, y: picker.y) }), format: .number)
                                    .accessibilityLabel(String(localized: "Pixelkoordinate X"))
                                    .accessibilityIdentifier("editor.colorPicker.x")
                            }
                            HStack {
                                Text("Y")
                                TextField("Y", value: Binding(get: { picker.y }, set: { picker.setPixel(x: picker.x, y: $0) }), format: .number)
                                    .accessibilityLabel(String(localized: "Pixelkoordinate Y"))
                                    .accessibilityIdentifier("editor.colorPicker.y")
                            }
                            if let color = picker.color {
                                HStack(spacing: 6) {
                                    Rectangle().fill(Color(nsColor: color)).frame(width: 20, height: 20).border(.secondary)
                                        .accessibilityHidden(true)
                                    Text(picker.hex).font(.callout.monospaced()).textSelection(.enabled).fixedSize()
                                        .accessibilityIdentifier("editor.colorPicker.hex")
                                }
                            }
                        }.textFieldStyle(.roundedBorder)
                    }
                    if let color = picker.color {
                        Text(String(format: String(localized: "sRGB: %d, %d, %d"), Int((color.redComponent * 255).rounded()),
                                    Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded())))
                            .font(.caption).monospacedDigit().textSelection(.enabled)
                        Text(String(format: String(localized: "Alpha: %.0f %%"), color.alphaComponent * 100)).font(.caption).monospacedDigit()
                    }
                    HStack {
                        Button(picker.copied ? String(localized: "Kopiert") : String(localized: "HEX kopieren")) {
                            NSPasteboard.general.clearContents()
                            picker.copied = NSPasteboard.general.setString(picker.hex, forType: .string)
                        }.disabled(picker.color == nil).accessibilityIdentifier("editor.colorPicker.copy")
                        Button(String(localized: "Live-Vorschau")) { picker.resume(); model.focusRequest += 1 }
                            .disabled(!picker.isFixed).accessibilityIdentifier("editor.colorPicker.resume")
                    }
                    Button(String(localized: "Als Werkzeugfarbe übernehmen")) {
                        guard let color = picker.color else { return }
                        picker.end()
                        model.updateStyle(color: EditorColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent))
                        model.focusRequest += 1
                    }.disabled(picker.color == nil).accessibilityIdentifier("editor.colorPicker.apply")
                } else if let failure = picker.failure {
                    Text(failure).font(.callout).foregroundStyle(.red)
                } else { ProgressView().frame(maxWidth: .infinity) }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(String(localized: "Maus bewegen: Farbe ansehen · Klicken: Farbe festhalten · Pfeiltasten: Pixel wählen · Esc: beenden"))
        .accessibilityIdentifier("editor.colorPicker.inspector")
        .accessibilityValue(picker.isFixed ? String(localized: "Farbe festgehalten. Klicke auf einen anderen Pixel oder wähle Live-Vorschau.")
            : String(localized: "Bewege die Pipette über das Bild. Ein Klick hält die Farbe fest."))
        .onExitCommand { picker.end(); model.focusRequest += 1 }
    }
}

private struct PixelColorLoupe: View {
    let image: CGImage
    let x: Int
    let y: Int
    var body: some View {
        let rect = CGRect(x: max(0, min(x - 5, image.width - 11)), y: max(0, min(y - 5, image.height - 11)),
                          width: min(11, image.width), height: min(11, image.height))
        if let crop = image.cropping(to: rect) {
            GeometryReader { geometry in
                let scale = min(geometry.size.width / rect.width, geometry.size.height / rect.height)
                ZStack(alignment: .topLeading) {
                    Image(decorative: crop, scale: 1).resizable().interpolation(.none)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                    Rectangle().stroke(.white, lineWidth: 3).overlay { Rectangle().stroke(.black, lineWidth: 1) }
                        .frame(width: scale, height: scale)
                        .offset(x: (CGFloat(x) - rect.minX) * scale, y: (CGFloat(y) - rect.minY) * scale)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.clipped()
        }
    }
}

import SwiftUI
import SnagForgeDomain

struct EditorResizeView: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var width: String
    @State private var height: String
    @State private var keepsRatio = true
    @State private var ratio: CGSize
    @FocusState private var focusedWidth: Bool

    init(model: EditorModel) {
        self.model = model
        let size = model.document.contentPixelSize
        _width = State(initialValue: String(size.width)); _height = State(initialValue: String(size.height))
        _ratio = State(initialValue: CGSize(width: size.width, height: size.height))
    }
    private var target: PixelSize? {
        guard let width = Int(width), let height = Int(height) else { return nil }
        return EditorResize.size(width: Double(width), height: Double(height))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "Bildauflösung ändern")).font(.title2.bold())
            Text(String(localized: "Aktuell: \(model.document.contentPixelSize.width) × \(model.document.contentPixelSize.height) Pixel"))
                .foregroundStyle(.secondary).monospacedDigit()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text(String(localized: "Breite"))
                    TextField(String(localized: "Breite"), text: Binding(get: { width }, set: { width = $0; updateOther(changingWidth: true) }))
                        .focused($focusedWidth).accessibilityIdentifier("editor.resize.width")
                    Text("px").foregroundStyle(.secondary)
                }
                GridRow {
                    Text(String(localized: "Höhe"))
                    TextField(String(localized: "Höhe"), text: Binding(get: { height }, set: { height = $0; updateOther(changingWidth: false) }))
                        .accessibilityIdentifier("editor.resize.height")
                    Text("px").foregroundStyle(.secondary)
                }
            }.textFieldStyle(.roundedBorder).monospacedDigit()
            Toggle(String(localized: "Seitenverhältnis beibehalten"), isOn: $keepsRatio)
                .accessibilityIdentifier("editor.resize.lock")
                .onChange(of: keepsRatio) { _, locked in
                    if locked, let target { ratio = CGSize(width: target.width, height: target.height) }
                    if locked { updateOther(changingWidth: true) }
                }
            HStack {
                Button("50 %") { setPercent(0.5) }
                Button("200 %") { setPercent(2) }
                Spacer()
                Button(String(localized: "Originalauflösung")) {
                    let original = model.document.outputRect.size
                    let source = model.history.transform.swapsAxes ? CGSize(width: original.height, height: original.width) : original
                    width = String(Int(source.width)); height = String(Int(source.height)); ratio = source
                }
            }
            Text(target == nil ? String(localized: "Gib ganze Pixelmaße von 1 bis 32.768 ein, insgesamt höchstens 100 Millionen Pixel.") : String(localized: "Bild, Markierungen und Schrift werden gemeinsam skaliert. Das Original bleibt erhalten."))
                .font(.callout).foregroundStyle(target == nil ? Color.orange : Color.secondary)
                .frame(minHeight: 36, alignment: .topLeading)
            HStack {
                Button(String(localized: "Abbrechen")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Übernehmen")) {
                    if let target, model.applyImageSize(target) { dismiss() }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(target == nil || target == model.document.contentPixelSize)
                .accessibilityIdentifier("editor.resize.apply")
            }
        }
        .padding(24).frame(width: 420)
        .onAppear { focusedWidth = true }
    }
    private func updateOther(changingWidth: Bool) {
        guard keepsRatio, let value = Int(changingWidth ? width : height), (1...32768).contains(value) else { return }
        guard let other = EditorResize.linkedDimension(value: Double(value), changingWidth: changingWidth, ratio: ratio) else { return }
        if changingWidth { height = String(Int(other)) } else { width = String(Int(other)) }
    }
    private func setPercent(_ factor: Double) {
        let current = model.document.contentPixelSize
        width = String(max(1, Int((Double(current.width) * factor).rounded())))
        height = String(max(1, Int((Double(current.height) * factor).rounded())))
        ratio = CGSize(width: current.width, height: current.height)
    }
}

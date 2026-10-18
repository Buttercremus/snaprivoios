import SwiftUI
import SnagForgeDomain

struct TextRecognitionView: View {
    @State private var model: TextRecognitionModel
    @State private var coordinates = ["0", "0", "100", "100"]
    @Environment(\.dismiss) private var dismiss

    init(snapshot: TextRecognitionSnapshot) {
        _model = State(initialValue: TextRecognitionModel(snapshot: snapshot))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Text erkennen")).font(.title2.bold())
            Text(String(localized: "Die Erkennung erfolgt lokal auf deinem Mac. Bild und Text werden nicht hochgeladen oder im Projekt gespeichert."))
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String(localized: "Bildbereich")).font(.headline)
                        Spacer()
                        Button(String(localized: "Ganzes Bild")) { setSelection(CGRect(x: 0, y: 0, width: 1, height: 1)) }
                            .accessibilityIdentifier("ocr.area.reset")
                    }
                    preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(String(localized: "Ziehe einen Bereich auf oder gib seine Position und Größe in Prozent ein."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        coordinateField("X (%)", index: 0)
                        coordinateField("Y (%)", index: 1)
                        coordinateField(String(localized: "Breite (%)"), index: 2)
                        coordinateField(String(localized: "Höhe (%)"), index: 3)
                    }
                    Picker(String(localized: "Sprache"), selection: $model.language) {
                        Text(String(localized: "Automatisch erkennen")).tag("")
                        ForEach(model.languages, id: \.self) { identifier in
                            Text(Locale.current.localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                        }
                    }.accessibilityIdentifier("ocr.language")
                }
                .disabled(model.isBusy)
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Ergebnis der letzten Erkennung")).font(.headline)
                    TextEditor(text: $model.text)
                        .font(.body).padding(4)
                        .background(.background, in: .rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                        .disabled(!model.hasResult || model.isBusy)
                        .accessibilityLabel(String(localized: "Erkannten Text korrigieren"))
                        .accessibilityIdentifier("ocr.result")
                    Text(String(localized: "Prüfe und korrigiere den Text vor dem Kopieren. OCR kann Zeichen und ganze Zeilen übersehen."))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            status.frame(minHeight: 48, alignment: .topLeading)
            HStack {
                Button(String(localized: "Schließen")) { model.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("ocr.close")
                Spacer()
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Button(String(localized: "Abbrechen")) { model.cancel() }
                        .disabled(model.isCancelling).accessibilityIdentifier("ocr.cancel")
                } else if model.preview == nil {
                    Button(String(localized: "Erneut versuchen")) { model.prepare() }
                } else {
                    Button(String(localized: "Text erkennen")) { model.recognize() }
                        .keyboardShortcut(.defaultAction).disabled(!model.canRecognize)
                        .accessibilityIdentifier("ocr.recognize")
                }
                Button(model.didCopy ? String(localized: "Kopiert") : String(localized: "Text kopieren")) { model.copy() }
                    .buttonStyle(.borderedProminent).disabled(!model.canCopy)
                    .accessibilityIdentifier("ocr.copy")
            }
        }
        .padding(24).frame(width: 760, height: 560)
        .task { model.prepare() }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isBusy {
                Text(model.isCancelling ? String(localized: "Texterkennung wird beendet …") : String(localized: "Bild wird lokal verarbeitet …"))
            } else if let notice = model.notice {
                Text(notice).foregroundStyle(.orange)
            } else if model.plan == nil {
                Text(String(localized: "Wähle einen gültigen Bereich innerhalb des Bildes (0–100 %)."))
                    .foregroundStyle(.orange)
            } else if model.hasResult && model.isEmptyResult {
                Text(String(localized: "Kein Text erkannt. Wähle einen kleineren Bereich oder eine andere Sprache."))
            } else if model.hasUncertainText {
                Text(String(localized: "Einige Textstellen sind unsicher. Prüfe das gesamte Ergebnis besonders sorgfältig."))
                    .foregroundStyle(.orange)
            }
            if model.plan?.isDownsampled == true {
                Text(String(localized: "Dieser Bereich wird für OCR verkleinert (max. 4.096 Pixel je Kante, 12 MP). Ein kleinerer Bereich kann mehr Textdetails erhalten."))
                    .foregroundStyle(.secondary)
            }
        }.font(.caption).textSelection(.enabled)
    }

    @ViewBuilder private var preview: some View {
        if let image = model.preview {
            GeometryReader { geometry in
                let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                    if model.plan != nil {
                        Rectangle().strokeBorder(.blue, lineWidth: 2)
                            .background(.blue.opacity(0.12))
                            .frame(width: model.selection.width * size.width, height: model.selection.height * size.height)
                            .offset(x: model.selection.minX * size.width, y: model.selection.minY * size.height)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                    let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
                    let end = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                    if let selection = TextRecognitionPlan.selection(from: start, to: end) { setSelection(selection) }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(String(localized: "Vorschau des bearbeiteten Bildes. Bereich über die Prozentfelder wählen."))
            }
        } else {
            ContentUnavailableView(String(localized: "Bildvorschau"), systemImage: "text.viewfinder")
        }
    }
    private func coordinateField(_ title: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            TextField(title, text: Binding(get: { coordinates[index] }, set: { value in
                coordinates[index] = value
                let values = coordinates.map { Double($0.replacingOccurrences(of: ",", with: ".")) }
                guard values.allSatisfy({ $0 != nil }) else { model.selection = .zero; return }
                model.selection = CGRect(x: values[0]! / 100, y: values[1]! / 100,
                                         width: values[2]! / 100, height: values[3]! / 100)
            }))
            .textFieldStyle(.roundedBorder).accessibilityLabel(title)
            .accessibilityIdentifier("ocr.area.\(index)")
        }
    }
    private func setSelection(_ rect: CGRect) {
        // Preserve exact drag coordinates; rounding is only for the editable display.
        model.selection = rect
        coordinates = [rect.minX, rect.minY, rect.width, rect.height].map { String(format: "%.2f", Double($0 * 100)) }
    }
}

import SwiftUI
import SnagForgeDomain

struct EditorInstructionOptions: View {
    @Bindable var model: EditorModel
    var body: some View {
        if model.activeKind == .highlight { highlightOptions }
        else { stepOptions }
    }
    private var highlightOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Modus"), selection: Binding(get: { model.activeHighlightStyle.mode }, set: { model.setHighlightMode($0) })) {
                Text(String(localized: "Rechteck")).tag(EditorHighlightMode.rectangle)
                Text(String(localized: "Freihand")).tag(EditorHighlightMode.freehand)
            }
            .pickerStyle(.segmented).controlSize(.small).accessibilityIdentifier("editor.highlight.mode")
            EditorColorOptions(title: String(localized: "Markerfarbe"), color: Binding(get: { model.activeColor }, set: { model.updateStyle(color: $0) }))
            EditorPropertySlider(title: String(localized: "Deckkraft"), identifier: "highlightOpacity", value: Binding(
                get: { model.activeHighlightStyle.opacity * 100 }, set: { model.updateHighlightOpacity($0 / 100) }),
                range: 5...80, unit: "%", onEditingChanged: editing)
            if model.activeHighlightStyle.mode == .freehand {
                EditorPropertySlider(title: String(localized: "Markerbreite"), identifier: "highlightWidth", value: Binding(
                    get: { Double(model.activeLineWidth) }, set: { model.updateStyle(width: CGFloat($0)) }),
                    range: 4...160, unit: "px", onEditingChanged: editing)
            }
            Text(String(localized: "Markierungen bleiben transparent, damit Text lesbar bleibt. Wechsel des Modus beginnt eine neue Markierung."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var stepOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Form")).font(.caption)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(EditorStepShape.allCases, id: \.self) { shape in
                    Button {
                        var style = model.activeStepStyle; style.shape = shape; model.updateStepStyle(style)
                    } label: {
                        VStack(spacing: 4) {
                            EditorStepShapeIcon(shape: shape)
                                .fill(Color(.sRGB, red: model.activeColor.red, green: model.activeColor.green, blue: model.activeColor.blue))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text(model.selectedObject == nil ? model.nextStepLabel : model.activeStepStyle.label)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(.sRGB, red: model.activeStepStyle.textColor.red,
                                                               green: model.activeStepStyle.textColor.green, blue: model.activeStepStyle.textColor.blue))
                                        .offset(x: shape == .pointer ? -3 : 0)
                                }
                            Text(shape.title).font(.caption2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(model.activeStepStyle.shape == shape ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04), in: .rect(cornerRadius: 8))
                        .contentShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain).accessibilityLabel(shape.title)
                    .accessibilityAddTraits(model.activeStepStyle.shape == shape ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.steps.shape.\(shape.rawValue)")
                }
            }
            Picker(String(localized: "Typ"), selection: Binding(get: { model.activeStepStyle.numbering }, set: {
                var style = model.activeStepStyle; style.numbering = $0; model.updateStepStyle(style)
            })) {
                Text("1, 2, 3 …").tag(EditorStepNumbering.numbers)
                Text("A, B, C …").tag(EditorStepNumbering.letters)
            }
            .pickerStyle(.segmented).controlSize(.small).accessibilityIdentifier("editor.steps.numbering")
            EditorColorOptions(title: String(localized: "Füllfarbe"), color: Binding(get: { model.activeColor }, set: { model.updateStyle(color: $0) }))
            EditorColorOptions(title: String(localized: "Textfarbe"), color: Binding(get: { model.activeStepStyle.textColor }, set: {
                var style = model.activeStepStyle; style.textColor = $0; model.updateStepStyle(style)
            }))
            EditorPropertySlider(title: String(localized: "Größe"), identifier: "stepSize", value: Binding(
                get: { Double(model.activeStepSize) }, set: { model.updateStepSize(CGFloat($0)) }),
                range: 24...240, unit: "px", onEditingChanged: editing)
            if model.selectedObject?.kind == .step {
                Stepper(String(localized: "Wert: \(model.activeStepStyle.label)"), value: Binding(get: { model.activeStepStyle.index }, set: {
                    var style = model.activeStepStyle; style.index = $0; model.updateStepStyle(style)
                }), in: 1...EditorSteps.maximumIndex)
                .font(.caption).controlSize(.small).accessibilityIdentifier("editor.steps.index")
            }
            Text(String(localized: "Nächste Marke: \(model.nextStepLabel)")).font(.callout).monospacedDigit()
                .accessibilityIdentifier("editor.steps.next")
            Text(String(localized: "Jeder Klick zählt weiter. Bestehende Marken behalten ihre Werte beim Löschen und Anordnen; Buchstaben gehen nach Z mit AA weiter."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func editing(_ active: Bool) {
        if active { model.beginStyleEditing() } else { model.endStyleEditing() }
    }
}

private struct EditorStepShapeIcon: Shape {
    let shape: EditorStepShape
    func path(in rect: CGRect) -> Path {
        var object = EditorObject(kind: .step, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY))
        object.stepStyle = EditorStepStyle(shape: shape)
        return Path(EditorRenderer.stepPath(object))
    }
}

private extension EditorStepShape {
    var title: String {
        switch self { case .circle: String(localized: "Kreis"); case .roundedRectangle: String(localized: "Rechteck"); case .diamond: String(localized: "Raute"); case .pointer: String(localized: "Pfeilmarke") }
    }
}

/// Visible choices, rather than another menu between the tool and the canvas.
struct EditorShapeOptions: View {
    @Bindable var model: EditorModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private var corner: CGFloat { model.selectedObject?.cornerRadius ?? model.defaultCornerRadius }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Form")).font(.caption)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ShapeChoice.all) { choice in
                    let selected = model.activeKind == choice.kind && (choice.kind != .rectangle || (corner > 0) == (choice.corner > 0))
                    Button { model.selectShape(choice.kind, corner: choice.corner) } label: {
                        ShapeIcon(kind: choice.kind, corner: choice.corner > 0 ? 6 : 0)
                            .stroke(selected ? Color.accentColor : .primary, lineWidth: 2)
                            .frame(width: 28, height: 24).frame(maxWidth: .infinity).frame(height: 38)
                            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: .rect(cornerRadius: 7))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain).help(choice.title)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.shape.\(choice.id)")
                }
            }
            Text(String(localized: "Stilvorlagen")).font(.caption).padding(.top, 4)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ShapeStylePreset.all) { preset in
                    Button {
                        model.endStyleEditing()
                        model.updateStyle(color: preset.color, width: 5, fill: preset.fill, stroke: EditorStroke())
                    } label: {
                        ShapeIcon(kind: model.activeKind ?? .rectangle, corner: corner > 0 ? 5 : 0)
                            .fill(preset.fill.isEnabled ? preset.fill.color.swiftUIColor.opacity(preset.fill.opacity) : .clear)
                            .overlay { ShapeIcon(kind: model.activeKind ?? .rectangle, corner: corner > 0 ? 5 : 0).stroke(preset.color.swiftUIColor, lineWidth: 3) }
                            .frame(width: 30, height: 25).frame(maxWidth: .infinity).frame(height: 38)
                            .background(.background, in: .rect(cornerRadius: 7))
                            .overlay { RoundedRectangle(cornerRadius: 7).stroke(.quaternary) }
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain).help(preset.title).accessibilityLabel(preset.title)
                    .accessibilityIdentifier("editor.preset.\(preset.id)")
                }
            }
        }
    }
}

private struct ShapeChoice: Identifiable {
    let id: String
    let kind: EditorObject.Kind
    let title: String
    var corner: CGFloat = 0
    static let all: [Self] = [
        .init(id: "rectangle", kind: .rectangle, title: String(localized: "Rechteck")),
        .init(id: "rounded", kind: .rectangle, title: String(localized: "Abgerundetes Rechteck"), corner: 20),
        .init(id: "ellipse", kind: .ellipse, title: String(localized: "Ellipse")),
        .init(id: "triangle", kind: .triangle, title: String(localized: "Dreieck")),
        .init(id: "diamond", kind: .diamond, title: String(localized: "Raute")),
        .init(id: "star", kind: .star, title: String(localized: "Stern"))
    ]
}

private struct ShapeStylePreset: Identifiable {
    let id: String
    let title: String
    let color: EditorColor
    var fill = EditorFill()
    static let all: [Self] = [
        .init(id: "red", title: String(localized: "Roter Rand, ohne Füllung"), color: EditorColor()),
        .init(id: "blue", title: String(localized: "Blauer Rand, ohne Füllung"), color: EditorColor(red: 0, green: 0.4, blue: 1)),
        .init(id: "green", title: String(localized: "Grüner Rand, ohne Füllung"), color: EditorColor(red: 0.2, green: 0.65, blue: 0.25)),
        .init(id: "yellowFill", title: String(localized: "Gelbe Markierung"), color: EditorColor(red: 0.9, green: 0.65, blue: 0),
              fill: EditorFill(isEnabled: true, color: EditorColor(red: 1, green: 0.85, blue: 0.1), opacity: 0.3)),
        .init(id: "blueFill", title: String(localized: "Blauer Rand mit heller Füllung"), color: EditorColor(red: 0, green: 0.4, blue: 1),
              fill: EditorFill(isEnabled: true, color: EditorColor(red: 0, green: 0.4, blue: 1), opacity: 0.2)),
        .init(id: "darkFill", title: String(localized: "Dunkle Füllung"), color: EditorColor(red: 0.15, green: 0.15, blue: 0.18),
              fill: EditorFill(isEnabled: true, color: EditorColor(red: 0.15, green: 0.15, blue: 0.18)))
    ]
}

private struct ShapeIcon: Shape {
    var kind: EditorObject.Kind
    var corner: CGFloat
    func path(in rect: CGRect) -> Path {
        var object = EditorObject(kind: kind, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY))
        object.cornerRadius = corner
        return Path(EditorRenderer.shapePath(object))
    }
}

struct EditorColorOptions: View {
    let title: String
    @Binding var color: EditorColor
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ColorPicker(title, selection: Binding(get: { color.swiftUIColor }, set: { value in
                guard let next = NSColor(value).usingColorSpace(.sRGB) else { return }
                color = EditorColor(red: next.redComponent, green: next.greenComponent, blue: next.blueComponent)
            }), supportsOpacity: false)
            HStack(spacing: 4) {
                ForEach(ColorChoice.all) { choice in
                    Button { color = choice.color } label: {
                        Circle().fill(choice.color.swiftUIColor)
                            .overlay { Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1) }
                            .padding(2)
                            .overlay { Circle().stroke(color == choice.color ? Color.accentColor : .clear, lineWidth: 2) }
                            .frame(width: 20, height: 20).contentShape(.circle)
                    }
                    .buttonStyle(.plain).help(choice.title)
                    .accessibilityLabel("\(title): \(choice.title)")
                    .accessibilityAddTraits(color == choice.color ? [.isSelected] : [])
                }
            }
        }
    }
}

private struct ColorChoice: Identifiable {
    let title: String
    let color: EditorColor
    var id: String { title }
    static let all: [Self] = [
        .init(title: String(localized: "Rot"), color: EditorColor()),
        .init(title: String(localized: "Orange"), color: EditorColor(red: 1, green: 0.5, blue: 0)),
        .init(title: String(localized: "Gelb"), color: EditorColor(red: 1, green: 0.85, blue: 0.1)),
        .init(title: String(localized: "Grün"), color: EditorColor(red: 0.2, green: 0.65, blue: 0.25)),
        .init(title: String(localized: "Blau"), color: EditorColor(red: 0, green: 0.4, blue: 1)),
        .init(title: String(localized: "Violett"), color: EditorColor(red: 0.65, green: 0.25, blue: 0.85)),
        .init(title: String(localized: "Schwarz"), color: EditorColor(red: 0, green: 0, blue: 0)),
        .init(title: String(localized: "Weiß"), color: EditorColor(red: 1, green: 1, blue: 1))
    ]
}

private extension EditorColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

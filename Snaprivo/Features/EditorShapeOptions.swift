import SwiftUI
import AppKit
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
                ForEach(EditorShapeChoice.all) { choice in
                    let selected = model.activeKind == choice.kind && (choice.kind != .rectangle || (corner > 0) == (choice.corner > 0))
                    Button { model.selectShape(choice.kind, corner: choice.corner) } label: {
                        EditorShapeIcon(kind: choice.kind, corner: choice.corner > 0 ? 6 : 0)
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
                        EditorShapeIcon(kind: model.activeKind ?? .rectangle, corner: corner > 0 ? 5 : 0)
                            .fill(preset.fill.isEnabled ? preset.fill.color.swiftUIColor.opacity(preset.fill.opacity) : .clear)
                            .overlay { EditorShapeIcon(kind: model.activeKind ?? .rectangle, corner: corner > 0 ? 5 : 0).stroke(preset.color.swiftUIColor, lineWidth: 3) }
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
                ForEach(EditorColorChoice.all) { choice in
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


struct EditorSpotlightOptions: View {
    let model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Form"), selection: Binding(get: { model.activeSpotlightStyle.shape }, set: { shape in
                var style = model.activeSpotlightStyle; style.shape = shape; model.updateSpotlightStyle(style)
            })) {
                Text(String(localized: "Rechteck")).tag(EditorSpotlightShape.rectangle)
                Text(String(localized: "Ellipse")).tag(EditorSpotlightShape.ellipse)
            }.pickerStyle(.segmented).accessibilityIdentifier("editor.spotlight.shape")
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Abdunklung")).font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.activeSpotlightStyle.opacity * 100 }, set: { opacity in
                    var style = model.activeSpotlightStyle; style.opacity = opacity / 100; model.updateSpotlightStyle(style)
                }), in: 0...95, onEditingChanged: { editing in
                    if editing { model.beginStyleEditing() } else { model.endStyleEditing() }
                }).accessibilityLabel(String(localized: "Abdunklung")).accessibilityIdentifier("editor.spotlight.opacity")
            }
            Text(String(localized: "Weitere Fokusbereiche bleiben gemeinsam hell. Es gilt die stärkste gewählte Abdunklung."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A shared frame control for the source composition and individually selected image objects.
struct EditorImageFrameControls: View {
    @Binding var radius: Double
    @Binding var border: EditorImageBorder?
    let onEditingChanged: (Bool) -> Void
    @FocusState private var radiusHasFocus: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Eckenradius"))
                Spacer()
                TextField(String(localized: "Eckenradius"), value: $radius, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 56)
                    .focused($radiusHasFocus)
                    .onChange(of: radiusHasFocus) { _, active in onEditingChanged(active) }
                    .onSubmit { onEditingChanged(false); radiusHasFocus = false }
                    .accessibilityIdentifier("editor.image.cornerRadius")
                Text("px").foregroundStyle(.secondary)
            }
            Slider(value: $radius, in: 0...100, onEditingChanged: onEditingChanged)
                .accessibilityLabel(String(localized: "Eckenradius"))
                .accessibilityIdentifier("editor.image.cornerSlider")
            Toggle(String(localized: "Rand"), isOn: Binding(get: { border != nil }, set: { border = $0 ? EditorImageBorder() : nil }))
                .accessibilityIdentifier("editor.image.border")
            if let current = border {
                ColorPicker(String(localized: "Randfarbe"), selection: Binding(get: {
                    Color(red: current.color.red, green: current.color.green, blue: current.color.blue)
                }, set: { value in
                    guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
                    border?.color = EditorColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
                }), supportsOpacity: false)
                HStack {
                    Text(String(localized: "Randbreite"))
                    Slider(value: Binding(get: { current.width }, set: { border?.width = $0 }), in: 1...20, onEditingChanged: onEditingChanged)
                        .accessibilityLabel(String(localized: "Randbreite"))
                    Text("\(Int(current.width)) px").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Source-image selection edits its frame without entering the presentation viewport.
struct EditorSourceImageFrameControls: View {
    let model: EditorModel
    var body: some View {
        EditorImageFrameControls(radius: Binding(get: { model.history.presentation.cornerRadius }, set: { value in
            var next = model.history.presentation; next.cornerRadius = value; model.updatePresentation(next)
        }), border: Binding(get: { model.history.presentation.border }, set: { border in
            var next = model.history.presentation; next.border = border; model.updatePresentation(next)
        }), onEditingChanged: { active in
            if active { model.beginPresentationEditing() } else { model.endPresentationEditing() }
        })
        .onDisappear { model.endPresentationEditing() }
    }
}

struct EditorSelectedImageFrameControls: View {
    let model: EditorModel
    private var currentBorder: EditorImageBorder? {
        guard let object = model.selectedObject, object.stroke?.isEnabled == true else { return nil }
        return EditorImageBorder(width: min(100, object.lineWidth), color: object.color)
    }
    @FocusState private var angleFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Drehwinkel"))
                Spacer()
                TextField(String(localized: "Drehwinkel"), value: Binding(get: { model.selectedObject?.imageRotationDegrees ?? 0 }, set: { model.updateSelectedImageRotation($0) }), format: .number.precision(.fractionLength(0...1)))
                    .focused($angleFocused).textFieldStyle(.roundedBorder).frame(width: 70)
                    .accessibilityIdentifier("editor.image.rotation.value")
                Text("°").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { model.selectedObject?.imageRotationDegrees ?? 0 }, set: { model.updateSelectedImageRotation($0) }), in: -180...180, onEditingChanged: { active in
                if active { model.beginStyleEditing() } else { model.endStyleEditing() }
            }).accessibilityLabel(String(localized: "Drehwinkel")).accessibilityIdentifier("editor.image.rotation.slider")
            Button(String(localized: "Ausrichtung zurücksetzen"), systemImage: "arrow.uturn.backward") { model.updateSelectedImageRotation(0) }
                .disabled((model.selectedObject?.imageRotationDegrees ?? 0) == 0)
            Divider()
        EditorImageFrameControls(radius: Binding(get: { model.selectedObject?.cornerRadius ?? 0 }, set: { value in
            model.updateSelectedImageFrame(radius: value, border: currentBorder)
        }), border: Binding(get: { currentBorder }, set: { border in
            model.updateSelectedImageFrame(radius: model.selectedObject?.cornerRadius ?? 0, border: border)
        }), onEditingChanged: { active in
            if active { model.beginStyleEditing() } else { model.endStyleEditing() }
        })
        }.onChange(of: angleFocused) { _, active in
            if active { model.beginStyleEditing() } else { model.endStyleEditing() }
        }.onDisappear { model.endStyleEditing() }
    }
}

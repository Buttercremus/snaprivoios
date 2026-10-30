import SwiftUI
import SnagForgeDomain

/// A narrow object toolbar. Each button reveals only its own compact system popover.
struct EditorQuickOptions: View {
    @Bindable var model: EditorModel
    let objectID: UUID
    var placement: Placement = .above
    let dismiss: () -> Void
    @State private var activeSection: Section?
    @State private var hoveredSection: Section?
    @FocusState private var focusedSection: Section?
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Placement: CaseIterable {
        case above, below, right, left
        var isHorizontal: Bool { self == .above || self == .below }
        var popoverEdge: Edge {
            switch self {
            case .above: .top
            case .below: .bottom
            case .right: .trailing
            case .left: .leading
            }
        }
    }
    private static let buttonSide: CGFloat = 36
    private static let buttonSpacing: CGFloat = 4
    private static let contentPadding: CGFloat = 6
    private static var thickness: CGFloat { buttonSide + contentPadding * 2 }
    static func horizontalSize(for object: EditorObject) -> CGSize {
        let count = object.kind == .image ? 2 : sections(for: object).count
        return CGSize(width: CGFloat(count) * buttonSide + CGFloat(max(0, count - 1)) * buttonSpacing + contentPadding * 2,
                      height: thickness)
    }

    private enum Section: String, Identifiable {
        case color, shape, line, fill, text, drawingStyle, magnification, smoothing, spotlightShape, spotlightOpacity, blur, opacity, markerWidth, stepShape, stepSize
        var id: String { rawValue }
        var title: String {
            switch self {
            case .color: String(localized: "Farbe")
            case .shape, .stepShape: String(localized: "Form")
            case .line: String(localized: "Linienbreite")
            case .fill: String(localized: "Füllung")
            case .text: String(localized: "Schriftgröße")
            case .drawingStyle: String(localized: "Zeichenstil")
            case .smoothing: String(localized: "Strich glätten")
            case .spotlightShape: String(localized: "Form")
            case .spotlightOpacity: String(localized: "Abdunklung")
            case .magnification: String(localized: "Vergrößerung")
            case .blur: String(localized: "Unschärfe")
            case .opacity: String(localized: "Deckkraft")
            case .markerWidth: String(localized: "Markerbreite")
            case .stepSize: String(localized: "Größe")
            }
        }
    }

    var body: some View {
        let layout = placement.isHorizontal ? AnyLayout(HStackLayout(spacing: Self.buttonSpacing))
            : AnyLayout(VStackLayout(spacing: Self.buttonSpacing))
        GlassEffectContainer(spacing: 8) {
            layout {
                if let object = model.selectedObject, object.id == objectID {
                    ForEach(Self.sections(for: object)) { section in
                        let highlighted = (activeSection ?? hoveredSection) == section
                        Button {
                            model.endStyleEditing()
                            selectSection(activeSection == section ? nil : section)
                        } label: {
                            sectionIcon(section, object: object)
                                .frame(width: Self.buttonSide, height: Self.buttonSide)
                                .background {
                                    if reduceMotion && highlighted {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.15))
                                    }
                                }
                                .glassEffect(highlighted && !reduceMotion ? .regular.tint(.accentColor.opacity(0.15)).interactive() : .identity,
                                             in: .rect(cornerRadius: 10))
                                .glassEffectID(highlighted && !reduceMotion ? "selection" : nil, in: selectionNamespace)
                                .glassEffectTransition(.matchedGeometry)
                                .contentShape(.rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .focused($focusedSection, equals: section)
                        .help(section.title).accessibilityLabel(section.title)
                        .accessibilityAddTraits(activeSection == section ? [.isSelected] : [])
                        .accessibilityIdentifier("editor.quick.section.\(section.rawValue)")
                        .onHover { hovering in
                            withAnimation(selectionAnimation) {
                                if hovering { hoveredSection = section }
                                else if hoveredSection == section { hoveredSection = nil }
                            }
                        }
                        .popover(isPresented: Binding(get: { activeSection == section }, set: { shown in
                            if !shown && activeSection == section { selectSection(nil) }
                        }), arrowEdge: placement.popoverEdge) {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionOptions(section, object: object)
                            }
                            .padding(12).frame(width: 272)
                            .fixedSize(horizontal: false, vertical: true).font(.body).controlSize(.small)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("editor.quick.panel.\(section.rawValue)")
                            .onExitCommand { selectSection(nil) }
                            .onDisappear { model.endStyleEditing() }
                        }
                    }
                    if object.kind == .image {
                        Button { dismiss(); model.duplicateSelection() } label: {
                            Image(systemName: "plus.square.on.square").frame(width: Self.buttonSide, height: Self.buttonSide)
                        }.help(String(localized: "Duplizieren")).accessibilityLabel(String(localized: "Duplizieren"))
                        Button { dismiss(); model.removeSelection() } label: {
                            Image(systemName: "trash").frame(width: Self.buttonSide, height: Self.buttonSide)
                        }.help(String(localized: "Löschen")).accessibilityLabel(String(localized: "Löschen"))
                    }
                }
            }
        }
        .buttonStyle(.plain).font(.system(size: 18))
        .padding(Self.contentPadding)
        .frame(width: placement.isHorizontal ? nil : Self.thickness, height: placement.isHorizontal ? Self.thickness : nil)
        .fixedSize()
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Schnellbearbeitung"))
        .accessibilityIdentifier("editor.quickOptions")
        .task {
            if let object = model.selectedObject { focusedSection = Self.sections(for: object).first }
        }
        .onExitCommand {
            if activeSection != nil { selectSection(nil) } else { dismiss() }
        }
        .onDisappear { model.endStyleEditing() }
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 1)
    }
    private func selectSection(_ section: Section?) {
        withAnimation(selectionAnimation) { activeSection = section }
    }

    private static func sections(for object: EditorObject) -> [Section] {
        switch object.kind {
        case .rectangle, .triangle, .diamond, .star: [.color, .shape, .line, .fill, .drawingStyle]
        case .ellipse: [.color, .shape, .line, .fill, .drawingStyle]
        case .arrow: [.color, .line, .drawingStyle]
        case .text: [.color, .text]
        case .callout: [.color, .line, .fill, .text]
        case .redact: [.color]
        case .pen: [.color, .line, .smoothing]
        case .spotlight: [.spotlightShape, .spotlightOpacity]
        case .magnifier: [.magnification, .color, .line]
        case .blur: [.blur]
        case .highlight: object.effectiveHighlightStyle.mode == .freehand ? [.color, .markerWidth, .opacity] : [.color, .opacity]
        case .step: [.color, .stepShape, .stepSize]
        case .image: []
        }
    }

    @ViewBuilder private func sectionIcon(_ section: Section, object: EditorObject) -> some View {
        switch section {
        case .color:
            Circle().fill(model.activeColor.swiftUIColor)
                .overlay { Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1) }
                .frame(width: 20, height: 20)
        case .shape:
            EditorShapeIcon(kind: object.kind, corner: (object.cornerRadius ?? 0) > 0 ? 4 : 0)
                .stroke(.primary, lineWidth: 1.7).frame(width: 20, height: 20)
        case .line, .markerWidth:
            Image(systemName: "lineweight")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: 20, height: 20)
        case .fill: Image(systemName: "circle.lefthalf.filled")
        case .text: Image(systemName: "textformat.size")
        case .drawingStyle: Image(systemName: "scribble.variable")
        case .smoothing: Image(systemName: "scribble")
        case .spotlightShape: Image(systemName: "square.on.circle")
        case .spotlightOpacity: Image(systemName: "circle.lefthalf.filled")
        case .magnification: Image(systemName: "plus.magnifyingglass")
        case .blur: Image(systemName: "slider.horizontal.3")
        case .opacity: Image(systemName: "circle.lefthalf.filled")
        case .stepShape: Image(systemName: "square.on.circle")
        case .stepSize: Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
    }

    @ViewBuilder private func sectionOptions(_ section: Section, object: EditorObject) -> some View {
        switch section {
        case .color:
            colorOptions(title: object.kind.isShape ? String(localized: "Randfarbe") : String(localized: "Farbe"))
        case .shape:
            shapeOptions(object)
        case .line:
            colorOptions(title: String(localized: "Farbe"))
            lineWidthOptions
        case .fill:
            fillOptions
        case .text:
            slider(String(localized: "Schriftgröße"), id: "font", value: Binding(
                get: { Double(model.selectedObject?.fontSize ?? model.defaultFontSize) }, set: { model.updateStyle(font: CGFloat($0)) }), range: 8...200)
            HStack {
                Toggle(String(localized: "Fett"), isOn: Binding(get: { model.activeTextStyle.weight == .bold }, set: { bold in
                    var style = model.activeTextStyle; style.weight = bold ? .bold : .regular; model.updateStyle(textStyle: style)
                }))
                Toggle(String(localized: "Kursiv"), isOn: Binding(get: { model.activeTextStyle.italic }, set: { italic in
                    var style = model.activeTextStyle; style.italic = italic; model.updateStyle(textStyle: style)
                }))
            }.toggleStyle(.button)
        case .drawingStyle:
            EditorDrawingStylePicker(model: model)
            if object.kind == .arrow {
                EditorArrowBendControl(model: model)
                Button(String(localized: "Pfeil begradigen")) { model.straightenArrow() }
            }
        case .smoothing:
            Toggle(String(localized: "Strich glätten"), isOn: Binding(get: { model.activePenSmoothed }, set: { model.updatePenSmoothed($0) }))
        case .spotlightShape:
            Picker(String(localized: "Form"), selection: Binding(get: { model.activeSpotlightStyle.shape }, set: { value in
                var style = model.activeSpotlightStyle; style.shape = value; model.updateSpotlightStyle(style)
            })) {
                Text(String(localized: "Rechteck")).tag(EditorSpotlightShape.rectangle)
                Text(String(localized: "Ellipse")).tag(EditorSpotlightShape.ellipse)
            }.pickerStyle(.segmented)
        case .spotlightOpacity:
            slider(String(localized: "Abdunklung"), id: "spotlightOpacity", value: Binding(get: { model.activeSpotlightStyle.opacity * 100 }, set: { value in
                var style = model.activeSpotlightStyle; style.opacity = value / 100; model.updateSpotlightStyle(style)
            }), range: 0...95, unit: "%")
        case .magnification:
            slider(String(localized: "Vergrößerung"), id: "magnification", value: Binding(
                get: { Double(model.activeMagnification * 100) }, set: { model.updateMagnification(CGFloat($0) / 100) }), range: 150...500, unit: "%")
        case .blur:
            EditorBlurControls(model: model)
        case .opacity:
            slider(String(localized: "Deckkraft"), id: "opacity", value: Binding(
                get: { model.activeHighlightStyle.opacity * 100 }, set: { model.updateHighlightOpacity($0 / 100) }), range: 5...80, unit: "%")
        case .markerWidth:
            slider(String(localized: "Markerbreite"), id: "width", value: Binding(
                get: { Double(model.activeLineWidth) }, set: { model.updateStyle(width: CGFloat($0)) }), range: 4...160)
        case .stepShape:
            Picker(String(localized: "Form"), selection: Binding(get: { model.activeStepStyle.shape }, set: { shape in
                var style = model.activeStepStyle; style.shape = shape; model.updateStepStyle(style)
            })) {
                Text(String(localized: "Kreis")).tag(EditorStepShape.circle)
                Text(String(localized: "Rechteck")).tag(EditorStepShape.roundedRectangle)
                Text(String(localized: "Raute")).tag(EditorStepShape.diamond)
                Text(String(localized: "Pfeilmarke")).tag(EditorStepShape.pointer)
            }
            .pickerStyle(.segmented).labelsHidden()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("editor.quick.stepShape")
        case .stepSize:
            slider(String(localized: "Größe"), id: "size", value: Binding(
                get: { Double(model.activeStepSize) }, set: { model.updateStepSize(CGFloat($0)) }), range: 24...240)
        }
    }

    private func colorOptions(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(EditorColorChoice.all.prefix(6).enumerated()), id: \.offset) { index, choice in
                    let selected = model.activeColor == choice.color
                    Button { model.endStyleEditing(); model.updateStyle(color: choice.color) } label: {
                        Circle().fill(choice.color.swiftUIColor)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 0.5) }
                            .padding(3)
                            .overlay { Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2) }
                            .frame(width: 24, height: 24).contentShape(.circle)
                    }
                    .buttonStyle(.plain).help(choice.title).accessibilityLabel(choice.title)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.quick.color.\(index)")
                }
                ColorPicker(title, selection: Binding(get: { model.activeColor.swiftUIColor }, set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    model.updateStyle(color: EditorColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
                }), supportsOpacity: false)
                .labelsHidden().accessibilityLabel(title).accessibilityIdentifier("editor.quick.color.custom")
            }
        }
    }

    private func shapeOptions(_ object: EditorObject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Form")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(EditorShapeChoice.all) { choice in
                    let selected = object.kind == choice.kind && (choice.kind != .rectangle || ((object.cornerRadius ?? 0) > 0) == (choice.corner > 0))
                    Button { model.selectShape(choice.kind, corner: choice.corner, focusCanvas: false) } label: {
                        EditorShapeIcon(kind: choice.kind, corner: choice.corner > 0 ? 5 : 0)
                            .stroke(selected ? Color.accentColor : .primary, lineWidth: 1.6)
                            .frame(width: 22, height: 20).frame(maxWidth: .infinity).frame(height: 34)
                            .background(selected ? Color.accentColor.opacity(0.15) : .primary.opacity(0.04), in: .rect(cornerRadius: 8))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain).help(choice.title).accessibilityLabel(choice.title)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.quick.shape.\(choice.id)")
                }
            }
        }
    }

    private var lineWidthOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Linienbreite")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([2, 5, 10, 16], id: \.self) { width in
                    Button { model.endStyleEditing(); model.updateStyle(width: CGFloat(width)) } label: {
                        Capsule().fill(.primary).frame(width: 34, height: max(1, CGFloat(width) / 2.5))
                            .frame(maxWidth: .infinity).frame(height: 28)
                            .background(model.activeLineWidth == CGFloat(width) ? Color.accentColor.opacity(0.15) : .primary.opacity(0.04), in: .rect(cornerRadius: 8))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain).accessibilityLabel(String(localized: "Linienbreite"))
                    .accessibilityValue(Text(verbatim: "\(width) px"))
                    .accessibilityAddTraits(model.activeLineWidth == CGFloat(width) ? [.isSelected] : [])
                    .accessibilityIdentifier("editor.quick.width.\(width)")
                }
            }
        }
    }

    private var fillOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.activeKind?.isShape == true {
                Toggle(String(localized: "Rand"), isOn: Binding(get: { model.activeStroke.isEnabled }, set: { enabled in
                    var stroke = model.activeStroke; stroke.isEnabled = enabled; model.updateStyle(stroke: stroke)
                })).toggleStyle(.switch).accessibilityIdentifier("editor.quick.stroke")
            }
            HStack {
                Toggle(String(localized: "Füllung"), isOn: Binding(get: { model.activeFill.isEnabled }, set: { enabled in
                    var fill = model.activeFill; fill.isEnabled = enabled; model.updateStyle(fill: fill)
                })).toggleStyle(.switch).accessibilityIdentifier("editor.quick.fill")
                Spacer()
                ColorPicker(String(localized: "Füllfarbe"), selection: Binding(get: { model.activeFill.color.swiftUIColor }, set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    var fill = model.activeFill; fill.color = EditorColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                    model.updateStyle(fill: fill)
                }), supportsOpacity: false).labelsHidden().disabled(!model.activeFill.isEnabled)
            }
        }
    }

    private func slider(_ title: String, id: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "px") -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(0))).monospacedDigit()
                Text(verbatim: unit).foregroundStyle(.secondary)
            }.font(.caption)
            Slider(value: value, in: range, onEditingChanged: { editing in
                if editing { model.beginStyleEditing() } else { model.endStyleEditing() }
            }).accessibilityLabel(title).accessibilityIdentifier("editor.quick.\(id)")
        }
    }
}

struct EditorShapeChoice: Identifiable {
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

struct EditorShapeIcon: Shape {
    var kind: EditorObject.Kind
    var corner: CGFloat
    func path(in rect: CGRect) -> Path {
        var object = EditorObject(kind: kind, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY))
        object.cornerRadius = corner
        return Path(EditorRenderer.shapePath(object))
    }
}

struct EditorColorChoice: Identifiable {
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

extension EditorColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

/// Shared native choices in the inspector and object toolbar.
struct EditorDrawingStylePicker: View {
    let model: EditorModel
    var body: some View {
        Picker(String(localized: "Zeichenstil"), selection: Binding(
            get: { model.activeDrawingStyle }, set: { model.updateStyle(drawingStyle: $0) })) {
            Text(String(localized: "Präzise")).tag(EditorDrawingStyle.precise)
            Text(String(localized: "Handgezeichnet")).tag(EditorDrawingStyle.handDrawn)
            Text(String(localized: "Skizze")).tag(EditorDrawingStyle.sketch)
            Text(String(localized: "Marker")).tag(EditorDrawingStyle.marker)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("editor.style.drawingStyle")
    }
}

struct EditorArrowBendControl: View {
    let model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Biegung")).font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { min(100, max(-100, model.activeArrowCurvature)) }, set: { model.updateArrowCurvature($0) }), in: -100...100,
                   onEditingChanged: { editing in
                       if editing { model.beginStyleEditing() } else { model.endStyleEditing() }
                   })
                .accessibilityLabel(String(localized: "Biegung"))
                .accessibilityIdentifier("editor.arrow.bend")
        }
    }
}

/// The inspector and the compact object popover edit the same persisted filter.
struct EditorBlurControls: View {
    let model: EditorModel
    @FocusState private var strengthFocused: Bool
    private var strength: Binding<Double> {
        Binding(get: { Double(model.selectedObject?.blurRadius ?? model.defaultBlurRadius) },
                set: { model.updateStyle(blur: CGFloat($0)) })
    }
    private var strengthTitle: String {
        switch model.activeBlurStyle {
        case .gaussian: String(localized: "Stärke")
        case .pixelate: String(localized: "Blockgröße")
        case .mosaic: String(localized: "Zellgröße")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Darstellung"), selection: Binding(get: { model.activeBlurStyle }, set: { model.updateStyle(blurStyle: $0) })) {
                Text(String(localized: "Weich")).tag(EditorBlurStyle.gaussian)
                Text(String(localized: "Pixel")).tag(EditorBlurStyle.pixelate)
                Text(String(localized: "Mosaik")).tag(EditorBlurStyle.mosaic)
            }
            .pickerStyle(.segmented).controlSize(.small).labelsHidden()
            .accessibilityLabel(String(localized: "Darstellung"))
            .accessibilityIdentifier("editor.blur.style")
            HStack {
                Text(strengthTitle)
                Spacer()
                TextField(strengthTitle, value: strength, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 56)
                    .focused($strengthFocused)
                    .onChange(of: strengthFocused) { _, active in editingChanged(active) }
                    .onSubmit { editingChanged(false); strengthFocused = false }
                    .accessibilityIdentifier("editor.blur.strength")
                Text("px").foregroundStyle(.secondary)
            }
            Slider(value: strength, in: 2...80, onEditingChanged: editingChanged)
                .accessibilityLabel(strengthTitle).accessibilityIdentifier("editor.blur.strengthSlider")
        }
    }
    private func editingChanged(_ active: Bool) {
        if active { model.beginStyleEditing() } else { model.endStyleEditing() }
    }
}

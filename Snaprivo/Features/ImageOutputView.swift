import SwiftUI
import AppKit
import SnagForgeDomain

/// Backgrounds and angle are edited in the document window, with document undo and autosave.
struct EditorPresentationInspector: View {
    @Bindable var model: EditorModel
    @State private var presets = PresentationPresetStore.load()
    @State private var importing = false
    @State private var failure: String?
    @State private var importID = UUID()
    @State private var importTask: Task<Void, Never>?
    @State private var showsAllGradients = false
    @State private var browsedBackgroundMode = BackgroundMode.gradient
    @FocusState private var angleFieldHasFocus: Bool
    private var value: EditorPresentation { model.history.presentation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Eigenschaften")).font(.headline)
                        Text(String(localized: "Gestaltung")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.endPresentationEditing(); model.isEditingPresentation = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel(String(localized: "Gestaltung schließen"))
                }
                if model.hasProAccess() {
                    EditorImageFrameControls(radius: binding(\.cornerRadius), border: binding(\.border), onEditingChanged: editingChanged)
                    Divider()
                }
                rotationControls
                Divider()
                if model.hasProAccess() {
                    backgroundControls
                } else {
                    Button(String(localized: "Präsentationshintergründe · Pro"), systemImage: "lock") { _ = model.requestFeature(.presentation) }
                }
                if importing { ProgressView().controlSize(.small) }
                if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.visible)
        .accessibilityIdentifier("editor.presentation.inspector")
        .onDisappear { importTask?.cancel(); model.endPresentationEditing() }
    }
    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Drehwinkel"))
                Spacer()
                TextField(String(localized: "Drehwinkel"), value: binding(\.rotationDegrees), format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 64)
                    .focused($angleFieldHasFocus)
                    .onSubmit { model.endPresentationEditing(); angleFieldHasFocus = false }
                    .onChange(of: angleFieldHasFocus) { _, focused in
                        if focused { model.beginPresentationEditing() } else { model.endPresentationEditing() }
                    }
                    .accessibilityIdentifier("editor.presentation.angle")
                Text("°")
            }
            Slider(value: Binding(get: { value.rotationDegrees }, set: { number in edit { $0.rotationDegrees = (number * 10).rounded() / 10 } }), in: -180...180, onEditingChanged: editingChanged)
                .accessibilityLabel(String(localized: "Drehwinkel"))
                .accessibilityIdentifier("editor.presentation.angleSlider")
            HStack {
                Button(String(localized: "90° links"), systemImage: "rotate.left") { model.transformImage(model.history.transform.rotated(clockwise: false)) }
                    .help(String(localized: "90° links"))
                Button(String(localized: "90° rechts"), systemImage: "rotate.right") { model.transformImage(model.history.transform.rotated()) }
                    .help(String(localized: "90° rechts"))
                Button(String(localized: "Ausrichtung zurücksetzen"), systemImage: "arrow.uturn.backward") {
                    model.transformImage(.identity); edit { $0.rotationDegrees = 0 }
                }.help(String(localized: "Ausrichtung zurücksetzen"))
                    .disabled(value.rotationDegrees == 0 && model.history.transform == .identity)
                Spacer()
            }.labelStyle(.iconOnly).controlSize(.small)
        }
    }
    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Hintergrund")).font(.headline)
                Spacer()
                Button(String(localized: "Keiner")) {
                    browsedBackgroundMode = .gradient
                    edit { $0.background = nil }
                }.accessibilityIdentifier("editor.presentation.none")
            }
            Picker(String(localized: "Hintergrundtyp"), selection: Binding(get: { backgroundMode }, set: setBackgroundMode)) {
                Text(String(localized: "Keiner")).tag(BackgroundMode.none)
                Text(String(localized: "Farbe")).tag(BackgroundMode.solid)
                Text(String(localized: "Verläufe")).tag(BackgroundMode.gradient)
                Text(String(localized: "Eigenes Bild …")).tag(BackgroundMode.image)
            }.accessibilityIdentifier("editor.presentation.backgroundType")
            if backgroundMode == .solid {
            ColorPicker(String(localized: "Hintergrundfarbe"), selection: Binding(get: {
                if case .solid(let color) = value.background { return Color(red: color.red, green: color.green, blue: color.blue) }
                return .white
            }, set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                edit { p in p.background = .solid(EditorColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)); enableFrame(&p) }
            }), supportsOpacity: false)
            }
            if backgroundMode == .gradient {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(PresentationBackgroundCatalog.gradients.enumerated().prefix(showsAllGradients ? 20 : 10)), id: \.offset) { index, gradient in
                    Button {
                        edit { p in p.background = .gradient(gradient); enableFrame(&p) }
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: gradient.colors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 32)
                            .overlay { RoundedRectangle(cornerRadius: 6).stroke(value.background == .gradient(gradient) ? Color.accentColor : Color.clear, lineWidth: 3) }
                    }.buttonStyle(.plain).accessibilityLabel(String(localized: "Farbverlauf \(index + 1)"))
                        .accessibilityIdentifier("editor.presentation.gradient.\(index)")
                }
            }
            Button(showsAllGradients ? String(localized: "Weniger Verläufe") : String(localized: "Alle Verläufe")) { showsAllGradients.toggle() }
                .controlSize(.small)
            }
            Button(String(localized: "Eigenes Bild …"), systemImage: "photo.badge.plus") { importBackground() }.disabled(importing)
            if case .asset(_, let blur) = value.background {
                Toggle(String(localized: "Weichzeichnen"), isOn: Binding(get: { blur > 0 }, set: { enabled in
                    edit { p in if case .asset(let asset, _) = p.background { p.background = .asset(asset, blur: enabled ? 24 : 0) } }
                }))
            }
            Picker(String(localized: "Seitenverhältnis"), selection: binding(\.aspectRatio)) {
                ForEach(PresentationAspectRatio.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker(String(localized: "Ausrichtung"), selection: binding(\.alignment)) {
                ForEach(PresentationAlignment.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            metric(String(localized: "Außenabstand"), value: Binding(get: { Double(value.padding) }, set: { number in edit { $0.padding = Int(number) } }), range: 0...200, suffix: "px")
            metric(String(localized: "Schattenstärke"), value: Binding(get: { value.shadowStrength * 100 }, set: { number in edit { $0.shadowStrength = number / 100 } }), range: 0...100, suffix: "%")
            Menu {
                Button(String(localized: "Vorlage speichern")) { savePreset() }
                ForEach(presets) { preset in
                    Button(preset.name) { applyPreset(preset) }
                    Button(String(localized: "Umbenennen: \(preset.name)")) { renamePreset(preset) }
                    Button(String(localized: "Löschen: \(preset.name)"), role: .destructive) {
                        presets.removeAll { $0.id == preset.id }; _ = PresentationPresetStore.save(presets)
                    }
                }
            } label: { Label(String(localized: "Vorlagen"), systemImage: "square.stack") }
        }
    }
    private enum BackgroundMode: Hashable { case none, solid, gradient, image }
    private var backgroundMode: BackgroundMode {
        switch value.background { case nil: browsedBackgroundMode; case .solid: .solid; case .gradient: .gradient; case .asset, .image: .image }
    }
    private func setBackgroundMode(_ mode: BackgroundMode) {
        browsedBackgroundMode = mode
        switch mode {
        case .none: edit { $0.background = nil }
        case .solid: edit { p in p.background = .solid(EditorColor(red: 1, green: 1, blue: 1)); enableFrame(&p) }
        case .gradient: edit { p in p.background = .gradient(PresentationBackgroundCatalog.gradients[0]); enableFrame(&p) }
        case .image: importBackground()
        }
    }
    private func binding<T>(_ path: WritableKeyPath<EditorPresentation, T>) -> Binding<T> {
        Binding(get: { value[keyPath: path] }, set: { next in edit { $0[keyPath: path] = next } })
    }
    private func edit(_ change: (inout EditorPresentation) -> Void) {
        var next = value; change(&next); model.updatePresentation(next)
    }
    private func editingChanged(_ active: Bool) {
        if active { model.beginPresentationEditing() } else { model.endPresentationEditing() }
    }
    private func enableFrame(_ presentation: inout EditorPresentation) {
        if value.background == nil && presentation.padding == 0 { presentation.padding = 40 }
    }
    private func metric(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, onEditingChanged: editingChanged).accessibilityLabel(title)
        }
    }
    private func importBackground() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        loadBackground(source)
    }
    private func loadBackground(_ source: URL, preset: EditorPresentation? = nil) {
        importTask?.cancel(); importing = true; failure = nil
        let request = UUID(); importID = request
        let access = source.startAccessingSecurityScopedResource()
        importTask = Task {
            defer { if access { source.stopAccessingSecurityScopedResource() }; if importID == request { importing = false; importTask = nil } }
            do {
                let task = Task.detached(priority: .userInitiated) { try PresentationBackgroundStorage.importAsset(from: source) }
                let asset = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                var next = preset ?? value; next.background = .asset(asset, blur: 0); if preset == nil { enableFrame(&next) }
                model.updatePresentation(next)
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }
    private func applyPreset(_ preset: PresentationPreset) {
        let next = preset.options.presentation
        if case .image(let path, _) = next.background { loadBackground(URL(fileURLWithPath: path), preset: next) }
        else { model.updatePresentation(next) }
    }
    private func named(_ title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 240, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Sichern")); alert.addButton(withTitle: String(localized: "Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !name.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        return name
    }
    private func savePreset() {
        guard let name = named(String(localized: "Vorlage speichern"), initial: String(localized: "Meine Vorlage")) else { return }
        var next = presets.filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
        next.append(PresentationPreset(name: name, options: ImageOutputOptions(presentation: value))); next = Array(next.suffix(32))
        if PresentationPresetStore.save(next) { presets = next } else { failure = String(localized: "Die Vorlagen überschreiten die unterstützte Dateigröße.") }
    }
    private func renamePreset(_ preset: PresentationPreset) {
        guard let name = named(String(localized: "Vorlage umbenennen"), initial: preset.name),
              !presets.contains(where: { $0.id != preset.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var next = presets; next[index].name = name
        if PresentationPresetStore.save(next) { presets = next }
    }
}

private struct PresentationContentRequest: Equatable {
    let project: UUID
    let objects: [EditorObject]
    let crop: CGRect?
    let resizedSize: PixelSize?
    let canvasRect: CGRect?
    let transform: EditorImageTransform
    let presentation: EditorPresentation?
}

/// Source pixels are prepared once. Angle, corners and frame draw directly during interaction.
struct EditorPresentationPreview: View {
    let model: EditorModel
    var interactive = false
    @State private var preview: CGImage?
    @State private var wallpaper: CGImage?
    @State private var wallpaperFailure: String?
    @State private var failure: String?
    private var request: PresentationContentRequest {
        PresentationContentRequest(project: model.document.id, objects: model.history.objects, crop: model.history.crop,
            resizedSize: model.history.resizedSize, canvasRect: model.history.canvasRect, transform: model.history.transform,
            presentation: interactive ? nil : model.history.presentation)
    }
    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let preview {
                if interactive {
                    PresentationPreviewSurface(model: model, image: preview, wallpaper: wallpaper)
                } else {
                    Image(decorative: preview, scale: 1).resizable().scaledToFit().padding(24)
                        .accessibilityLabel(String(localized: "Live-Vorschau der Gestaltung"))
                }
            } else if failure == nil { ProgressView() }
            if let failure = failure ?? wallpaperFailure { Text(failure).foregroundStyle(.red).padding(24).textSelection(.enabled) }
        }
        .accessibilityIdentifier("editor.presentation.preview")
        .task(id: request) {
            guard let snapshot = model.pngShareItemForToolbar else { return }
            let presentation = interactive ? nil : snapshot.presentation
            do {
                let task = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    return try EditorRenderer.render(image: snapshot.image, objects: snapshot.objects, crop: snapshot.crop,
                        resizedSize: snapshot.resizedSize, maxDimension: 4096, canvasRect: snapshot.canvasRect,
                        transform: snapshot.transform, presentation: presentation)
                }
                let image = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation(); preview = image; failure = nil
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
        .task(id: interactive ? model.history.presentation.background : nil) {
            wallpaper = nil; wallpaperFailure = nil
            guard interactive else { return }
            let background = model.history.presentation.background
            do {
                let task = Task.detached(priority: .userInitiated) { try EditorRenderer.preparePresentationWallpaper(background) }
                let image = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation(); wallpaper = image
            } catch { if !Task.isCancelled { wallpaperFailure = error.localizedDescription } }
        }
    }
}

private struct PresentationPreviewSurface: NSViewRepresentable {
    let model: EditorModel
    let image: CGImage
    let wallpaper: CGImage?
    func makeNSView(context: Context) -> PresentationPreviewView { PresentationPreviewView(model: model, image: image) }
    func updateNSView(_ view: PresentationPreviewView, context: Context) {
        _ = model.viewport; _ = model.history.presentation
        view.image = image; view.wallpaper = wallpaper; view.synchronizeViewport(); view.needsDisplay = true
    }
}
final class PresentationPreviewView: NSView {
    let model: EditorModel
    var image: CGImage
    var wallpaper: CGImage?
    private var dragPoint: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(model: EditorModel, image: CGImage) {
        self.model = model; self.image = image; super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = true
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Live-Vorschau der Gestaltung"))
        setAccessibilityHelp(String(localized: "Scrollen verschiebt das Bild. Mit Befehl und Mausrad oder Aufziehen zoomen."))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func layout() { super.layout(); synchronizeViewport() }
    func synchronizeViewport() {
        if model.viewportBounds != bounds { model.viewportBounds = bounds }
        let scale = window?.backingScaleFactor ?? 2
        if model.viewportBackingScale != scale { model.viewportBackingScale = scale }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let sourceSize = model.document.contentPixelSize, presentation = model.history.presentation
        guard let rect = presentation.previewRect(for: sourceSize, viewport: model.viewport, in: bounds,
                                                   backingScale: window?.backingScaleFactor ?? 2),
              let geometry = presentation.geometry(for: sourceSize) else { return }
        let scale = rect.width / CGFloat(geometry.outputSize.width)
        context.saveGState(); defer { context.restoreGState() }
        context.clip(to: bounds)
        context.translateBy(x: rect.minX, y: rect.minY); context.scaleBy(x: scale, y: scale)
        try? EditorRenderer.drawPresentationScene(image, sourceSize: CGSize(width: sourceSize.width, height: sourceSize.height),
            presentation: presentation, in: context, preparedWallpaper: wallpaper, usesPreparedWallpaper: true,
            effectScale: scale * (window?.backingScaleFactor ?? 2))
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { model.zoomBy(exp(event.scrollingDeltaY * 0.01), at: convert(event.locationInWindow, from: nil)) }
        else { model.panImage(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)) }
        needsDisplay = true
    }
    override func magnify(with event: NSEvent) {
        model.zoomBy(max(0.1, 1 + event.magnification), at: convert(event.locationInWindow, from: nil)); needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); dragPoint = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let old = dragPoint { model.panImage(by: CGSize(width: point.x - old.x, height: point.y - old.y)) }
        dragPoint = point; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragPoint = nil }
}

/// Export controls only; presentation is edited inline and already belongs to the snapshot.
struct ImageOutputView: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var format = ImageOutputOptions.restored().format
    @State private var quality = ImageOutputOptions.restored().quality
    @State private var writing = false
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Bildausgabe")).font(.title2.bold())
            Picker(String(localized: "Format"), selection: $format) {
                ForEach(ImageOutputFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
            }.pickerStyle(.segmented)
            if format == .jpeg {
                HStack { Text(String(localized: "Qualität")); Slider(value: $quality, in: 0.1...1); Text("\(Int(quality * 100)) %").monospacedDigit() }
            }
            EditorPresentationPreview(model: model)
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(String(localized: "Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Als PNG kopieren")) { model.copyPNG(); dismiss() }
                Button(String(localized: "Speichern …")) { save() }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(minWidth: 640, idealWidth: 760, minHeight: 480, idealHeight: 620)
            .disabled(writing).interactiveDismissDisabled(writing)
    }
    private func save() {
        guard let snapshot = model.pngShareItemForToolbar else { return }
        var options = ImageOutputOptions(); options.format = format; options.quality = quality
        let requested = options
        let panel = NSSavePanel(); panel.allowedContentTypes = [requested.format.type]
        panel.nameFieldStringValue = model.name + "." + (format == .jpeg ? "jpg" : format.rawValue)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writing = true
        Task {
            defer { writing = false }
            let saved = await model.exportPreparedOutput(to: url) {
                try await Task.detached {
                    let composed = try EditorRenderer.render(image: snapshot.image, objects: snapshot.objects, crop: snapshot.crop,
                        resizedSize: snapshot.resizedSize, canvasRect: snapshot.canvasRect, transform: snapshot.transform, presentation: snapshot.presentation)
                    let output = try ImageOutput.compose(composed, options: requested)
                    return try ImageOutput.encode(output, options: requested)
                }.value
            }
            if saved {
                if let data = try? JSONEncoder().encode(requested) { UserDefaults.standard.set(data, forKey: "image.output.options.v1") }
                dismiss()
            } else { failure = model.error }
        }
    }
}

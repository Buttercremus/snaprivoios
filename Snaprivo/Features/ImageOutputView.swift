import SwiftUI
import AppKit
import SnagForgeDomain

struct ImageOutputView: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var options = ImageOutputOptions.restored()
    @State private var base: CGImage?
    @State private var preview: CGImage?
    @State private var failure: String?
    @State private var writing = false
    @State private var renderedOptions: ImageOutputOptions?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Bildausgabe")).font(.title2.bold())
            Picker(String(localized: "Format"), selection: $options.format) {
                ForEach(ImageOutputFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
            }.pickerStyle(.segmented)
            if options.format == .jpeg {
                HStack {
                    Text(String(localized: "Qualität"))
                    Slider(value: $options.quality, in: 0.1...1)
                    Text("\(Int(options.quality * 100)) %").monospacedDigit()
                }
            }
            if !model.hasProAccess() {
                Button(String(localized: "Präsentationshintergründe · Pro"), systemImage: "lock") { _ = model.requestFeature(.presentation) }
            } else {
            DisclosureGroup(String(localized: "Hintergrund, Abstand & Schatten")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(String(localized: "Präsentation")) {
                            options.padding = 64; options.cornerRadius = 20; options.shadow = true
                            options.background = EditorColor(red: 0.89, green: 0.91, blue: 0.97)
                        }
                        Button(String(localized: "Ohne Rahmen")) { options.padding = 0; options.cornerRadius = 0; options.shadow = false }
                    }
                    backgroundPicker
                    HStack {
                        Text(String(localized: "Außenabstand"))
                        Slider(value: Binding(get: { Double(options.padding) }, set: { options.padding = Int($0) }), in: 0...200, step: 1)
                        Text("\(options.padding) px").monospacedDigit().frame(width: 60)
                    }
                    HStack {
                        Text(String(localized: "Runde Ecken"))
                        Slider(value: $options.cornerRadius, in: 0...100, step: 1)
                        Text("\(Int(options.cornerRadius)) px").monospacedDigit().frame(width: 60)
                    }
                    Toggle(String(localized: "Schatten"), isOn: $options.shadow)
                    Text(String(localized: "Gestaltung für diese Ausgabe. Die Einstellungen werden für die nächste Ausgabe gemerkt.")).font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            }
            if let preview {
                Image(decorative: preview, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(preview.width) × \(preview.height) px").font(.caption).foregroundStyle(.secondary)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let failure { Text(failure).foregroundStyle(.red).font(.caption) }
            HStack {
                Button(String(localized: "Schließen")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(writing)
                Spacer()
                Button(String(localized: "Als PNG kopieren")) { copy() }
                    .disabled(preview == nil || renderedOptions != options || writing)
                Button(String(localized: "Speichern …")) { save() }.buttonStyle(.borderedProminent)
                    .disabled(preview == nil || renderedOptions != options || writing)
            }
        }.padding(24).frame(width: 700, height: 650).disabled(writing)
        .interactiveDismissDisabled(writing)
        .onChange(of: model.hasProAccess(), initial: true) { _, hasPro in
            if !hasPro { options = options.withoutPresentation }
        }
        .onChange(of: options) { _, value in
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "image.output.options.v1") }
        }
        .task {
            let image = model.image, objects = model.history.objects, crop = model.history.crop, resized = model.history.resizedSize
            do { base = try await Task.detached { try EditorRenderer.render(image: image, objects: objects, crop: crop, resizedSize: resized) }.value; await refresh() }
            catch { failure = error.localizedDescription }
        }
        .task(id: "\(options.format.rawValue)-\(options.quality)-\(options.background)-\(options.padding)-\(options.cornerRadius)-\(options.shadow)") { await refresh() }
    }
    private var backgroundPicker: some View {
        ColorPicker(String(localized: "Hintergrundfarbe"), selection: Binding(get: {
            Color(red: options.background.red, green: options.background.green, blue: options.background.blue)
        }, set: { value in
            guard let c = NSColor(value).usingColorSpace(.sRGB) else { return }
            options.background = EditorColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
        }), supportsOpacity: false)
    }
    private func refresh() async {
        guard let base else { return }
        let requested = options
        do {
            let result = try await ImageOutputProcessor.shared.compose(base, options: requested)
            guard !Task.isCancelled, options == requested else { return }
            preview = result; renderedOptions = requested; failure = nil
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
    private func copy() {
        guard let preview, renderedOptions == options else { return }
        guard !options.hasPresentation || model.requestFeature(.presentation) else { return }
        var requested = options; requested.format = .png
        let outputOptions = requested
        writing = true
        Task {
            defer { writing = false }
            do {
                let data = try await Task.detached { try ImageOutput.encode(preview, options: outputOptions) }.value
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.setData(data, forType: .png) { dismiss() }
                else { failure = String(localized: "Speichern fehlgeschlagen") }
            } catch { failure = error.localizedDescription }
        }
    }
    private func save() {
        guard let preview, renderedOptions == options else { return }
        guard !options.hasPresentation || model.requestFeature(.presentation) else { return }
        let requested = options
        let panel = NSSavePanel(); panel.allowedContentTypes = [requested.format.type]
        panel.nameFieldStringValue = model.name + "." + (requested.format == .jpeg ? "jpg" : requested.format.rawValue)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writing = true
        Task {
            defer { writing = false }
                let saved = await model.exportPreparedOutput(to: url) {
                    try await Task.detached { try ImageOutput.encode(preview, options: requested) }.value
                }
                guard saved else { failure = model.error ?? String(localized: "Speichern fehlgeschlagen"); return }
                dismiss()
        }
    }
}

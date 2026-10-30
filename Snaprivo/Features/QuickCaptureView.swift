import AppKit
import Observation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import SnagForgeDomain

/// A single flattened file supplies both the thumbnail and external file drags.
struct QuickCapturePayload: Sendable {
    let file: URL
    let preview: CGImage
    static func prepare(_ snapshot: EditorPNGShare, in root: URL,
                        decode: @escaping @Sendable (URL) throws -> CGImage = decodeThumbnail) async throws -> Self {
        try Task.checkCancellation()
        let file = try await snapshot.writeTemporaryPNG(in: root)
        do {
            try Task.checkCancellation()
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let preview = try decode(file)
                try Task.checkCancellation()
                return Self(file: file, preview: preview)
            }
            return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        } catch {
            await Task.detached { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }.value
            throw error
        }
    }
    private static func decodeThumbnail(_ file: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 720
              ] as CFDictionary) else { throw ProjectError.invalidDocument }
        return preview
    }
}

struct QuickCaptureView: View {
    let workspace: WorkspaceModel
    @Bindable var model: EditorModel
    var onClose: () -> Void = {}
    @State private var isDiscarding = false
    @State private var renderedFile: URL?
    @State private var renderedImage: CGImage?
    @State private var renderError: String?
    @State private var recognition = QuickImageRecognitionModel()
    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Aufnahme bereit")).font(.headline)
            Group {
                if let renderedImage { Image(decorative: renderedImage, scale: 1).resizable().scaledToFit() }
                else { ProgressView().controlSize(.small) }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(String(localized: "Vorschau der neuen Aufnahme"))
                .onDrag {
                    guard let renderedFile, let provider = NSItemProvider(contentsOf: renderedFile) else { return NSItemProvider() }
                    provider.suggestedName = model.pngShareItemForToolbar?.fileName
                    return provider
                }
                .overlay(alignment: .bottomLeading) {
                    if renderedFile == nil {
                        Label(String(localized: "Vorschau wird vorbereitet …"), systemImage: "arrow.down.circle")
                            .font(.caption).padding(7).background(.regularMaterial, in: .capsule).padding(8)
                    }
                }
            HStack(spacing: 8) {
                Button(String(localized: "Kopieren"), systemImage: "doc.on.doc") { model.copyPNG() }.keyboardShortcut("c").help(String(localized: "PNG kopieren"))
                Button(String(localized: "PNG exportieren …"), systemImage: "square.and.arrow.down") { model.exportPNG() }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).help(String(localized: "PNG exportieren …"))
                    .disabled(!model.hasExportableImage || model.isExporting)
                Button(String(localized: "Markieren"), systemImage: "pencil.tip") { workspace.editQuickCapture(model); onClose() }.keyboardShortcut(.defaultAction).help(String(localized: "Im Editor öffnen"))
                PinImageButton(model: model, size: workspace.preferences.toolbarSize, iconOnly: true)
                Spacer()
                Button(String(localized: "Verwerfen"), systemImage: "trash") {
                    isDiscarding = true
                    Task { await workspace.discardQuickCapture(model); isDiscarding = false; if workspace.quickCapture == nil { onClose() } }
                }.disabled(isDiscarding)
            }.labelStyle(.iconOnly)
            HStack(spacing: 12) {
                Button(String(localized: "Text kopieren"), systemImage: "text.viewfinder") { recognize(codesOnly: false) }
                    .accessibilityIdentifier("quickCapture.copyText")
                Button(String(localized: "QR lesen"), systemImage: "qrcode.viewfinder") { recognize(codesOnly: true) }
                    .accessibilityIdentifier("quickCapture.scanCode")
                if recognition.isBusy { ProgressView().controlSize(.small) }
            }.font(.callout).disabled(recognition.isBusy || !model.hasConfirmedImageForToolbar)
            if !recognition.codes.isEmpty { RecognitionCodeResults(model: recognition, compact: true) }
            if let message = recognition.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error = recognition.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack(spacing: 8) {
                Text(model.copyState == .copied ? String(localized: "Kopiert") : String(localized: "Gesichert"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Schließen")) { onClose() }.keyboardShortcut(.cancelAction)
            }
            if let error = renderError ?? model.error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .padding(12).frame(minWidth: 300, idealWidth: 360, minHeight: 280, idealHeight: 340)
        .onDisappear { recognition.cancel() }
        .task(id: model.document.revision) {
            recognition.cancel()
            guard model.hasConfirmedImageForToolbar else { return }
            renderedFile = nil; renderedImage = nil; renderError = nil
            guard let snapshot = model.pngShareItemForToolbar else { return }
            do {
                let prepared = try await QuickCapturePayload.prepare(snapshot, in: FileManager.default.temporaryDirectory.appendingPathComponent("QuickCaptureTransfers", isDirectory: true))
                guard !Task.isCancelled else { return }
                renderedFile = prepared.file; renderedImage = prepared.preview
            } catch { if !Task.isCancelled { renderError = error.localizedDescription } }
        }
    }
    private func recognize(codesOnly: Bool) {
        guard model.requestFeature(.textRecognition), let snapshot = model.pngShareItemForToolbar else { return }
        let revision = model.document.revision
        recognition.recognize(snapshot, codesOnly: codesOnly, canUse: { model.hasProAccess() && model.document.revision == revision && QuickCapturePanelController.shared.isVisible })
    }
}

/// A compact, persistent stack. Every thumbnail refers to its own saved project.
private struct QuickCaptureStack: View {
    let workspace: WorkspaceModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focusedCapture: UUID?
    var body: some View {
        VStack(spacing: 10) {
            if workspace.showsDirectCaptureResult { DirectCaptureResultCard(workspace: workspace) }
            if !workspace.quickCaptures.isEmpty {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(workspace.quickCaptures, id: \.document.id) { model in
                                QuickCaptureThumbnail(workspace: workspace, model: model,
                                    isSelected: workspace.selectedQuickCaptureID == model.document.id,
                                    focus: $focusedCapture, moveSelection: moveSelection,
                                    close: { dismiss(model) })
                                    .id(model.document.id)
                                    .transition(.identity)
                            }
                        }.padding(2)
                    }.scrollIndicators(.hidden)
                        .onChange(of: focusedCapture) { _, id in
                            guard let id else { return }
                            workspace.selectedQuickCaptureID = id
                            reader.scrollTo(id)
                        }
                }
                HStack(spacing: 8) {
                    Text(String(localized: "Letzte Aufnahmen")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Ausblenden"), systemImage: "chevron.down") { QuickCapturePanelController.shared.hide() }
                        .labelStyle(.iconOnly).help(String(localized: "Vorschauen ausblenden"))
                }.padding(.horizontal, 8).padding(.vertical, 5)
                    .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial), in: .capsule)
            }
        }
        .padding(8)
        .onChange(of: workspace.quickCaptures.map { $0.document.id }) { _, _ in QuickCapturePanelController.shared.refreshLayout() }
        .onChange(of: workspace.selectedQuickCaptureID) { _, id in
            if focusedCapture != nil { focusedCapture = id }
        }
        .onChange(of: workspace.showsDirectCaptureResult) { _, _ in QuickCapturePanelController.shared.refreshLayout(animated: true) }
        .onChange(of: workspace.isDirectOCRBusy) { _, _ in QuickCapturePanelController.shared.refreshLayout(animated: true) }
        .onChange(of: workspace.directCaptureNotice) { _, _ in QuickCapturePanelController.shared.refreshLayout(animated: true) }
        .onChange(of: workspace.directCaptureError) { _, _ in QuickCapturePanelController.shared.refreshLayout(animated: true) }
        .task { focusedCapture = workspace.selectedQuickCaptureID }
        .task(id: workspace.quickCaptureFocusRequest) {
            guard workspace.quickCaptureFocusRequest > 0 else { return }
            focusedCapture = nil
            await Task.yield()
            focusedCapture = workspace.selectedQuickCaptureID ?? workspace.quickCaptures.first?.document.id
        }
        .onExitCommand { QuickCapturePanelController.shared.hide() }
    }
    private func moveSelection(_ offset: Int) {
        workspace.moveQuickCaptureSelection(by: offset)
        focusedCapture = workspace.selectedQuickCaptureID
    }
    private func dismiss(_ model: EditorModel) {
        let movesKeyboardFocus = focusedCapture == model.document.id
        workspace.dismissQuickCapture(model)
        if movesKeyboardFocus { focusedCapture = workspace.selectedQuickCaptureID }
    }
}

private struct QuickCaptureThumbnail: View {
    let workspace: WorkspaceModel
    @Bindable var model: EditorModel
    let isSelected: Bool
    let focus: FocusState<UUID?>.Binding
    let moveSelection: (Int) -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var payload: QuickCapturePayload?
    @State private var error: String?
    @State private var showsDetails = false
    @State private var isHovered = false
    @State private var showsRecognition = false
    @State private var readsCodes = false
    @State private var recognitionRevision: Int?
    @State private var recognition = QuickImageRecognitionModel()
    @FocusState private var closeIsFocused: Bool
    @AccessibilityFocusState private var closeHasAccessibilityFocus: Bool
    private var showsHoverActions: Bool { isHovered || showsRecognition }
    private var showsCloseButton: Bool { isHovered || closeIsFocused || closeHasAccessibilityFocus }
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Button { workspace.editQuickCapture(model) } label: {
                    Group {
                        if let preview = payload?.preview { Image(decorative: preview, scale: 1).resizable().scaledToFit() }
                        else { ProgressView().controlSize(.small) }
                    }.frame(maxWidth: .infinity).frame(height: 112).contentShape(.rect)
                }.buttonStyle(.plain).help(String(localized: "Im Editor öffnen"))
                    .accessibilityLabel(model.name)
                    .accessibilityValue(isSelected ? String(localized: "Ausgewählt") : "")
                    .accessibilityHint(String(localized: "Pfeiltasten wählen eine Aufnahme, Eingabe öffnet den Editor, Rückschritt schließt die Vorschau."))
                    .accessibilityIdentifier("quickCapture.open.\(model.document.id)")
                    .focusable()
                    .focused(focus, equals: model.document.id)
                    .onKeyPress(.return) { workspace.editQuickCapture(model); return .handled }
                    .onKeyPress(.delete) { close(); return .handled }
                    .onMoveCommand { direction in
                        switch direction {
                        case .up, .left: moveSelection(-1)
                        case .down, .right: moveSelection(1)
                        default: break
                        }
                    }
                    .onDeleteCommand(perform: close)
                    .onDrag {
                        guard let file = payload?.file, let provider = NSItemProvider(contentsOf: file) else { return NSItemProvider() }
                        provider.suggestedName = model.pngShareItemForToolbar?.fileName
                        return provider
                    }
                HStack(spacing: 6) {
                    Button(String(localized: "Kopieren"), systemImage: "doc.on.doc") { model.copyPNG() }
                        .accessibilityIdentifier("quickCapture.hover.copy")
                    Button(String(localized: "Text"), systemImage: "text.viewfinder") { recognize(codesOnly: false) }
                        .accessibilityIdentifier("quickCapture.hover.text")
                    Button(String(localized: "QR"), systemImage: "qrcode.viewfinder") { recognize(codesOnly: true) }
                        .accessibilityIdentifier("quickCapture.hover.code")
                }
                .font(.callout).labelStyle(.titleOnly).controlSize(.small).buttonStyle(.bordered)
                .padding(7).background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial), in: .capsule).padding(.bottom, 8)
                .opacity(showsHoverActions ? 1 : 0).allowsHitTesting(showsHoverActions)
                .accessibilityHidden(!showsHoverActions)
                .disabled(recognition.isBusy || !model.hasConfirmedImageForToolbar)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                        .background(Color(nsColor: .windowBackgroundColor), in: .circle)
                        .contentShape(.circle)
                        .opacity(showsCloseButton ? 1 : 0)
                }
                    .buttonStyle(.plain)
                    .focused($closeIsFocused)
                    .accessibilityFocused($closeHasAccessibilityFocus)
                    .accessibilityLabel(String(localized: "Vorschau schließen"))
                    .accessibilityHidden(false)
                    .accessibilityIdentifier("quickCapture.thumbnail.close")
                    .allowsHitTesting(showsCloseButton)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: showsCloseButton)
                    .padding(8).help(String(localized: "Vorschau schließen; Aufnahme bleibt in der Bibliothek"))
            }
            HStack(spacing: 7) {
                Button(String(localized: "Kopieren"), systemImage: "doc.on.doc") { model.copyPNG() }
                    .labelStyle(.iconOnly).help(String(localized: "PNG kopieren"))
                Button(String(localized: "PNG exportieren …"), systemImage: "square.and.arrow.down") { model.exportPNG() }
                    .labelStyle(.iconOnly).help(String(localized: "PNG exportieren …"))
                PinImageButton(model: model, size: workspace.preferences.toolbarSize, iconOnly: true)
                Button(String(localized: "Text kopieren"), systemImage: "text.viewfinder") { recognize(codesOnly: false) }
                    .labelStyle(.iconOnly).help(String(localized: "Text erkennen und kopieren"))
                    .accessibilityIdentifier("quickCapture.thumbnail.copyText")
                    .disabled(recognition.isBusy || !model.hasConfirmedImageForToolbar)
                Button(String(localized: "QR lesen"), systemImage: "qrcode.viewfinder") { recognize(codesOnly: true) }
                    .labelStyle(.iconOnly).help(String(localized: "QR lesen"))
                    .accessibilityIdentifier("quickCapture.thumbnail.scanCode")
                    .disabled(recognition.isBusy || !model.hasConfirmedImageForToolbar)
                Spacer(minLength: 0)
                if model.copyState == .copied { Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel(String(localized: "Kopiert")) }
                Button(String(localized: "Mehr"), systemImage: "ellipsis") { showsDetails = true }
                    .labelStyle(.iconOnly).help(String(localized: "Weitere Bildaktionen"))
                    .popover(isPresented: $showsDetails) {
                        QuickCaptureView(workspace: workspace, model: model) { showsDetails = false }
                    }
            }.font(.callout).buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 34)
                .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
            if let error = error ?? model.error { Text(error).font(.caption2).foregroundStyle(.red).padding(6) }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.12)), lineWidth: contrast == .increased ? 2 : 0.5).allowsHitTesting(false) }
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: showsHoverActions)
        .popover(isPresented: $showsRecognition) {
            QuickCaptureRecognitionResult(recognition: recognition, codesOnly: readsCodes,
                canUse: { model.hasProAccess() && model.document.revision == recognitionRevision && workspace.quickCaptures.contains { $0 === model } },
                retry: { recognize(codesOnly: readsCodes) }, close: { showsRecognition = false })
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickCapture.thumbnail.\(model.document.id)")
        .onDisappear { recognition.cancel() }
        .task(id: model.document.revision) {
            recognition.cancel()
            guard let snapshot = model.pngShareItemForToolbar else { return }
            do {
                let prepared = try await QuickCapturePayload.prepare(snapshot, in: FileManager.default.temporaryDirectory.appendingPathComponent("QuickCaptureTransfers", isDirectory: true))
                guard !Task.isCancelled else { return }
                payload = prepared; error = nil
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func recognize(codesOnly: Bool) {
        guard model.requestFeature(.textRecognition), let snapshot = model.pngShareItemForToolbar else { return }
        readsCodes = codesOnly; showsRecognition = true
        let revision = model.document.revision; recognitionRevision = revision
        recognition.recognize(snapshot, codesOnly: codesOnly, canUse: {
            model.hasProAccess() && model.document.revision == revision && workspace.quickCaptures.contains { $0 === model }
                && QuickCapturePanelController.shared.isVisible
        })
    }
}

private struct QuickCaptureRecognitionResult: View {
    let recognition: QuickImageRecognitionModel
    let codesOnly: Bool
    let canUse: @MainActor () -> Bool
    let retry: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(codesOnly ? String(localized: "QR lesen") : String(localized: "Text erkennen"),
                      systemImage: codesOnly ? "qrcode.viewfinder" : "text.viewfinder").font(.headline)
                Spacer()
                Button(String(localized: "Schließen"), systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            if recognition.isBusy {
                ProgressView(codesOnly ? String(localized: "Codes werden erkannt …") : String(localized: "Text wird erkannt …"))
                Button(String(localized: "Abbrechen")) { recognition.cancel(); close() }.controlSize(.small)
            } else if codesOnly {
                RecognitionCodeResults(model: recognition, compact: true)
            } else {
                if !recognition.text.isEmpty {
                    ScrollView { Text(recognition.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 80)
                    Button(recognition.didCopyText ? String(localized: "Erneut kopieren") : String(localized: "Text kopieren"), systemImage: "doc.on.doc") {
                        recognition.copyText(canUse: canUse)
                    }.accessibilityIdentifier("quickCapture.recognition.copyAgain")
                }
                if let message = recognition.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if let error = recognition.error { Text(error).font(.callout).foregroundStyle(.red) }
            }
            if !recognition.isBusy { Button(String(localized: "Erkennung wiederholen"), systemImage: "arrow.clockwise", action: retry).buttonStyle(.link) }
        }.padding(16).frame(width: 300)
            .accessibilityIdentifier("quickCapture.recognition.result")
    }
}

private struct DirectCaptureResultCard: View {
    let workspace: WorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(workspace.directCaptureReadsCodes ? String(localized: "QR-Code scannen") : String(localized: "Textaufnahme"),
                      systemImage: workspace.directCaptureReadsCodes ? "qrcode.viewfinder" : "text.viewfinder").font(.headline)
                Spacer()
                Button(String(localized: "Schließen"), systemImage: "xmark") { workspace.dismissDirectCaptureResult() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            if workspace.isDirectOCRBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(workspace.directCaptureReadsCodes ? String(localized: "Code wird gelesen …") : String(localized: "Text wird erkannt …")).font(.callout)
                    Spacer()
                    Button(String(localized: "Abbrechen")) { workspace.cancelDirectTextCapture() }.controlSize(.small)
                }
                Text(String(localized: "Du kannst weiterarbeiten. Das Ergebnis erscheint hier.")).font(.caption).foregroundStyle(.secondary)
            } else {
                if !workspace.directCaptureText.isEmpty {
                    ScrollView { Text(workspace.directCaptureText).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 72)
                    Button(String(localized: "Erneut kopieren"), systemImage: "doc.on.doc") { workspace.copyDirectCaptureText() }
                        .buttonStyle(.borderedProminent).controlSize(.small).accessibilityIdentifier("capture.text.copyAgain")
                }
                if !workspace.directCaptureCodes.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(workspace.directCaptureCodes, id: \.self) { code in
                                Text(code).textSelection(.enabled).font(.caption).lineLimit(2)
                                HStack {
                                    Button(String(localized: "Kopieren"), systemImage: "doc.on.doc") {
                                        NSPasteboard.general.clearContents()
                                        workspace.directCaptureNotice = NSPasteboard.general.setString(code, forType: .string) ? String(localized: "Kopiert") : String(localized: "Kopieren fehlgeschlagen")
                                    }
                                    if let url = URL(string: code), ["http", "https"].contains(url.scheme?.lowercased()) {
                                        Button(String(localized: "URL öffnen"), systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                                    }
                                }.controlSize(.small)
                            }
                        }
                    }.frame(height: 80)
                }
                if let notice = workspace.directCaptureNotice { Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("capture.recognition.status") }
                if let error = workspace.directCaptureError { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
                if workspace.directCaptureImage != nil {
                    Button(String(localized: "Erkennung wiederholen"), systemImage: "arrow.clockwise") { workspace.retryDirectTextCapture() }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain).accessibilityIdentifier("capture.recognition.result")
    }
}

/// One non-activating panel keeps the stack on the active display's lower left.
@MainActor final class QuickCapturePanelController: NSObject, NSWindowDelegate {
    static let shared = QuickCapturePanelController()
    private var panel: NSPanel?
    private weak var workspace: WorkspaceModel?
    private var anchor: CGRect?
    var isVisible: Bool { panel?.isVisible == true }
    var frame: CGRect? { panel?.frame }

    func present(workspace: WorkspaceModel, model: EditorModel? = nil) {
        let changedWorkspace = self.workspace !== workspace
        self.workspace = workspace
        workspace.onQuickCaptureDismissed = { [weak self] in self?.closeIfCaptureGone() }
        guard !workspace.quickCaptures.isEmpty || workspace.showsDirectCaptureResult else { hide(); return }
        if panel == nil {
            let panel = QuickCapturePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "Aufnahme bereit")
            panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            self.panel = panel
        }
        if changedWorkspace || panel?.contentView == nil { panel?.contentView = NSHostingView(rootView: QuickCaptureStack(workspace: workspace)) }
        if !isVisible || changedWorkspace {
            anchor = (NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main)?.visibleFrame
        }
        refreshLayout(); panel?.orderFrontRegardless()
    }
    func refreshLayout(animated: Bool = false) {
        guard let workspace, let panel else { return }
        guard !workspace.quickCaptures.isEmpty || workspace.showsDirectCaptureResult else { hide(); return }
        let screen = NSScreen.screens.first(where: { $0.visibleFrame == anchor })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        let width: CGFloat = workspace.showsDirectCaptureResult ? 320 : 248
        let feedbackHeight: CGFloat
        if workspace.showsDirectCaptureResult {
            let measurement = NSHostingView(rootView: DirectCaptureResultCard(workspace: workspace).frame(width: width - 16))
            feedbackHeight = ceil(measurement.fittingSize.height) + (workspace.quickCaptures.isEmpty ? 0 : 10)
        } else { feedbackHeight = 0 }
        let thumbnailsHeight: CGFloat = workspace.quickCaptures.isEmpty ? 0 : CGFloat(workspace.quickCaptures.count) * 156 + 29
        let height = min(screen.height - 40, feedbackHeight + thumbnailsHeight + 16)
        let target = CGRect(x: screen.minX + 16, y: screen.minY + 16, width: width, height: height)
        guard panel.frame != target else { return }
        if animated, isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(target, display: true)
            }
        } else { panel.setFrame(target, display: true) }
    }
    func hide() { panel?.orderOut(nil) }
    func restore() {
        guard let workspace, !workspace.quickCaptures.isEmpty || workspace.showsDirectCaptureResult else { return }
        refreshLayout()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        workspace.quickCaptureFocusRequest += 1
    }
    func hideForCapture() { panel?.orderOut(nil) }
    func closeIfCaptureGone() { refreshLayout() }
    func windowWillClose(_ notification: Notification) { hide() }
}

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Recognition always receives the flattened, visible document, including masks.
extension EditorPNGShare {
    func recognitionImage() async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try EditorRenderer.render(image: image, objects: objects, crop: crop, resizedSize: resizedSize,
                maxDimension: 4096, canvasRect: canvasRect, transform: transform, presentation: presentation)
        }.value
    }
}

@MainActor @Observable
final class QuickImageRecognitionModel {
    private(set) var isBusy = false
    private(set) var codes: [String] = []
    private(set) var text = ""
    private(set) var didCopyText = false
    private(set) var message: String?
    private(set) var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    private var requestID = UUID()
    @ObservationIgnored private let service: TextRecognitionService
    init(service: TextRecognitionService = .shared) { self.service = service }
    func cancel() { task?.cancel(); task = nil; requestID = UUID(); isBusy = false; codes = []; text = ""; didCopyText = false; message = nil; error = nil }
    func recognize(_ snapshot: EditorPNGShare, codesOnly: Bool, canUse: @escaping @MainActor () -> Bool,
                   copy: @escaping @MainActor (String) -> Bool = { value in
                       NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(value, forType: .string)
                   }, clipboardRevision: @escaping @MainActor () -> Int = { NSPasteboard.general.changeCount }) {
        cancel(); guard canUse() else { return }
        let clipboardAtStart = clipboardRevision()
        isBusy = true
        let id = requestID, selfService = service
        task = Task { [weak self] in
            defer { if let self, self.requestID == id { self.isBusy = false; self.task = nil } }
            do {
                let image = try await snapshot.recognitionImage()
                let result: TextRecognitionService.DirectResult
                if codesOnly { result = .init(text: "", codes: try await selfService.recognizeCodes(image)) }
                else { result = try await selfService.recognizeDirect(image, includeCodes: false) }
                guard !Task.isCancelled, let self, self.requestID == id, canUse() else { return }
                self.codes = Array(Set(result.codes)).sorted()
                self.text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !codesOnly, !self.text.isEmpty {
                    if clipboardRevision() == clipboardAtStart { self.copyText(canUse: canUse, copy: copy) }
                    else { self.message = String(localized: "Text erkannt. Zwischenablage inzwischen geändert – zum Kopieren klicken.") }
                } else if codesOnly { self.message = self.codes.isEmpty ? String(localized: "Kein QR- oder Barcode erkannt") : nil }
                else { self.message = String(localized: "Kein Text erkannt") }
            } catch {
                if !Task.isCancelled, let self, self.requestID == id { self.error = error.localizedDescription }
            }
        }
    }
    @discardableResult func copyText(canUse: @MainActor () -> Bool,
        copy: @MainActor (String) -> Bool = { value in
            NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(value, forType: .string)
        }) -> Bool {
        guard canUse(), !text.isEmpty else { return false }
        didCopyText = copy(text)
        message = didCopyText ? String(localized: "Text kopiert") : nil
        error = didCopyText ? nil : String(localized: "Der erkannte Text konnte nicht in die Zwischenablage kopiert werden.")
        return didCopyText
    }

}

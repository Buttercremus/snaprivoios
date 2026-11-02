import SwiftUI
import SnagForgeDomain

struct EditorView: View {
    let workspace: WorkspaceModel
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Group {
                    if workspace.isChangingTrash {
                        ProgressView(String(localized: "Projekt wird verschoben …"))
                    } else if let editor = workspace.editor {
                        ImageEditorView(model: editor, preferences: workspace.preferences)
                    } else {
                        ContentUnavailableView(String(localized: "Noch kein Bild geöffnet"), systemImage: "photo", description: Text(String(localized: "Öffne ein Bild über die Symbolleiste oder mit ⌘O.")))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !workspace.items.isEmpty, workspace.storage.libraryError == nil {
                    Divider()
                    EditorFilmstripView(workspace: workspace)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct ImageEditorView: View {
    @Bindable var model: EditorModel
    let preferences: AppPreferences
    @State private var inlineRecognition = InlineTextRecognitionModel()
    @State private var codeRecognition = QuickImageRecognitionModel()
    @State private var showsCodes = false
    @State private var showsOutput = false
    @State private var colorPicker = ImageColorPickerState()
    @State private var isRenaming = false
    @State private var isCustomizingToolbar = false
    @State private var showsSwitchProgress = false
    @State private var showsInteractionHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            commandBar.padding(.top, 8)
            EditorLearningHint(model: model, preferences: preferences)
            if let error = model.saveError {
                HStack {
                    Label(String(localized: "Speichern fehlgeschlagen"), systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Text(error).lineLimit(2).textSelection(.enabled)
                    Button(String(localized: "Erneut sichern")) { Task { await model.flush() } }.disabled(model.isSaving)
                    Button(String(localized: "Als Kopie sichern")) { Task { await model.saveCopy() } }.disabled(model.isSaving)
                    Spacer()
                }.font(.caption).padding(.horizontal).padding(.bottom, 8)
            }
            HStack(spacing: 0) {
                if model.isRecognizingTextInPlace {
                    ZStack {
                        if inlineRecognition.image == nil { EditorCanvas(model: model).allowsHitTesting(false) }
                        InlineTextRecognitionCanvas(editor: model, recognition: inlineRecognition).opacity(inlineRecognition.image == nil ? 0 : 1)
                    }
                } else if model.isEditingPresentation {
                    EditorPresentationPreview(model: model, interactive: true)
                } else {
                    EditorCanvas(model: model, colorPicking: colorPicker.isActive ? EditorCanvasColorPicking(
                        sample: { colorPicker.sample($0, fixed: $1) }, move: { colorPicker.move($0) },
                        cancel: { colorPicker.end(); model.focusRequest += 1 }) : nil)
                        .onAppear { model.focusRequest += 1 }
                        .transaction { $0.animation = nil }
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) {
                            if showsSwitchProgress && model.isSwitchingImage { ProgressView().controlSize(.small).padding(12) }
                        }
                }
                Divider()
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                    if colorPicker.isActive {
                        ImageColorPicker(model: model, picker: colorPicker)
                    } else if model.isRecognizingTextInPlace {
                        InlineTextRecognitionInspector(editor: model, recognition: inlineRecognition).transition(.opacity)
                    } else if model.isEditingPresentation {
                        EditorPresentationInspector(model: model)
                            .transition(.opacity)
                    } else {
                        EditorProperties(model: model, preferences: preferences)
                            .transition(.opacity)
                    }
                    }
                    .animation(EditorMotion.panel(reduceMotion: reduceMotion), value: model.isEditingPresentation)
                    .animation(EditorMotion.panel(reduceMotion: reduceMotion), value: model.isRecognizingTextInPlace)
                    Divider()
                    EditorObjectList(model: model)
                }.frame(width: 260)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ViewThatFits(in: .horizontal) {
                navigationBar(compactHint: false, compactHistory: false)
                navigationBar(compactHint: true, compactHistory: false)
                navigationBar(compactHint: true, compactHistory: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.top, 4)
            .padding(.horizontal, 12)
            if let status = activityStatus {
                Text(status)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16).padding(.top, 4)
                    .accessibilityIdentifier("editor.activityStatus")
            }
            imageInfo
                .padding(.horizontal, 16).padding(.vertical, 4)
        }
        .allowsHitTesting(!model.isSwitchingImage)
        .onChange(of: model.copyState) { _, state in
            if state == .copied {
                preferences.dismissedEditorHints.formUnion(["firstAnnotation", "output"])
            }
        }
        .task(id: model.isSwitchingImage) {
            showsSwitchProgress = false
            guard model.isSwitchingImage else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            showsSwitchProgress = true
        }
        .task(id: "\(model.document.id)-\(model.isRecognizingTextInPlace)-\(model.document.revision)-\(model.isSwitchingImage)") {
            codeRecognition.cancel()
            guard model.isRecognizingTextInPlace, let snapshot = model.pngShareItemForToolbar else { inlineRecognition.clear(); return }
            let revision = model.document.revision
            await inlineRecognition.prepare(snapshot, canUse: { model.hasProAccess() && model.document.revision == revision })
        }
        .sheet(isPresented: $showsCodes) { RecognitionCodeResults(model: codeRecognition).padding(24).frame(width: 420, height: 360)
            Button(String(localized: "Schließen")) { showsCodes = false }.padding(.bottom).keyboardShortcut(.cancelAction)
        }
        .sheet(isPresented: $showsOutput) { ImageOutputView(model: model) }
        .task(id: "\(model.document.id)-\(model.document.revision)-\(colorPicker.isActive)") {
            if colorPicker.isActive { await colorPicker.prepare(model) }
        }
        .sheet(isPresented: $isRenaming) {
            ProjectRenameSheet(title: model.name) { title in
                guard model.updateMetadata(title: title) else { return false }
                return await model.flush()
            }
        }
        .sheet(isPresented: $isCustomizingToolbar) {
            EditorToolbarCustomization(preferences: preferences)
        }
        .sheet(isPresented: $model.isShowingImageSize, onDismiss: { model.focusRequest += 1 }) { EditorResizeView(model: model) }
        .sheet(isPresented: $model.isShowingTextRecognition, onDismiss: { model.focusRequest += 1 }) {
            TextRecognitionView(snapshot: TextRecognitionSnapshot(image: model.image, objects: model.history.objects,
                                                                 crop: model.history.crop, resizedSize: model.history.resizedSize, canvasRect: model.history.canvasRect, transform: model.history.transform))
        }
        .sheet(isPresented: $model.isShowingRedactionSuggestions, onDismiss: { model.focusRequest += 1 }) { RedactionSuggestionView(editor: model) }
        .onDisappear { colorPicker.end(); codeRecognition.cancel(); inlineRecognition.clear(); model.endPresentationEditing(); model.endStyleEditing(); if model.cropDraft != nil { model.cancelCrop() } }
        .onChange(of: model.document.id) { colorPicker.end() }
        .onChange(of: model.selectedIDs) { colorPicker.end() }
        .onChange(of: model.isEditingPresentation) { _, active in if active { colorPicker.end() } }
        .onChange(of: model.isRecognizingTextInPlace) { _, active in if active { colorPicker.end() } }
        .onChange(of: model.tool) { old, new in
            // Crop cancellation can activate an accessory in the same action.
            // Model tool changes already end presentation editing synchronously.
            if old != .crop || new != .selection { colorPicker.end() }
            model.endStyleEditing()
            if new != .selection && old.toolbarTool != new.toolbarTool { model.selection = nil }
        }
        .onChange(of: preferences.automaticallyFitsImage) { _, enabled in
            model.setAutomaticallyFitsImage(enabled)
        }
        .onChange(of: preferences.hiddenToolbarTools) { previous, hidden in
            if hidden.subtracting(previous).contains(model.tool.toolbarTool) {
                model.endPresentationEditing(); model.isEditingPresentation = false
                model.endStyleEditing()
                model.finishTextEditing()
                model.tool = .selection
                model.focusRequest += 1
            }
        }
        .alert(String(localized: "Aktion fehlgeschlagen"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var activityStatus: String? {
        if model.isExportingPNG { return String(localized: "Bild wird exportiert …") }
        if model.isOpeningExternally { return String(localized: "Bild wird in anderer App geöffnet …") }
        return model.notice
    }

    private func navigationBar(compactHint: Bool, compactHistory: Bool) -> some View {
        HStack(spacing: 8) {
            EditorZoomControls(model: model, preferences: preferences).fixedSize()
            EditorSavedStyles(model: model, preferences: preferences, compact: true).fixedSize()
            Spacer(minLength: 0)
            if compactHint {
                Button { showsInteractionHint.toggle() } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help(instruction)
                .accessibilityLabel(instruction)
                .accessibilityIdentifier("editor.interactionHint")
                .popover(isPresented: $showsInteractionHint) {
                    Text(instruction).font(.callout).padding(12).frame(width: 320)
                }
            } else {
                Text(instruction)
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
                    .accessibilityIdentifier("editor.interactionHint")
            }
            Spacer(minLength: 0)
            EditorObjectActions(model: model).fixedSize()
            if compactHistory {
                historyButtons.labelStyle(.iconOnly).fixedSize()
            } else {
                historyButtons.fixedSize()
            }
        }
    }

    private var imageInfo: some View {
        HStack(spacing: 12) {
            Button { isRenaming = true } label: {
                HStack(spacing: 6) {
                    Text(model.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "pencil")
                }
            }
            .buttonStyle(.plain)
            .help(String(localized: "Projekt umbenennen: \(model.name)"))
            .accessibilityLabel(String(localized: "Projekt umbenennen: \(model.name)"))
            .accessibilityIdentifier("editor.rename")
            Spacer(minLength: 8)
            Text(String(localized: "\(model.document.outputPixelSize.width) × \(model.document.outputPixelSize.height) Pixel"))
                .monospacedDigit().fixedSize()
                .accessibilityIdentifier("editor.imageDimensions")
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Bildinformationen"))
        .accessibilityIdentifier("editor.imageInfo")
    }
    private var commandBar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(actionLimit: 4, minimumToolWidth: 500)
            toolbarRow(actionLimit: 2, minimumToolWidth: 400)
            toolbarRow(actionLimit: 1, minimumToolWidth: 100)
        }
        .frame(maxWidth: .infinity, minHeight: preferences.toolbarSize.buttonHeight)
        .padding(3)
        .contentShape(.rect)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Editor-Symbolleiste"))
        .accessibilityIdentifier("editor.toolbar")
        .contextMenu {
            Button(String(localized: "Symbole anordnen …"), systemImage: "slider.horizontal.3") { isCustomizingToolbar = true }
            Toggle(String(localized: "Screenshot automatisch kopieren"), isOn: Binding(
                get: { preferences.copyAfterCapture }, set: { preferences.copyAfterCapture = $0 }))
        }
    }

    private func toolbarRow(actionLimit: Int, minimumToolWidth: CGFloat) -> some View {
        let tools = preferences.visibleToolbarTools
        let editingActions = preferences.visibleToolbarActions.filter(\.isEditingTool)
        return Group {
            if (!tools.isEmpty || !editingActions.isEmpty) && !imageActions.isEmpty {
                EditorToolbarGroupsLayout(itemWidths: EditorToolOverflowLayout.itemWidths(tools: tools, actions: editingActions, size: preferences.toolbarSize),
                    toolCount: tools.count, moreWidth: EditorToolOverflowLayout.moreWidth(size: preferences.toolbarSize),
                    minimumToolWidth: minimumToolWidth, height: preferences.toolbarSize.buttonHeight) {
                    toolbarTools
                    toolbarSeparator
                    toolbarActions(limit: actionLimit)
                }
            } else if !tools.isEmpty || !editingActions.isEmpty {
                toolbarTools
            } else if !imageActions.isEmpty {
                HStack { toolbarActions(limit: actionLimit); Spacer(minLength: 0) }
            } else {
                HStack {
                    Button(String(localized: "Symbole einblenden …")) { isCustomizingToolbar = true }
                        .accessibilityIdentifier("editor.toolbar.customize")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var transformMenu: some View {
        EditorTransformButton(model: model, size: preferences.toolbarSize)
    }

    private var toolbarSeparator: some View {
        Capsule().fill(.secondary.opacity(0.5))
            .frame(width: 3, height: preferences.toolbarSize.buttonHeight - 8)
            .accessibilityHidden(true)
    }

    private var toolbarTools: some View {
        EditorAdaptiveToolPalette(selection: $model.tool, size: preferences.toolbarSize,
            order: preferences.visibleToolbarTools,
            actions: preferences.visibleToolbarActions.filter(\.isEditingTool), hasPro: model.hasProAccess(), toolsAreActive: !colorPicker.isActive && !model.isEditingPresentation && !model.isRecognizingTextInPlace,
            activeAction: colorPicker.isActive ? .colorPicker : nil) {
                colorPicker.end()
                model.endPresentationEditing(); model.isEditingPresentation = false; model.isRecognizingTextInPlace = false
                model.endStyleEditing()
                model.finishTextEditing()
                model.focusRequest += 1
            } action: { action in
                toolbarAction(action)
            } overflowAction: { action in
                overflowAction(action)
            }
            .buttonStyle(EditorToolbarButtonStyle())
    }

    private var imageActions: [EditorToolbarAction] {
        preferences.visibleToolbarActions.filter { !$0.isEditingTool }
    }
    private func toolbarActions(limit: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(imageActions.prefix(limit))) { action in toolbarAction(action) }
            if imageActions.count > limit {
                Menu {
                    ForEach(Array(imageActions.dropFirst(limit))) { action in
                        overflowAction(action)
                    }
                } label: {
                    Label(String(localized: "Mehr"), systemImage: "chevron.down")
                        .font(.system(size: preferences.toolbarSize.labelSize))
                        .frame(height: preferences.toolbarSize.buttonHeight)
                }
                .menuIndicator(.hidden).menuStyle(.borderlessButton).fixedSize()
                .accessibilityIdentifier("editor.actions.more")
                .help(String(localized: "Weitere Bildaktionen"))
            }
        }.buttonStyle(EditorToolbarButtonStyle()).fixedSize()
    }
    @ViewBuilder private func overflowAction(_ action: EditorToolbarAction) -> some View {
        switch action {
        case .transform:
            Menu(action.title, systemImage: action.symbol) { EditorTransformCommands(model: model) }.disabled(!model.canSwitchEditingTool)
        case .openWith:
            Menu(action.title) {
                ForEach(EditorPNGApplication.available(), id: \.url) { app in
                    Button(app.name) { model.openPNG(with: app.url) }
                }
                Button(String(localized: "Andere App …")) { model.choosePNGApplication() }
            }.disabled(!model.hasConfirmedImageForToolbar || model.isExporting)
        case .share:
            if let item = model.pngShareItemForToolbar {
                ShareLink(item: item, preview: SharePreview(model.name, image: Image(systemName: "photo"))) {
                    Label(action.title, systemImage: action.symbol)
                }
            } else { Button(action.title, systemImage: action.symbol) {}.disabled(true) }
        case .copy:
            Button(action.title, systemImage: action.symbol) { model.copyPNG(animateFeedback: true) }
                .disabled(!model.hasConfirmedImageForToolbar || model.isExporting)
        default: toolbarAction(action)
        }
    }
    @ViewBuilder private func toolbarAction(_ action: EditorToolbarAction) -> some View {
        switch action {
        case .presentation:
            Button {
                model.togglePresentationTool()
            } label: { EditorToolbarLabel(title: action.title, symbol: action.symbol, size: preferences.toolbarSize) }
                .buttonStyle(EditorToolbarButtonStyle(isSelected: model.isEditingPresentation))
                .disabled(!model.canSwitchEditingTool).accessibilityIdentifier("editor.background.open")
        case .transform: transformMenu
        case .scanCode:
            Button {
                guard model.canSwitchEditingTool, model.requestFeature(.textRecognition), model.prepareForEditingTool(),
                      let snapshot = model.pngShareItemForToolbar else { return }
                showsCodes = true
                let revision = model.document.revision
                codeRecognition.recognize(snapshot, codesOnly: true, canUse: { model.hasProAccess() && model.document.revision == revision })
            } label: { EditorToolbarLabel(title: action.title, symbol: action.symbol, size: preferences.toolbarSize) }
                .disabled(!model.canSwitchEditingTool).accessibilityIdentifier("editor.qr.open")
        case .resize:
            Button { model.beginImageResize() } label: {
                EditorToolbarLabel(title: action.title, symbol: action.symbol, size: preferences.toolbarSize)
            }
            .disabled(!model.canSwitchEditingTool)
            .help(String(localized: "Bildauflösung ändern"))
            .accessibilityIdentifier("editor.resize.open")
        case .output:
            Button { model.endStyleEditing(); model.finishTextEditing(); showsOutput = true } label: {
                EditorToolbarLabel(title: action.title, symbol: action.symbol, size: preferences.toolbarSize)
            }.disabled(!model.hasConfirmedImageForToolbar)
        case .colorPicker:
            Button {
                guard model.prepareForEditingTool() else { return }
                if colorPicker.isActive { colorPicker.end() }
                else {
                    model.endPresentationEditing(); model.endStyleEditing(); model.finishTextEditing()
                    model.isEditingPresentation = false; model.isRecognizingTextInPlace = false
                    colorPicker.activate()
                }
                model.focusRequest += 1
            } label: {
                EditorToolbarLabel(title: action.title, symbol: action.symbol, size: preferences.toolbarSize)
            }.disabled(!model.canSwitchEditingTool)
                .buttonStyle(EditorToolbarButtonStyle(isSelected: colorPicker.isActive))
                .accessibilityIdentifier("editor.colorPicker.open")
        case .insertImage: InsertImageButton(model: model, size: preferences.toolbarSize)
        case .pin: PinImageButton(model: model, size: preferences.toolbarSize)
        case .copy: copyButton
        case .recognizeText:
            Button { model.beginInlineTextRecognition() } label: {
                EditorToolbarLabel(title: model.hasProAccess() ? action.title : String(localized: "Text erkennen · Pro"), symbol: action.symbol, size: preferences.toolbarSize, extraWidth: 4)
            }
            .disabled(!model.canSwitchEditingTool)
            .buttonStyle(EditorToolbarButtonStyle(isSelected: model.isRecognizingTextInPlace))
            .help(String(localized: "Text direkt im Bild auswählen"))
            .accessibilityIdentifier("editor.ocr.open")
        case .savePNG:
            Button { model.exportPNG() } label: {
                EditorToolbarLabel(title: action.title, symbol: action.symbol, size: preferences.toolbarSize, extraWidth: 4)
            }
            .disabled(model.isExportingPNG || !model.hasConfirmedImageForToolbar)
            .help(String(localized: "Bearbeitetes Bild als PNG exportieren (⇧⌘E)"))
            .accessibilityIdentifier("editor.export.png")
        case .share: shareButton
        case .openWith: EditorOpenWithButton(model: model, size: preferences.toolbarSize)
        }
    }
    private var shareButton: some View {
        Group {
            if let item = model.pngShareItemForToolbar {
                ShareLink(item: item, preview: SharePreview(model.name, image: Image(systemName: "photo"))) {
                    EditorToolbarLabel(title: String(localized: "Teilen"), symbol: "square.and.arrow.up", size: preferences.toolbarSize)
                }
            } else {
                Button {} label: {
                    EditorToolbarLabel(title: String(localized: "Teilen"), symbol: "square.and.arrow.up", size: preferences.toolbarSize)
                }.disabled(true)
            }
        }
        .help(String(localized: "Bearbeitetes PNG über AirDrop, Mail und weitere Apps teilen"))
        .accessibilityLabel(String(localized: "Bild teilen"))
        .accessibilityIdentifier("editor.share")
    }
    private var copyButton: some View {
        Button { model.copyPNG(animateFeedback: true) } label: {
            // Keep the normal label during rendering; a fleeting loading label looks like a flicker.
            // Both states reserve their width so confirmation never shifts nearby controls.
            ZStack {
                EditorToolbarLabel(title: String(localized: "Kopieren"), symbol: "doc.on.doc", size: preferences.toolbarSize).hidden()
                EditorToolbarLabel(title: String(localized: "Kopiert"), symbol: "checkmark", size: preferences.toolbarSize).hidden()
                let copied = model.copyState == .copied
                EditorToolbarLabel(title: copied ? String(localized: "Kopiert") : String(localized: "Kopieren"),
                                   symbol: copied ? "checkmark" : "doc.on.doc", size: preferences.toolbarSize)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityHidden(true)
            .animation(reduceMotion || !model.animateCopyFeedback ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.16), value: model.copyState == .copied)
        }
        .accessibilityLabel(model.copyState == .copied ? String(localized: "Bild kopiert") : model.copyState == .copying ? String(localized: "Bild wird kopiert") : String(localized: "Bild kopieren"))
        .accessibilityIdentifier("editor.copy")
        .help(String(localized: "Bearbeitetes Bild in die Zwischenablage kopieren"))
        .disabled(model.isExportingPNG || !model.hasConfirmedImageForToolbar)
    }
    private var historyButtons: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Rückgängig"), systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.history.canUndo || model.cropDraft != nil).help(String(localized: "Rückgängig (⌘Z)"))
            Button(String(localized: "Wiederholen"), systemImage: "arrow.uturn.forward") { model.redo() }
                .disabled(!model.history.canRedo || model.cropDraft != nil).help(String(localized: "Wiederholen (⇧⌘Z)"))
            Button(String(localized: "Löschen"), systemImage: "trash") { model.removeSelection() }
                .disabled(model.selection == nil).help(String(localized: "Ausgewähltes Objekt löschen"))
        }
    }
    private var instruction: String {
        if colorPicker.isActive { return String(localized: "Maus bewegen: Farbe ansehen · Klicken: Farbe festhalten · Pfeiltasten: Pixel wählen · Esc: beenden") }
        return switch model.tool {
        case .crop: String(localized: "Rahmen aufziehen oder an Griffen ändern · Innen ziehen: verschieben · ⌥ ziehen: neuer Rahmen · Eingabe: übernehmen · Esc: abbrechen")
        case .arrow: String(localized: "Pfeil aufziehen · Mittleren Griff ziehen: biegen · Umschalt: 45°-Schritte")
        case .callout: String(localized: "Sprechblase aufziehen, dann Text eingeben · Spitze ziehen: Ziel ändern")
        case .pen: String(localized: "Ziehen: frei zeichnen · Farbe, Breite und Glättung rechts ändern")
        case .spotlight: String(localized: "Fokusbereich aufziehen · Weitere Bereiche ergänzen · Intensität rechts ändern")
        case .magnifier: String(localized: "Kreis aufziehen: vergrößern · Vergrößerung rechts ändern")
        case .text: String(localized: "Klicken oder Textfeld aufziehen · Doppelklick: Wort markieren · ⌘A: alles · Esc: fertig")
        case .rectangle, .ellipse: String(localized: "Form aufziehen · Umschalt: Quadrat oder Kreis")
        case .redact: String(localized: "Bereich deckend abdecken · Bearbeitbare Projekte behalten das Original.")
        case .highlight: model.activeHighlightStyle.mode == .freehand ? String(localized: "Ziehen: freihändig markieren · Farbe, Breite und Deckkraft rechts ändern") : String(localized: "Rechteck aufziehen: markieren · Modus, Farbe und Deckkraft rechts ändern")
        case .steps: String(localized: "Klicken: nächste Marke \(model.nextStepLabel) setzen · Form, Farben und Typ rechts ändern")
        case .blur: String(localized: "Bereich aufziehen · Unschärfe ist keine sichere Schwärzung.")
        default:
            if model.selectedObject?.kind == .arrow { String(localized: "Mittleren Griff ziehen: biegen · Endpunkte ziehen · Schaft: verschieben · ⌘Z / ⇧⌘Z") }
            else if let kind = model.selectedObject?.kind, kind.isShape || kind == .callout {
                String(localized: "Griffe ziehen: Größe ändern · Umschalt: Quadrat/Kreis bzw. Proportionen · Doppelklick: Text bearbeiten")
            }
            else { String(localized: "Doppelklick: Text bearbeiten · Scrollen oder Leertaste + Ziehen: Bild verschieben · ⌘Z / ⇧⌘Z") }
        }
    }
}

private struct EditorToolbarCustomization: View {
    let preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Symbole anordnen")).font(.headline).padding(.top, 20)
            EditorToolbarSettings(preferences: preferences)
            HStack {
                Spacer()
                Button(String(localized: "Fertig")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding([.horizontal, .bottom], 20)
        }
        .frame(width: 540, height: 620)
    }
}

private struct EditorZoomControls: View {
    let model: EditorModel
    let preferences: AppPreferences
    var body: some View {
        HStack(spacing: 4) {
            Button(String(localized: "Verkleinern"), systemImage: "minus.magnifyingglass") { model.zoomBy(1 / 1.25) }
                .labelStyle(.iconOnly).help(String(localized: "Verkleinern (⌘−)")).accessibilityIdentifier("editor.zoom.out")
            Menu {
                Button(String(localized: "An Fenster anpassen")) { model.fitImage() }
                Divider()
                ForEach([25, 50, 75, 100, 150, 200, 400, 800, 1600], id: \.self) { percent in
                    Button("\(percent) %") { model.setZoom(CGFloat(percent) / 100) }
                }
                Divider()
                Toggle(String(localized: "Immer passend verkleinern"), isOn: Binding(
                    get: { preferences.automaticallyFitsImage },
                    set: { preferences.automaticallyFitsImage = $0 }))
                    .help(String(localized: "Neue Bilder passend anzeigen, höchstens mit 100 %. Ändert nur die Ansicht."))
                    .accessibilityIdentifier("editor.zoom.automaticallyFit")
            } label: {
                Text(model.zoomLabel).monospacedDigit().frame(minWidth: 64)
            }
            .fixedSize().help(String(localized: "Zoomstufe wählen")).accessibilityLabel(String(localized: "Zoom: \(model.zoomLabel)"))
            .accessibilityIdentifier("editor.zoom.level")
            Button(String(localized: "Vergrößern"), systemImage: "plus.magnifyingglass") { model.zoomBy(1.25) }
                .labelStyle(.iconOnly).help(String(localized: "Vergrößern (⌘+)")).accessibilityIdentifier("editor.zoom.in")
            Button("100 %") { model.setZoom(1) }
                .help(String(localized: "Ein Bildpixel pro Bildschirm-Pixel (⌘1)")).accessibilityIdentifier("editor.zoom.actual")
            Button(String(localized: "Anpassen"), systemImage: "arrow.up.left.and.arrow.down.right") { model.fitImage() }
                .labelStyle(.iconOnly).help(String(localized: "An Fenster anpassen (⌘0)")).accessibilityIdentifier("editor.zoom.fit")
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(model.isCanvasGestureActive)
    }
}


/// A constant-width inspector keeps the canvas still when changing tools or selection.
private struct EditorProperties: View {
    @Bindable var model: EditorModel
    let preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var context: String {
        model.cropDraft != nil ? "crop" : model.isSourceImageSelected ? "source" : model.selectedIDs.count > 1 ? "multiple" : model.activeKind?.rawValue ?? "empty"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.cropDraft != nil {
                    EditorCropProperties(model: model)
                } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(model.isSourceImageSelected ? String(localized: "Bild") : model.selectedIDs.count > 1 ? String(localized: "Mehrere Objekte ausgewählt") : model.activeKind == nil ? String(localized: "Kein Objekt ausgewählt") : model.selectedObject == nil ? String(localized: "Für neue Objekte") : String(localized: "Ausgewähltes Objekt"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                if model.isSourceImageSelected {
                    EditorSourceImageFrameControls(model: model)
                } else if let kind = model.activeKind {
                    if kind.isShape { EditorShapeOptions(model: model) }
                    if kind == .arrow || kind.isShape {
                        EditorDrawingStylePicker(model: model)
                        if kind == .arrow {
                            Text(String(localized: "Mittleren Griff ziehen, um den Pfeil zu biegen.")).font(.caption).foregroundStyle(.secondary)
                            if model.selectedObject != nil {
                                EditorArrowBendControl(model: model)
                                Button(String(localized: "Pfeil begradigen")) { model.straightenArrow() }
                                    .accessibilityIdentifier("editor.arrow.straighten")
                            }
                        }
                    }
                    if kind == .highlight || kind == .step {
                        EditorInstructionOptions(model: model)
                    } else if kind == .spotlight {
                        EditorSpotlightOptions(model: model)
                    } else if kind == .pen {
                        colorPicker(String(localized: "Farbe"), color: Binding(get: { model.activeColor }, set: { model.updateStyle(color: $0) }))
                        lineWidthControl(String(localized: "Linienbreite"))
                        Toggle(String(localized: "Strich glätten"), isOn: Binding(get: { model.activePenSmoothed }, set: { model.updatePenSmoothed($0) }))
                    } else if kind == .redact {
                        colorPicker(String(localized: "Deckfarbe"), color: Binding(get: { model.activeColor }, set: { model.updateStyle(color: $0) }))
                        Button(String(localized: "Sensible Daten finden …"), systemImage: "eye.slash") { model.beginRedactionSuggestions() }
                            .accessibilityIdentifier("editor.redaction.suggest")
                        Text(String(localized: "Immer vollständig deckend und über allen Markierungen. PNG und Zwischenablage enthalten hier nur die Deckfarbe. Bearbeitbare Projekte und Sicherungen behalten das Original.")).font(.caption).foregroundStyle(.secondary)
                    } else if kind == .magnifier {
                        Picker(String(localized: "Lupenart"), selection: Binding(
                            get: { model.activeMagnifierOffset }, set: { model.updateMagnifierOffset($0) })) {
                            Text(String(localized: "Normal")).tag(false)
                            Text(String(localized: "Versetzt")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("editor.magnifier.mode")
                        EditorPropertySlider(title: String(localized: "Vergrößerung"), identifier: "magnification", value: Binding(
                            get: { Double(model.activeMagnification * 100) }, set: { model.updateMagnification(CGFloat($0) / 100) }),
                            range: 150...500, unit: "%", onEditingChanged: { active in
                                if active { model.beginStyleEditing() } else { model.endStyleEditing() }
                            })
                        colorPicker(String(localized: "Randfarbe"), color: Binding(get: { model.activeColor }, set: { model.updateStyle(color: $0) }))
                        lineWidthControl(String(localized: "Linienbreite"))
                        Text(model.activeMagnifierOffset
                             ? String(localized: "Auf ein Detail drücken und die Lupe daneben ziehen. Quelle und Lupe getrennt verschieben.")
                             : String(localized: "Kreis direkt über dem Detail aufziehen. Griffe ändern die Größe."))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if kind == .image {
                        EditorSelectedImageFrameControls(model: model)
                        Text(String(localized: "Bild verschieben oder an den Griffen skalieren. Umschalt erhält die Proportionen.")).font(.caption)
                    } else if kind != .blur {
                        if kind.isShape {
                            borderControls
                        } else {
                            colorPicker(kind == .text ? String(localized: "Textfarbe") : kind == .callout ? String(localized: "Text & Kontur") : String(localized: "Farbe"), color: Binding(
                                get: { model.selectedObject?.color ?? model.defaultColor },
                                set: { model.updateStyle(color: $0) }))
                            if kind != .text { lineWidthControl(kind == .arrow ? String(localized: "Pfeilstärke") : String(localized: "Linienbreite")) }
                        }
                        if kind == .text || kind == .callout {
                            EditorTypographyControls(model: model)
                            propertySlider(String(localized: "Schriftgröße"), id: "font", value: Binding(
                                get: { model.selectedObject?.fontSize ?? model.defaultFontSize },
                                set: { model.updateStyle(font: $0) }), range: 8...200)
                        }
                        if kind.isShape || kind == .callout {
                            fillControls
                        }
                        if kind == .rectangle {
                            Divider()
                            propertySlider(String(localized: "Eckenradius"), id: "corner", value: Binding(
                                get: { model.selectedObject.map { $0.cornerRadius ?? 0 } ?? model.defaultCornerRadius },
                                set: { model.updateStyle(corner: $0) }), range: 0...100)
                        }
                    } else {
                        EditorBlurControls(model: model)
                        Text(String(localized: "Weichzeichnen und Verpixeln sind keine sichere Schwärzung. Nutze dafür Abdecken.")).font(.caption).foregroundStyle(.secondary)
                    }
                } else if model.selectedIDs.count > 1 {
                    Text(String(localized: "Umschalt-Klick ergänzt die Auswahl. Ziehen verschiebt alle ausgewählten Objekte.")).font(.caption)
                } else {
                    Label(String(localized: "Objekt im Bild auswählen, um seine Eigenschaften zu ändern."), systemImage: "cursorarrow")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(String(localized: "Doppelklick bearbeitet Text.")).font(.caption).foregroundStyle(.secondary)
                }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(EditorMotion.panel(reduceMotion: reduceMotion), value: context)
        }
        .background(.background)
        .accessibilityIdentifier("editor.properties")
    }
    private func objectTitle(_ kind: EditorObject.Kind) -> String {
        switch kind {
        case .image: String(localized: "Bild")
        case .arrow: String(localized: "Pfeil")
        case .text: String(localized: "Text")
        case .rectangle: String(localized: "Rechteck")
        case .ellipse: String(localized: "Ellipse")
        case .triangle: String(localized: "Dreieck")
        case .diamond: String(localized: "Raute")
        case .star: String(localized: "Stern")
        case .callout: String(localized: "Callout")
        case .pen: String(localized: "Stift")
        case .spotlight: String(localized: "Spotlight")
        case .magnifier: String(localized: "Lupe")
        case .blur: String(localized: "Unschärfe")
        case .redact: String(localized: "Abdecken")
        case .highlight: String(localized: "Markieren")
        case .step: String(localized: "Liste")
        }
    }
    private var title: String {
        switch model.activeKind {
        case .image: String(localized: "Bild")
        case .arrow: String(localized: "Pfeil")
        case .text: String(localized: "Text")
        case .rectangle: String(localized: "Rechteck")
        case .ellipse: String(localized: "Ellipse")
        case .triangle: String(localized: "Dreieck")
        case .diamond: String(localized: "Raute")
        case .star: String(localized: "Stern")
        case .callout: String(localized: "Callout")
        case .pen: String(localized: "Stift")
        case .spotlight: String(localized: "Spotlight")
        case .magnifier: String(localized: "Lupe")
        case .blur: String(localized: "Unschärfe")
        case .redact: String(localized: "Abdecken")
        case .highlight: String(localized: "Markieren")
        case .step: String(localized: "Liste")
        case nil: String(localized: "Eigenschaften")
        }
    }
    private var borderControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Toggle(String(localized: "Rand"), isOn: Binding(get: { model.activeStroke.isEnabled }, set: {
                var stroke = model.activeStroke; stroke.isEnabled = $0; model.updateStyle(stroke: stroke)
            }))
            .toggleStyle(.checkbox).accessibilityIdentifier("editor.style.strokeEnabled")
            VStack(alignment: .leading, spacing: 12) {
                colorPicker(String(localized: "Randfarbe"), color: Binding(
                    get: { model.selectedObject?.color ?? model.defaultColor }, set: { model.updateStyle(color: $0) }))
                lineWidthControl(String(localized: "Linienbreite"))
                Text(String(localized: "Linienstil")).font(.caption)
                Picker(String(localized: "Linienstil"), selection: Binding(get: { model.activeStroke.style }, set: {
                    var stroke = model.activeStroke; stroke.style = $0; model.updateStyle(stroke: stroke)
                })) {
                    Text(String(localized: "Voll")).tag(EditorStroke.Style.solid)
                    Text(String(localized: "Strich")).tag(EditorStroke.Style.dashed)
                    Text(String(localized: "Punkt")).tag(EditorStroke.Style.dotted)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                .accessibilityIdentifier("editor.style.strokeStyle")
            }.disabled(!model.activeStroke.isEnabled)
        }
    }
    private func lineWidthControl(_ title: String) -> some View {
        propertySlider(title, id: "width", value: Binding(
            get: { model.activeLineWidth },
            set: { model.updateStyle(width: $0) }), range: 1...80)
    }
    private var fillControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Toggle(String(localized: "Füllung"), isOn: Binding(get: { model.activeFill.isEnabled }, set: { enabled in
                var fill = model.activeFill; fill.isEnabled = enabled; model.updateStyle(fill: fill)
            }))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("editor.style.fillEnabled")
            colorPicker(String(localized: "Füllfarbe"), color: Binding(get: { model.activeFill.color }, set: { color in
                var fill = model.activeFill; fill.color = color; model.updateStyle(fill: fill)
            }))
            .disabled(!model.activeFill.isEnabled)
            EditorPropertySlider(title: String(localized: "Deckkraft der Füllung"), identifier: "fillOpacity", value: Binding(
                get: { model.activeFill.opacity * 100 }, set: { opacity in
                    var fill = model.activeFill; fill.opacity = opacity / 100; model.updateStyle(fill: fill)
                }), range: 0...100, unit: "%", onEditingChanged: styleEditing)
                .disabled(!model.activeFill.isEnabled)
        }
    }
    private func colorPicker(_ title: String, color: Binding<EditorColor>) -> some View {
        EditorColorOptions(title: title, color: color)
    }
    private func propertySlider(_ title: String, id: String, value: Binding<CGFloat>, range: ClosedRange<Double>) -> some View {
        EditorPropertySlider(title: title, identifier: id,
            value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) }),
            range: range, unit: "px", onEditingChanged: styleEditing)
    }
    private func styleEditing(_ editing: Bool) {
        if editing { model.beginStyleEditing() } else { model.endStyleEditing() }
    }
}

extension EditorLayerMove {
    var title: String {
        switch self {
        case .forward: String(localized: "Eine Ebene nach vorne")
        case .backward: String(localized: "Eine Ebene nach hinten")
        case .front: String(localized: "Ganz nach vorne")
        case .back: String(localized: "Ganz nach hinten")
        }
    }
    var shortTitle: String {
        switch self { case .forward: String(localized: "Nach vorne"); case .backward: String(localized: "Nach hinten"); case .front: String(localized: "Ganz vorne"); case .back: String(localized: "Ganz hinten") }
    }
    var symbol: String {
        switch self { case .forward: "arrow.up"; case .backward: "arrow.down"; case .front: "arrow.up.to.line"; case .back: "arrow.down.to.line" }
    }
    var identifier: String {
        switch self { case .forward: "forward"; case .backward: "backward"; case .front: "front"; case .back: "back" }
    }
}

private struct EditorObjectActions: View {
    let model: EditorModel
    var body: some View {
        Menu {
            Button(String(localized: "Duplizieren"), systemImage: "plus.square.on.square") { model.duplicateSelection() }
                .disabled(!model.canDuplicateSelection)
                .help(String(localized: "Ausgewähltes Objekt duplizieren (⌘D)")).accessibilityIdentifier("editor.object.duplicate")
            if model.selectedIDs.count > 1 {
                Button(String(localized: "Gruppieren")) { model.groupSelection() }
                    .disabled(!model.canActOnSelection)
            }
            if model.history.objects.contains(where: { model.selectedIDs.contains($0.id) && $0.groupID != nil }) {
                Button(String(localized: "Gruppe auflösen")) { model.groupSelection(ungroup: true) }
                    .disabled(!model.canActOnSelection)
            }
            Button(String(localized: "Auswahl löschen")) { model.removeSelection() }
                .disabled(!model.canActOnSelection)
            if model.history.objects.count >= 10_000 {
                Text(String(localized: "Die Projektgrenze von 10.000 Objekten ist erreicht.")).font(.caption).foregroundStyle(.secondary)
            }
        } label: { Label(String(localized: "Objektaktionen"), systemImage: "ellipsis.circle") }
        .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
        .disabled(!model.canActOnSelection)
        .help(String(localized: "Duplizieren, gruppieren oder löschen"))
        .accessibilityIdentifier("editor.object.actions")
    }
}

private struct EditorCropProperties: View {
    let model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Zuschneiden")).font(.headline)
            Text(String(localized: "Rahmen aufziehen, an den Griffen ändern oder innen verschieben."))
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            if let rect = model.cropDraft {
                pixelField("X", id: "x", value: rect.minX)
                pixelField("Y", id: "y", value: rect.minY)
                pixelField(String(localized: "Breite"), id: "width", value: rect.width)
                pixelField(String(localized: "Höhe"), id: "height", value: rect.height)
            }
            Button(String(localized: "Übernehmen"), systemImage: "checkmark") { model.applyCrop() }
                .buttonStyle(.borderedProminent).disabled(!model.canApplyCrop)
                .help(String(localized: "Zuschnitt übernehmen (Eingabetaste)")).accessibilityIdentifier("editor.crop.apply")
            Button(String(localized: "Abbrechen")) { model.cancelCrop() }
                .disabled(model.isCanvasGestureActive).help(String(localized: "Zuschnitt verwerfen (Esc)"))
                .accessibilityIdentifier("editor.crop.cancel")
            Divider()
            Button(String(localized: "Ganzes Original")) { model.restoreOriginal() }
                .disabled(model.isCanvasGestureActive).accessibilityIdentifier("editor.crop.original")
            Text(String(localized: "Das Original und alle Markierungen bleiben erhalten. Ausgeblendete Bereiche lassen sich später wieder einbeziehen."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func pixelField(_ title: String, id: String, value: CGFloat) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            TextField(title, value: Binding(get: { Double(value) }, set: { new in
                guard new.isFinite, var rect = model.cropDraft else { return }
                let area = model.fullCanvasRect
                switch id {
                case "x": rect.origin.x = min(area.maxX - rect.width, max(area.minX, CGFloat(new).rounded()))
                case "y": rect.origin.y = min(area.maxY - rect.height, max(area.minY, CGFloat(new).rounded()))
                case "width": rect.size.width = min(area.maxX - rect.minX, max(1, CGFloat(new).rounded()))
                default: rect.size.height = min(area.maxY - rect.minY, max(1, CGFloat(new).rounded()))
                }
                model.cropDraft = rect
            }), format: .number.precision(.fractionLength(0)))
            .frame(width: 76).textFieldStyle(.roundedBorder).controlSize(.small)
            .monospacedDigit().multilineTextAlignment(.trailing)
            .disabled(model.isCanvasGestureActive)
            .accessibilityLabel(String(localized: "Zuschnitt \(title) in Pixeln")).accessibilityIdentifier("editor.crop.\(id)")
            Text("px").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct EditorPropertySlider: View {
    let title: String
    let identifier: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let onEditingChanged: (Bool) -> Void
    private var boundedValue: Binding<Double> {
        Binding(get: { min(range.upperBound, max(range.lowerBound, value)) }, set: {
            guard $0.isFinite else { return }
            value = min(range.upperBound, max(range.lowerBound, $0))
        })
    }
    private var sliderValue: Binding<Double> {
        Binding(get: { boundedValue.wrappedValue }, set: { boundedValue.wrappedValue = $0.rounded() })
    }
    private func adjustValue(by step: Double) {
        onEditingChanged(true)
        sliderValue.wrappedValue += step
        onEditingChanged(false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.9)
                Spacer(minLength: 4)
                TextField(title, value: boundedValue, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .monospacedDigit().multilineTextAlignment(.trailing).frame(width: 42)
                    .accessibilityLabel(String(localized: "\(title) in \(unit)"))
                    .accessibilityIdentifier("editor.style.\(identifier).value")
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            // macOS still draws an automatic scale with step: 1, even when all
            // tick labels are nil. Round input separately to keep the track clean.
            Slider(value: sliderValue, in: range, onEditingChanged: onEditingChanged)
                .onKeyPress(keys: [.leftArrow, .downArrow], phases: [.down, .repeat]) { _ in
                    adjustValue(by: -1); return .handled
                }
                .onKeyPress(keys: [.rightArrow, .upArrow], phases: [.down, .repeat]) { _ in
                    adjustValue(by: 1); return .handled
                }
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjustValue(by: 1)
                    case .decrement: adjustValue(by: -1)
                    @unknown default: break
                    }
                }
                .accessibilityLabel(title)
                .accessibilityIdentifier("editor.style.\(identifier)")
        }
    }
}


private struct EditorTypographyControls: View {
    @Bindable var model: EditorModel
    @State private var families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    private func change(_ update: (inout EditorTextStyle) -> Void) {
        var style = model.activeTextStyle; update(&style)
        model.updateStyle(textStyle: style)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(String(localized: "Schrift"), selection: Binding(get: { model.activeTextStyle.family ?? "" }, set: { value in
                change { $0.family = value.isEmpty ? nil : value }
            })) {
                Text(String(localized: "Systemschrift")).tag("")
                if let family = model.activeTextStyle.family, !families.contains(family) {
                    Text(String(localized: "\(family) (nicht verfügbar)")).tag(family)
                }
                ForEach(families, id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("editor.text.family")
            HStack {
                Toggle(String(localized: "Fett"), isOn: Binding(get: { model.activeTextStyle.weight != .regular }, set: { value in
                    change { $0.weight = value ? .bold : .regular }
                })).accessibilityIdentifier("editor.text.bold")
                Toggle(String(localized: "Kursiv"), isOn: Binding(get: { model.activeTextStyle.italic }, set: { value in
                    change { $0.italic = value }
                })).accessibilityIdentifier("editor.text.italic")
                Toggle(String(localized: "Unterstrichen"), isOn: Binding(get: { model.activeTextStyle.isUnderlined }, set: { value in
                    change { $0.isUnderlined = value }
                })).accessibilityIdentifier("editor.text.underline")
            }.toggleStyle(.button)
            Picker(String(localized: "Ausrichtung"), selection: Binding(get: { model.activeTextStyle.alignment }, set: { value in
                change { $0.alignment = value }
            })) {
                Image(systemName: "text.alignleft").accessibilityLabel(String(localized: "Linksbündig")).tag(EditorTextStyle.Alignment.left)
                Image(systemName: "text.aligncenter").accessibilityLabel(String(localized: "Zentriert")).tag(EditorTextStyle.Alignment.center)
                Image(systemName: "text.alignright").accessibilityLabel(String(localized: "Rechtsbündig")).tag(EditorTextStyle.Alignment.right)
            }.pickerStyle(.segmented).accessibilityIdentifier("editor.text.alignment")
            if model.activeKind == .callout {
                Text(String(localized: "Den runden Griff an der Zeigerspitze ziehen. Die eckigen Griffe ändern den Rahmen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

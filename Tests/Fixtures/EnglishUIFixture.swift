import AppKit
import SwiftUI
import SnagForgeDomain

private actor UIExportHold {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class UICompletedVideoTransport: VideoRecordingTransport {
    var onEvent: (@MainActor (VideoRecordingEvent) -> Void)?
    func start(completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        onEvent?(.started); completion(.success(()))
    }
    func stop(completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        onEvent?(.finished); completion(.success(()))
    }
    func detachOutput() throws { }
}

/// Runs production scenes with synthetic images and a disposable library.
/// Scroll controls retain production actions; video selection/countdown uses a failing synthetic engine.
@MainActor enum EnglishUIFixture {
    static private var selector: ScreenshotSelector?
    static private var scrollSession: ManualScrollSession?
    static private var videoSession: VideoRecordingSession?
    static private var hoverPanel: SelectionPanel?
    static private var imageSwitchHold: UIExportHold?

    static func makeWorkspace() -> WorkspaceModel {
        let defaults = UserDefaults(suiteName: "com.snaprivo.englishuifixture.\(UUID())")!
        defaults.set(false, forKey: "capture.globalShortcutsEnabled")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-English-UI-\(UUID())")
        let workspace = WorkspaceModel(root: root, defaults: defaults)
        Task {
            do {
                let image = bitmap(width: 1280, height: 800)
                let original = try EditorRenderer.png(image: image, objects: [])
                var arrow = EditorObject(kind: .arrow, start: CGPoint(x: 320, y: 300), end: CGPoint(x: 700, y: 390), lineWidth: 15)
                arrow.color = EditorColor(red: 0.1, green: 0.4, blue: 0.9)
                let text = EditorObject(kind: .text, start: CGPoint(x: 160, y: 110), text: "Synthetic screenshot – English UI review", fontSize: 32)
                let callout = EditorObject(kind: .callout, start: CGPoint(x: 600, y: 470), text: "A sample callout with editable text", fontSize: 26, textWidth: 420)
                for title in ["English UI layout fixture", "A long synthetic project title for checking narrow windows and search"] {
                    let document = ProjectDocument(title: title, pixelSize: PixelSize(width: 1280, height: 800)!, objects: [arrow, text, callout])
                    try await workspace.store.create(document, original: original,
                        thumbnail: EditorRenderer.thumbnail(image: image, objects: document.objects))
                }
                await workspace.refreshLibrary()
            } catch { workspace.importError = error.localizedDescription }
        }
        return workspace
    }

    static func bitmap(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor(srgbRed: 0.91, green: 0.95, blue: 1, alpha: 1).cgColor)
        context.fill(CGRect(x: width / 10, y: height / 5, width: width * 8 / 10, height: height * 3 / 5))
        context.setStrokeColor(NSColor(srgbRed: 0.5, green: 0.65, blue: 0.85, alpha: 1).cgColor)
        context.setLineWidth(2)
        for y in stride(from: height / 4, to: height * 3 / 4, by: max(1, height / 10)) {
            context.move(to: CGPoint(x: width / 7, y: y)); context.addLine(to: CGPoint(x: width * 6 / 7, y: y))
        }
        context.strokePath()
        return context.makeImage()!
    }

    static func showSelection(workspace: WorkspaceModel, video: Bool, source: CaptureSource = .region) {
        let desktop = FrozenDesktop(displays: NSScreen.screens.map { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
            return FrozenDisplay(displayID: id, screenFrame: screen.frame,
                image: bitmap(width: Int(screen.frame.width * screen.backingScaleFactor), height: Int(screen.frame.height * screen.backingScaleFactor)))
        })
        selector = ScreenshotSelector()
        let screen = NSScreen.main!
        let rect = CGRect(x: screen.frame.minX + 120, y: screen.frame.minY + 160, width: 640, height: 400)
        let primaryHeight = NSScreen.screens.first!.frame.height
        let windows = source == .window ? [CapturableWindow(id: 42, processID: nil, applicationName: "Synthetic window",
            frame: CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height))] : []
        Task {
            do {
                let result = try await selector?.select(source: source, windows: windows, desktop: desktop, media: video ? .video : .image)
                if let result {
                    if result.media == .video {
                        // UI-only synthetic source: explicit Start fails instead of opening a real capture stream.
                        videoSession = VideoRecordingSession(selection: result, includesCursor: false, delaySeconds: 3,
                            files: VideoRecordingFiles(root: FileManager.default.temporaryDirectory.appendingPathComponent("Synthetic-Video-UI-\(UUID())")),
                            makeEngine: { VideoRecordingEngine(prepare: { _, _, _, _ in throw VideoRecordingError.windowUnavailable }) })
                        await videoSession?.run(startImmediately: true); videoSession = nil
                    } else { workspace.openScreenshot(try desktop.crop(result)) }
                }
            } catch { workspace.importError = error.localizedDescription }
            selector = nil
            NSApp.windows.first { $0.identifier?.rawValue == "workspace" }?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    static func sampleSelection() -> ScreenshotSelection {
        let screen = NSScreen.main!
        return ScreenshotSelection(displayID: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32,
            rect: CGRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 640, height: 400), screenFrame: screen.frame)
    }
    static func showScroll() {
        scrollSession = ManualScrollSession(selection: sampleSelection(), first: bitmap(width: 1280, height: 800))
        Task { _ = await scrollSession?.run(); scrollSession = nil }
    }
    static func showVideo() {
        videoSession = VideoRecordingSession(selection: sampleSelection(), includesCursor: false, delaySeconds: 3,
            files: VideoRecordingFiles(root: FileManager.default.temporaryDirectory.appendingPathComponent("Synthetic-Video-UI-\(UUID())")),
            makeEngine: { VideoRecordingEngine(prepare: { _, _, _, _ in throw VideoRecordingError.windowUnavailable }) })
        Task { await videoSession?.run(startImmediately: true); videoSession = nil }
    }
    static func showVideoEditorFlow(workspace: WorkspaceModel) {
        if let videoSession { videoSession.show(); return }
        let session = VideoRecordingSession(selection: sampleSelection(), includesCursor: false, files: workspace.videos.files,
            makeEngine: {
                VideoRecordingEngine { _, _, _, url in
                    try await SyntheticVideoFixture.write(to: url)
                    return PreparedVideoRecording(transport: UICompletedVideoTransport(), pixelSize: PixelSize(width: 320, height: 180)!)
                }
            })
        session.onFinished = { url in
            Task {
                workspace.libraryShowsVideos = true; workspace.section = .library
                await workspace.videos.showPreview(recording: url)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.identifier?.rawValue == "workspace" }?.makeKeyAndOrderFront(nil)
            }
        }
        videoSession = session
        Task { await session.run(startImmediately: true); videoSession = nil }
    }
    static func addVideos(workspace: WorkspaceModel) {
        Task {
            do {
                let files = workspace.videos.files
                let partial = try await files.prepare(availableBytes: 1_000_000_000)
                try await SyntheticVideoFixture.write(to: partial)
                _ = try await files.finalize(partial)
                let ready = try await files.list().items.first { $0.document.state == .finished }!
                try await files.rename(ready.id, title: "Synthetic support video")
                let failed = try await files.prepare(availableBytes: 1_000_000_000)
                try await files.markFailed(failed, message: "Synthetic storage error")
                let interrupted = try await files.prepare(availableBytes: 1_000_000_000)
                try await files.markFailed(interrupted, message: nil)
                await workspace.videos.refresh(); workspace.libraryShowsVideos = true; workspace.section = .library
            } catch { workspace.importError = error.localizedDescription }
        }
    }

    static func showWindowHover() {
        guard hoverPanel == nil, let screen = NSScreen.main else { return }
        let size = screen.frame.size, scale = screen.backingScaleFactor
        let rects = [CGRect(x: size.width * 0.08, y: size.height * 0.3, width: size.width * 0.5, height: size.height * 0.6),
                     CGRect(x: size.width * 0.48, y: size.height * 0.16, width: size.width * 0.45, height: size.height * 0.65),
                     CGRect(x: size.width * 0.13, y: size.height * 0.14, width: size.width * 0.24, height: size.height * 0.24)]
        let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor(srgbRed: 0.12, green: 0.19, blue: 0.32, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        for (index, rect) in rects.enumerated() {
            context.setFillColor(NSColor.white.cgColor); context.fill(rect)
            context.setFillColor(NSColor(srgbRed: 0.88, green: 0.93, blue: 1, alpha: 1).cgColor)
            context.fill(CGRect(x: rect.minX, y: rect.maxY - 36, width: rect.width, height: 36))
            context.setFillColor([NSColor.systemBlue, .systemGreen, .systemOrange][index].cgColor)
            context.fill(CGRect(x: rect.minX + 20, y: rect.minY + 20, width: rect.width - 40, height: rect.height - 76))
        }
        let panel = SelectionPanel(screenFrame: screen.frame)
        panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.hasShadow = false; panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        let view = SelectionView(frame: CGRect(origin: .zero, size: size))
        view.screenFrame = screen.frame; view.frozenImage = context.makeImage(); view.pixelScale = scale
        let targets = rects.map { $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY) }
        let close: () -> Void = { [weak panel, weak view] in
            view?.isFinishing = true
            panel?.orderOut(nil); panel?.close(); hoverPanel = nil
        }
        view.onHover = { [weak view] point in
            view?.setHoveredWindow(targets.reversed().first { $0.contains(point) })
        }
        view.onPropose = { [weak view] rect in
            guard let view, let selected = rect ?? view.highlight else { return }
            view.isReviewing = true; view.reviewDraft = CaptureSelectionDraft(rect: selected)
        }
        view.onRestart = { [weak view] in view?.isReviewing = false; view?.reviewDraft = nil; view?.highlight = nil }
        view.onCancel = close; view.onConfirm = { _ in close() }
        view.caption = "Synthetic windows · 180 ms glide · Esc: Close"
        let controls = NSHostingView(rootView: HStack {
            ForEach(0..<3) { [weak view] index in
                Button(["Window A", "Window B", "Small Window"][index]) { [weak view] in view?.setHoveredWindow(targets[index]) }
            }
            Button("Close Preview", action: close)
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)))
        controls.frame = CGRect(x: 24, y: 76, width: 550, height: 50)
        view.addSubview(controls)
        panel.contentView = view; hoverPanel = panel
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
    }

    static func resizeWorkspace(width: CGFloat, height: CGFloat) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" }) else { return }
        window.setContentSize(NSSize(width: width, height: height))
        window.makeKeyAndOrderFront(nil)
    }
    static func addFilmstripImages(workspace: WorkspaceModel) {
        Task {
            do {
                let image = bitmap(width: 640, height: 400)
                let original = try EditorRenderer.png(image: image, objects: [])
                for index in 1...12 {
                    var label = EditorObject(kind: .text, start: CGPoint(x: 120, y: 100), text: "Synthetic image \(index)", fontSize: 30)
                    label.color = EditorColor(red: Double(index % 3) / 3, green: 0.2, blue: 0.7)
                    let document = ProjectDocument(title: "Filmstrip image \(index)", pixelSize: PixelSize(width: 640, height: 400)!, objects: [label], createdAt: .now.addingTimeInterval(Double(index)))
                    try await workspace.store.create(document, original: original, thumbnail: EditorRenderer.thumbnail(image: image, objects: [label]))
                }
                await workspace.refreshLibrary()
            } catch { workspace.importError = error.localizedDescription }
        }
    }
    static func addSavedGuides(workspace: WorkspaceModel) {
        Task {
            do {
                for index in 1...2 {
                    try await workspace.guides.store.create(GuideDocument(title: "Synthetic guide \(index)"))
                }
                await workspace.guides.refresh()
                workspace.section = .guides
            } catch { workspace.guides.error = error.localizedDescription }
        }
    }
    static func holdPNGForImageSwitch(workspace: WorkspaceModel) {
        guard let old = workspace.editor, old.hasExportableImage, !old.isExporting else { return }
        Task {
            guard await old.flush() else { return }
            let gate = UIExportHold(); imageSwitchHold = gate
            let held = EditorModel(image: old.image, document: old.document, generation: old.savedRevision, store: workspace.store,
                writePNG: { data, url in await gate.pause(); try await EditorModel.writePNGData(data, to: url) },
                onSaved: { Task { await workspace.refreshLibrary() } })
            held.inheritToolSettings(from: old); workspace.editor = held
            _ = held.exportPNG(to: FileManager.default.temporaryDirectory.appendingPathComponent("Synthetic-held-export-\(UUID()).png"))
        }
    }
    static func releaseHeldPNG() {
        guard let gate = imageSwitchHold else { return }
        imageSwitchHold = nil
        Task { await gate.release() }
    }
}

struct EnglishUIFixtureCommands: Commands {
    let workspace: WorkspaceModel
    var body: some Commands {
        CommandMenu("UI QA") {
            Button("Minimum Window (800 × 540)") { EnglishUIFixture.resizeWorkspace(width: 800, height: 540) }
            Button("Default Window (1180 × 780)") { EnglishUIFixture.resizeWorkspace(width: 1180, height: 780) }
            Button("Add Synthetic Images (Filmstrip)") { EnglishUIFixture.addFilmstripImages(workspace: workspace) }
            Button("Add Synthetic Videos") { EnglishUIFixture.addVideos(workspace: workspace) }
            Button("Add Saved Guides (No Selection)") { EnglishUIFixture.addSavedGuides(workspace: workspace) }
            Button("Hold PNG Export (Image Switch)") { EnglishUIFixture.holdPNGForImageSwitch(workspace: workspace) }
            Button("Release Held PNG Export") { EnglishUIFixture.releaseHeldPNG() }
            Divider()
            Button("Window Hover Motion Preview") { EnglishUIFixture.showWindowHover() }
            Button("Synthetic Screenshot Selection") { EnglishUIFixture.showSelection(workspace: workspace, video: false) }
            Button("Synthetic Video Selection") { EnglishUIFixture.showSelection(workspace: workspace, video: true) }
            Button("Synthetic Window Video Selection") { EnglishUIFixture.showSelection(workspace: workspace, video: true, source: .window) }
            Button("Scroll Panel (Preview Only)") { EnglishUIFixture.showScroll() }
            Button("Video Countdown (Synthetic)") { EnglishUIFixture.showVideo() }
            Button("Synthetic Video to Internal Editor") { EnglishUIFixture.showVideoEditorFlow(workspace: workspace) }
        }
    }
}

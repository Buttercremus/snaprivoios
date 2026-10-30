import AppKit
import PDFKit
import ImageIO
import SnagForgeDomain

@main struct GuideChecks {
    @MainActor static func main() async throws {
        func require(_ value: Bool, _ message: String = "Guide check failed", file: StaticString = #file, line: UInt = #line) { precondition(value, message, file: file, line: line) }
        _ = NSApplication.shared
        func wait(_ model: GuideModel) async throws {
            for _ in 0..<1000 { if !model.isBusy { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Guide operation timed out")
        }
        if CommandLine.arguments.count == 3 {
            let stage = CommandLine.arguments[1]
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(CommandLine.arguments[2])
            let model = GuideModel(root: folder)
            if stage == "--write" {
                let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
                let doc = GuideDocument(title: "Process restart", steps: [GuideStep(title: "Before restart", png: try EditorRenderer.png(image: context.makeImage()!, objects: []))])
                try await model.store.create(doc); model.open(doc.id); try await wait(model)
                model.edit { $0.steps[0].caption = "Saved before process exit"; $0.style = .compact }
                require(await model.finishPendingWork())
            } else {
                await model.refresh(); require(model.documents.count == 1)
                model.open(model.documents[0].id); try await wait(model)
                require(model.document!.steps[0].caption == "Saved before process exit" && model.document!.style == .compact)
                try FileManager.default.removeItem(at: folder)
                print("Guide process restart passed: saved images, caption, order and style reopened in a fresh process.")
            }
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Snaprivo-Guides-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func bitmap(_ color: NSColor) -> CGImage {
            let c = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
            c.translateBy(x: 0, y: 80); c.scaleBy(x: 1, y: -1)
            c.setFillColor(color.cgColor); c.fill(CGRect(x: 21, y: 21, width: 48, height: 28))
            return c.makeImage()!
        }
        let projects = ProjectStore(root: root.appendingPathComponent("Projects"))
        var mask = EditorObject(kind: .redact, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 70, y: 50))
        mask.color = EditorColor(red: 0, green: 0, blue: 0)
        var steps: [GuideStep] = []
        for (color, secret) in [(NSColor.red, "ALPHA"), (.blue, "BETA")] {
            let image = bitmap(color), text = EditorObject(kind: .text, start: CGPoint(x: 22, y: 22), text: secret, fontSize: 8)
            let croppedText = EditorObject(kind: .text, start: CGPoint(x: 95, y: 75), text: "OUTSIDE_CROP", fontSize: 8)
            let project = ProjectDocument(title: "Source", pixelSize: PixelSize(width: 100, height: 80)!, objects: [text, croppedText, mask],
                crop: CGRect(x: 10, y: 10, width: 80, height: 60), resizedSize: PixelSize(width: 40, height: 30)!)
            try await projects.create(project, original: EditorRenderer.png(image: image, objects: []), thumbnail: nil)
            steps.append(try await GuideExporter.snapshot(projects.load(project.id), library: GuideModel.libraryKey(projects)))
        }
        require(steps[0].png == steps[1].png, "Covered original or cropped text leaked into the guide")
        require(GuideDocument.pngSize(steps[0].png) == PixelSize(width: 40, height: 30))
        let wide = CGContext(data: nil, width: 5000, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        wide.setFillColor(NSColor.white.cgColor); wide.fill(CGRect(x: 0, y: 0, width: 5000, height: 20))
        let wideDoc = ProjectDocument(title: "Wide screenshot", pixelSize: PixelSize(width: 5000, height: 20)!)
        try await projects.create(wideDoc, original: EditorRenderer.png(image: wide.makeImage()!, objects: []), thumbnail: nil)
        let bounded = try await GuideExporter.snapshot(projects.load(wideDoc.id), library: GuideModel.libraryKey(projects))
        require(GuideDocument.pngSize(bounded.png)!.width == 2560 && GuideDocument.pngSize(bounded.png)!.height >= 1)
        let invalidDoc = ProjectDocument(title: "Mismatched original", pixelSize: PixelSize(width: 100, height: 80)!)
        try await projects.create(invalidDoc, original: EditorRenderer.png(image: wide.makeImage()!, objects: []), thumbnail: nil)
        do { _ = try await GuideExporter.snapshot(projects.load(invalidDoc.id), library: GuideModel.libraryKey(projects)); preconditionFailure("Accepted wrong source dimensions") } catch {}
        let rep = NSBitmapImageRep(data: steps[0].png)!, center = rep.colorAt(x: 20, y: 15)!.usingColorSpace(.sRGB)!
        require(center.redComponent == 0 && center.blueComponent == 0 && center.alphaComponent == 1)
        steps[0].title = "FIRST_STEP"; steps[0].caption = "Caption with umlauts: Grüße München & <literal>"
        steps[1].title = "SECOND_STEP"; steps[1].caption = "Final caption."
        var doc = GuideDocument(title: "Synthetic guide", introduction: "Cover introduction.", steps: steps)
        for style in GuideStyle.allCases {
            doc.style = style
            let pdf = try GuideExporter.pdf(doc), parsed = PDFDocument(data: pdf)!
            require(parsed.pageCount == (style == .standard ? 3 : 2) && parsed.string!.contains("Grüße München"))
            require(parsed.page(at: 1)!.string!.contains("FIRST_STEP"))
            require(parsed.page(at: style == .standard ? 2 : 1)!.string!.contains("SECOND_STEP"))
            for secret in ["ALPHA", "BETA", "OUTSIDE_CROP", projects.root.path, steps[0].sourceProjectID!.uuidString] {
                require(!parsed.string!.contains(secret) && !String(decoding: pdf, as: UTF8.self).contains(secret))
            }
            for index in 0..<parsed.pageCount {
                let page = parsed.page(at: index)!
                require(page.annotations.isEmpty)
                let bounds = page.bounds(for: .mediaBox)
                for character in 0..<page.numberOfCharacters {
                    let rect = page.characterBounds(at: character)
                    require(rect.isEmpty || bounds.insetBy(dx: 10, dy: 10).contains(rect), "PDF text clipped outside the page")
                }
                let raster = CGContext(data: nil, width: 596, height: 842, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                raster.setFillColor(NSColor.white.cgColor); raster.fill(bounds)
                page.draw(with: .mediaBox, to: raster)
                let sample = NSBitmapImageRep(cgImage: raster.makeImage()!)
                for y in stride(from: 0, to: 842, by: 3) { for x in stride(from: 0, to: 596, by: 3) {
                    let color = sample.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    require(abs(color.redComponent - color.blueComponent) < 0.02, "Secret colored pixels leaked into PDF")
                } }
            }
            if let output = ProcessInfo.processInfo.environment["SNAPRIVO_GUIDE_QA_OUTPUT"] {
                try pdf.write(to: URL(fileURLWithPath: output).appendingPathComponent("guide-\(style.rawValue).pdf"))
            }
        }
        doc.includesCover = false
        let noCover = PDFDocument(data: try GuideExporter.pdf(doc))!
        require(noCover.pageCount == 2 && noCover.page(at: 0)!.string!.contains("FIRST_STEP"))
        doc.style = .standard
        let noCoverStandard = PDFDocument(data: try GuideExporter.pdf(doc))!
        require(noCoverStandard.pageCount == 2 && noCoverStandard.page(at: 0)!.string!.contains("Synthetic guide"))
        doc.includesCover = true; doc.style = .compact
        // Pagination must retain all text, including the last paragraph and long unbroken words.
        doc.introduction = String(repeating: "A long introduction with line wrapping. ", count: 180) + "INTRO_END"
        doc.steps[0].caption = String(repeating: "Paragraph with descriptive text and line breaks.\n", count: 140) + "CAPTION_END"
        doc.steps[1].caption = String(repeating: "W", count: 2000) + "WORD_END"
        let longPDF = PDFDocument(data: try GuideExporter.pdf(doc))!
        let text = longPDF.string!.replacingOccurrences(of: "\n", with: "")
        require(longPDF.pageCount > 5 && text.contains("INTRO_END") && text.contains("CAPTION_END") && text.contains("WORD_END"))
        let markdownURL = root.appendingPathComponent("Markdown")
        try GuideExporter.markdown(doc, to: markdownURL)
        let markdown = try String(contentsOf: markdownURL.appendingPathComponent("Anleitung.md"), encoding: .utf8)
        require(markdown.contains("CAPTION\\_END"))
        require(try Data(contentsOf: markdownURL.appendingPathComponent("images/0001.png")) == steps[0].png)
        require(Set(try FileManager.default.contentsOfDirectory(atPath: markdownURL.path)) == ["Anleitung.md", "images"])
        do { try GuideExporter.markdown(doc, to: markdownURL); preconditionFailure("Overwrote existing Markdown folder") } catch {}
        require(try Data(contentsOf: markdownURL.appendingPathComponent("images/0001.png")) == steps[0].png)
        var broken = doc; broken.steps[1].png = steps[1].png.prefix(33)
        let brokenURL = root.appendingPathComponent("Broken")
        do { try GuideExporter.markdown(broken, to: brokenURL); preconditionFailure("Accepted a truncated PNG") } catch {}
        require(!FileManager.default.fileExists(atPath: brokenURL.path))
        // Imported PNGs can contain comments: all external outputs must discard them.
        let annotatedPNG = NSMutableData()
        let pngWriter = CGImageDestinationCreateWithData(annotatedPNG, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(pngWriter, try GuideExporter.image(steps[0].png),
            [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGComment: "METADATA_SECRET"]] as CFDictionary)
        require(CGImageDestinationFinalize(pngWriter))
        var metadataGuide = doc; metadataGuide.steps[0].png = annotatedPNG as Data
        require(String(decoding: metadataGuide.steps[0].png, as: UTF8.self).contains("METADATA_SECRET"))
        let sanitized = try GuideExporter.cleanCopy(metadataGuide)
        require(!String(decoding: sanitized.steps[0].png, as: UTF8.self).contains("METADATA_SECRET"))
        let cleanMarkdown = root.appendingPathComponent("CleanMarkdown")
        try GuideExporter.markdown(metadataGuide, to: cleanMarkdown)
        require(!String(decoding: try Data(contentsOf: cleanMarkdown.appendingPathComponent("images/0001.png")), as: UTF8.self).contains("METADATA_SECRET"))
        let cancellationDocument = doc
        let cancelled = Task.detached { withUnsafeCurrentTask { $0?.cancel() }; return try GuideExporter.pdf(cancellationDocument) }
        do { _ = try await cancelled.value; preconditionFailure("Ignored export cancellation") } catch is CancellationError {}

        let model = GuideModel(root: root.appendingPathComponent("Guides"))
        model.create(); try await wait(model)
        require(model.document != nil && model.error == nil && model.focusesTitle)
        // Creating again reuses the untouched new guide and only refocuses its title.
        let untouched = model.document!.id; model.focusesTitle = false
        model.create(); try await wait(model)
        require(model.document!.id == untouched && model.documents.count == 1 && model.focusesTitle)
        model.addProjects(steps.compactMap(\.sourceProjectID), from: projects, prepare: { true }); try await wait(model)
        require(model.document!.steps.count == 2 && !model.isDirty)
        let guideID = model.document!.id, first = model.document!.steps[0].id
        model.edit { $0.title = "Edited guide"; $0.moveStep(first, by: 1); $0.style = .compact }
        model.editStep(first) { $0.caption = "Saved caption" }
        model.isSuspended = true
        model.edit { $0.title = "Must not change while quitting" }; model.create()
        require(model.document!.title == "Edited guide" && !model.isBusy)
        require(await model.finishPendingWork())
        model.isSuspended = false
        let reopen = GuideModel(root: model.store.root); reopen.open(guideID); try await wait(reopen)
        require(reopen.document!.title == "Edited guide" && reopen.document!.steps[1].caption == "Saved caption" && reopen.document!.style == .compact)
        model.edit { $0.introduction = "Saved by another instance" }; require(await model.flush())
        reopen.edit { $0.introduction = "My unsaved competing changes" }
        require(!(await reopen.flush()) && reopen.isDirty)
        reopen.saveAsCopy(); try await wait(reopen)
        require(reopen.document!.id != guideID && reopen.document!.introduction == "My unsaved competing changes" && !reopen.isDirty)
        // Updating a source keeps the chosen step identity, title, caption and order.
        let target = reopen.document!.steps[1]
        var updatedSource = try await projects.load(steps[1].sourceProjectID!).document
        updatedSource.objects.append(EditorObject(kind: .rectangle, start: CGPoint(x: 75, y: 55), end: CGPoint(x: 85, y: 65)))
        updatedSource.revision += 1
        try await projects.save(updatedSource, expectedGeneration: 0, thumbnail: nil)
        reopen.addProjects([steps[1].sourceProjectID!], from: projects, replacing: target.id, prepare: { true }); try await wait(reopen)
        require(reopen.document!.steps[1].id == target.id && reopen.document!.steps[1].caption == target.caption)
        require(reopen.document!.steps[1].png != target.png, "Updating a project did not refresh its visible pixels")
        let portable = root.appendingPathComponent("Portable.snaprivoguide")
        reopen.export(.workingCopy, to: portable); try await wait(reopen)
        require(try GuideDocument.read(portable).steps.allSatisfy { $0.sourceProjectID == nil && $0.sourceLibrary == nil })
        reopen.importCopy(portable); try await wait(reopen)
        require(reopen.document!.id != guideID && reopen.document!.steps.count == 2)
        // A failed save blocks switching/quit and retains the edited working state for retry.
        reopen.edit { $0.title = "" }
        require(!(await reopen.finishPendingWork()) && reopen.isDirty && reopen.error != nil)
        reopen.edit { $0.title = "Recovered title" }
        require(await reopen.finishPendingWork())
        // Every structural edit survives autosave and is reversible using the current revision.
        let historyModel = GuideModel(root: root.appendingPathComponent("History"))
        historyModel.createFromProjects(steps.compactMap(\.sourceProjectID), from: projects, prepare: { true }); try await wait(historyModel)
        let initialHistory = historyModel.document!, firstID = initialHistory.steps[0].id
        let provider = NSItemProvider(object: "\(initialHistory.id):\(firstID)" as NSString)
        let dragPayload: String = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, error in
                if let text = object as? String { continuation.resume(returning: text) }
                else { continuation.resume(throwing: error ?? ProjectError.invalidDocument) }
            }
        }
        require(historyModel.moveStep(payload: dragPayload, documentID: initialHistory.id, before: nil) == firstID)
        require(historyModel.document!.steps.last?.id == firstID)
        historyModel.undo(); require(historyModel.document!.steps == initialHistory.steps)
        let beforeRejectedDrop = historyModel.document!
        for payload in ["../../outside", "\(UUID()):\(firstID)", "\(initialHistory.id):\(UUID())"] {
            require(historyModel.moveStep(payload: payload, documentID: initialHistory.id, before: nil) == nil)
        }
        require(historyModel.moveStep(payload: dragPayload, documentID: UUID(), before: nil) == nil)
        require(historyModel.moveStep(payload: dragPayload, documentID: initialHistory.id, before: UUID()) == nil)
        historyModel.requestFeature = { _ in false }
        require(historyModel.moveStep(payload: dragPayload, documentID: initialHistory.id, before: nil) == nil)
        require(historyModel.document == beforeRejectedDrop)
        historyModel.requestFeature = { _ in true }
        historyModel.edit { $0.moveStep(firstID, before: nil) }; require(await historyModel.flush())
        historyModel.undo(); require(historyModel.document!.steps == initialHistory.steps)
        require(await historyModel.flush())
        historyModel.redo(); require(historyModel.document!.steps.last?.id == firstID)
        historyModel.removeStep(firstID); require(historyModel.document!.steps.count == 1)
        historyModel.undo(); require(historyModel.document!.steps.count == 2)
        historyModel.edit(textGroup: "title") { $0.title = "Typed" }
        historyModel.edit(textGroup: "title") { $0.title = "Typed together" }
        historyModel.undo(); require(historyModel.document!.title == initialHistory.title)
        historyModel.redo(); require(historyModel.document!.title == "Typed together")
        let replacementTarget = historyModel.document!.steps[0]
        historyModel.addProjects([wideDoc.id], from: projects, replacing: replacementTarget.id, prepare: { true }); try await wait(historyModel)
        require(historyModel.document!.steps[0].png != replacementTarget.png)
        historyModel.undo(); require(historyModel.document!.steps[0] == replacementTarget)
        require(await historyModel.flush())
        let duplicatedFrom = historyModel.document!
        historyModel.duplicate(); try await wait(historyModel)
        require(historyModel.document!.id != duplicatedFrom.id && historyModel.document!.steps == duplicatedFrom.steps)
        let copyID = historyModel.document!.id
        historyModel.moveToTrash(copyID); try await wait(historyModel)
        require(historyModel.document == nil && historyModel.trash.count == 1)
        historyModel.restore(copyID); try await wait(historyModel)
        historyModel.open(copyID); try await wait(historyModel)
        require(historyModel.document!.steps == duplicatedFrom.steps)
        let failedExport = root.appendingPathComponent("Blocked.pdf")
        try FileManager.default.createDirectory(at: failedExport, withIntermediateDirectories: false)
        historyModel.export(.pdf, to: failedExport); try await wait(historyModel)
        require(historyModel.error != nil && historyModel.failureContext == .output(.pdf))
        require(await historyModel.flush()); require(historyModel.error != nil, "Unrelated save erased an export error")
        try FileManager.default.removeItem(at: failedExport)
        historyModel.export(.pdf, to: failedExport); try await wait(historyModel)
        require(historyModel.error == nil && PDFDocument(url: failedExport) != nil)

        // Individual step actions keep image snapshots, sources, history and disk state coherent.
        let actionModel = GuideModel(root: root.appendingPathComponent("StepActions"))
        let actionDocument = GuideDocument(title: "Searchable workflow", introduction: "Office network", steps: steps)
        try await actionModel.store.create(actionDocument)
        actionModel.open(actionDocument.id); try await wait(actionModel)
        actionModel.duplicateStep(steps[0].id)
        let copiedStep = actionModel.document!.steps[1]
        require(copiedStep.id != steps[0].id && copiedStep.png == steps[0].png && copiedStep.sourceProjectID == steps[0].sourceProjectID)
        require(actionModel.selectedStep == copiedStep.id && actionModel.stepToReveal == copiedStep.id)
        require(await actionModel.flush())
        require(try await actionModel.store.load(actionDocument.id).document.steps.count == 3)
        actionModel.undo(); require(actionModel.document!.steps == steps)
        actionModel.redo(); require(actionModel.document!.steps[1] == copiedStep)
        actionModel.addProjects([steps[1].sourceProjectID!], from: projects, at: .before(steps[0].id), prepare: { true })
        try await wait(actionModel)
        require(actionModel.document!.steps[1] == steps[0])
        actionModel.addProjects([steps[0].sourceProjectID!], from: projects, at: .after(copiedStep.id), prepare: { true })
        try await wait(actionModel)
        require(actionModel.document!.steps[3].id == actionModel.selectedStep)
        let beforeInvalid = actionModel.document!
        actionModel.addProjects([steps[0].sourceProjectID!], from: projects, at: .after(UUID()), prepare: { true })
        try await wait(actionModel)
        require(actionModel.document == beforeInvalid && actionModel.error != nil)
        actionModel.requestFeature = { _ in false }
        actionModel.duplicateStep(steps[0].id); require(actionModel.document == beforeInvalid)
        actionModel.requestFeature = { _ in true }
        // Search must see text before the delayed autosave, including its stable jump target.
        actionModel.editStep(copiedStep.id) { $0.caption = "Unsaved UNIQUE_NEEDLE" }
        actionModel.searchQuery = "unique_needle"
        for _ in 0..<500 { if !actionModel.isSearching { break }; try await Task.sleep(for: .milliseconds(10)) }
        let hit = actionModel.searchResults.first!
        require(hit.stepID == copiedStep.id && hit.documentID == actionDocument.id)
        actionModel.open(hit.documentID, revealing: hit.stepID, fromSearch: true)
        require(actionModel.selectedStep == copiedStep.id && actionModel.stepToReveal == copiedStep.id)
        actionModel.stepToReveal = nil
        actionModel.open(hit.documentID, revealing: hit.stepID, fromSearch: true)
        require(actionModel.stepToReveal == copiedStep.id, "Repeated search hit did not request another reveal")
        actionModel.searchQuery = "office network"
        for _ in 0..<500 { if !actionModel.isSearching { break }; try await Task.sleep(for: .milliseconds(10)) }
        require(actionModel.searchResults.first?.stepID == nil)
        require(await actionModel.finishPendingWork())

        // 100 large visible images: text saves write only small manifests and leave assets untouched.
        let largeStore = GuideStore(root: root.appendingPathComponent("Large"))
        let largePNGs = try await Task.detached {
            var bytes = [UInt8](repeating: 255, count: 640 * 480 * 4)
            var seed: UInt64 = 42
            for i in stride(from: 0, to: bytes.count, by: 4) {
                for channel in 0..<3 { seed = seed &* 6364136223846793005 &+ 1; bytes[i + channel] = UInt8(truncatingIfNeeded: seed >> 32) }
            }
            var images: [Data] = []
            for index in 0..<100 {
                bytes[0] = UInt8(index)
                let png = try bytes.withUnsafeMutableBytes { buffer in
                    let context = CGContext(data: buffer.baseAddress, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 640 * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    return try EditorRenderer.png(image: context.makeImage()!, objects: [])
                }
                images.append(png)
            }
            return images
        }.value
        var large = GuideDocument(title: "100 large images", steps: largePNGs.enumerated().map { GuideStep(title: "Step \($0.offset)", png: $0.element) })
        try await largeStore.create(large)
        let assetFolder = largeStore.root.appendingPathComponent(".assets/\(large.id)")
        let assets = try FileManager.default.contentsOfDirectory(at: assetFolder, includingPropertiesForKeys: nil)
        require(assets.count == 100)
        let modifications = try assets.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let started = ContinuousClock.now
        for i in 0..<10 { large.steps[0].caption = "Text revision \(i)"; large = try await largeStore.save(large, expectedRevision: large.revision) }
        let elapsed = started.duration(to: .now)
        let manifestSize = try Data(contentsOf: largeStore.root.appendingPathComponent("\(large.id).snaprivoguide")).count
        require(manifestSize < 64_000)
        require(try assets.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate } == modifications)
        require(try await GuideStore(root: largeStore.root).load(large.id).document == large)
        print("Large guide: \(largePNGs.reduce(0) { $0 + $1.count }) image bytes; \(manifestSize)-byte manifest; 10 text saves \(elapsed), images unchanged.")
        print("Guide checks passed: flattened crop/resize/redaction, both PDF styles, Unicode/pagination/page bounds, Markdown assets/escaping/atomic failures/cancellation, autosave/reopen/update/import/export/save recovery.")
    }
}

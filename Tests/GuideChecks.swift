import AppKit
import PDFKit
import ImageIO
import SnagForgeDomain

@main struct GuideChecks {
    @MainActor static func main() async throws {
        func require(_ value: Bool, _ message: String = "Guide check failed") { precondition(value, message) }
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
            require(parsed.pageCount == 3 && parsed.string!.contains("Grüße München"))
            require(parsed.page(at: 1)!.string!.contains("FIRST_STEP") && parsed.page(at: 2)!.string!.contains("SECOND_STEP"))
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
        require(model.document != nil && model.error == nil)
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
        print("Guide checks passed: flattened crop/resize/redaction, both PDF styles, Unicode/pagination/page bounds, Markdown assets/escaping/atomic failures/cancellation, autosave/reopen/update/import/export/save recovery.")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Converts files between formats, entirely on this Mac. Audio and video go
/// through ffmpeg, images through ImageIO (WebP through cwebp), documents
/// through textutil and CoreText, PDFs through PDFKit, and spreadsheets are
/// read natively (XLSX to CSV/TSV) or handed to LibreOffice for the rest.
/// Work happens in a temporary folder and is moved next to the original only
/// once it succeeds, so Stop never leaves half-written output behind.
final class ConverterService: ObservableObject {
    static let shared = ConverterService()

    enum Status: Equatable {
        case pending, running
        case done(URL)
        case failed(String)
    }

    struct Job: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var status: Status = .pending
    }

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var isRunning = false
    @Published private(set) var usedFallbackFolder = false
    @Published private(set) var toolRevision = 0

    private let queue = DispatchQueue(label: "chikit.converter", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false
    private var currentProcess: Process?

    private init() {}

    // MARK: Tools

    private static let toolFolders = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/local/bin"]

    static func tool(_ name: String, extra: [String] = []) -> String? {
        (extra + toolFolders.map { "\($0)/\(name)" })
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var ffmpegPath: String? { tool("ffmpeg") }
    static var cwebpPath: String? { tool("cwebp") }
    static var libreOfficePath: String? {
        tool("soffice", extra: ["/Applications/LibreOffice.app/Contents/MacOS/soffice"])
    }

    var libreOfficeAvailable: Bool { Self.libreOfficePath != nil }

    /// Re-checks for tools installed while the panel is open.
    func refreshTools() { toolRevision += 1 }

    /// What is missing for this target, as a ready-to-show hint.
    static func missingToolHint(for format: ConvertFormat) -> String? {
        switch format.engine {
        case .ffmpeg where ffmpegPath == nil: return "Needs ffmpeg: brew install ffmpeg"
        case .cwebp where cwebpPath == nil: return "Needs cwebp: brew install webp"
        case .libreOffice where libreOfficePath == nil: return "Needs LibreOffice: brew install --cask libreoffice"
        default: return nil
        }
    }

    // MARK: Control

    func reset() {
        guard !isRunning else { return }
        jobs = []
        usedFallbackFolder = false
    }

    func stop() {
        lock.lock()
        cancelled = true
        let process = currentProcess
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    /// Converts every file in order. Safe to call only while idle.
    func convert(_ urls: [URL], to format: ConvertFormat, options: ConvertOptions) {
        guard !isRunning, !urls.isEmpty else { return }
        jobs = urls.map { Job(url: $0) }
        isRunning = true
        usedFallbackFolder = false
        lock.lock(); cancelled = false; lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            for index in urls.indices {
                if self.isCancelled { self.update(index) { $0.status = .failed("Stopped") }; continue }
                self.update(index) { $0.status = .running }
                let result = self.convertOne(urls[index], format: format, options: options)
                switch result {
                case .success(let output):
                    if options.trashOriginals {
                        try? FileManager.default.trashItem(at: urls[index], resultingItemURL: nil)
                    }
                    self.update(index) { $0.status = .done(output) }
                case .failure(let error):
                    self.update(index) { $0.status = .failed(error.message) }
                }
            }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    private func update(_ index: Int, _ change: @escaping (inout Job) -> Void) {
        DispatchQueue.main.async {
            guard self.jobs.indices.contains(index) else { return }
            change(&self.jobs[index])
        }
    }

    // MARK: One file

    struct ConvertError: Error { let message: String }

    private func convertOne(_ input: URL, format: ConvertFormat, options: ConvertOptions) -> Result<URL, ConvertError> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("chikit-convert-\(UUID().uuidString)", isDirectory: true)
        do { try fm.createDirectory(at: work, withIntermediateDirectories: true) } catch {
            return .failure(ConvertError(message: "Could not create a working folder."))
        }
        defer { try? fm.removeItem(at: work) }

        let produced: Result<URL, ConvertError>
        switch format.engine {
        case .ffmpeg: produced = viaFFmpeg(input, format, options, work)
        case .imageIO: produced = viaImageIO(input, format, options, work)
        case .cwebp: produced = viaCWebP(input, options, work)
        case .pdfKit: produced = viaPDFKit(input, format, options, work)
        case .textutil:
            // PDF to Word/ODT/RTF: LibreOffice's PDF import keeps blocks where
            // they sit on the page; textutil only gets the text.
            let filters = ["docx": "docx:MS Word 2007 XML", "odt": "odt:writer8", "rtf": "rtf:Rich Text Format"]
            if format.kind == .pdf, Self.libreOfficePath != nil, let filter = filters[format.ext],
               case .success(let doc) = viaLibreOffice(input, format, work, filter: filter,
                                                       infilter: "writer_pdf_import") {
                produced = .success(doc)
            } else {
                produced = viaTextutil(input, format, work)
            }
        case .appKitPDF:
            // LibreOffice keeps the page layout of the original; the CoreText
            // path only reproduces text and basic styling, so it is the fallback.
            let ext = input.pathExtension.lowercased()
            if Self.libreOfficePath != nil, ext != "md", ext != "markdown",
               case .success(let pdf) = viaLibreOffice(input, format, work,
                                                       filter: ext == "html" || ext == "htm"
                                                           ? "pdf:writer_web_pdf_Export" : "pdf:writer_pdf_Export") {
                produced = .success(pdf)
            } else {
                produced = viaCoreTextPDF(input, options, work)
            }
        case .nativeSpreadsheet:
            produced = XLSXReader.isXLSX(input)
                ? viaNativeSpreadsheet(input, format, work)
                : viaLibreOffice(input, format, work)
        case .libreOffice: produced = viaLibreOffice(input, format, work)
        }
        if isCancelled { return .failure(ConvertError(message: "Stopped")) }
        guard case .success(let temp) = produced else { return produced }
        return place(temp, original: input, ext: format.ext)
    }

    /// Moves the finished output beside the original ("song.mp3", then
    /// "song 2.mp3"), or into Downloads when that folder is read-only.
    private func place(_ temp: URL, original: URL, ext: String) -> Result<URL, ConvertError> {
        let fm = FileManager.default
        var directory = original.deletingLastPathComponent()
        if !fm.isWritableFile(atPath: directory.path),
           let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            directory = downloads
            DispatchQueue.main.async { self.usedFallbackFolder = true }
        }
        var isDirectory: ObjCBool = false
        fm.fileExists(atPath: temp.path, isDirectory: &isDirectory)
        let target = ConverterSupport.uniqueURL(directory: directory,
                                                baseName: original.deletingPathExtension().lastPathComponent,
                                                ext: isDirectory.boolValue ? "" : ext)
        do {
            try fm.moveItem(at: temp, to: target)
            return .success(target)
        } catch {
            return .failure(ConvertError(message: "Could not save the result: \(error.localizedDescription)"))
        }
    }

    // MARK: Process

    private func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 3600)
        -> (status: Int32, stderr: String) {
        if isCancelled { return (-1, "Stopped") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe

        let buffer = LockedBuffer(limit: 16 * 1024)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { buffer.append(chunk) }
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        lock.lock(); currentProcess = process; lock.unlock()
        defer { lock.lock(); currentProcess = nil; lock.unlock() }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return (-1, error.localizedDescription)
        }
        if isCancelled { process.terminate() }
        if finished.wait(timeout: .now() + timeout) == .timedOut { process.terminate(); _ = finished.wait(timeout: .now() + 5) }
        pipe.fileHandleForReading.readabilityHandler = nil
        return (process.terminationStatus, buffer.string())
    }

    private static func lastLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init) ?? "The conversion failed."
    }

    // MARK: ffmpeg

    private func viaFFmpeg(_ input: URL, _ format: ConvertFormat, _ options: ConvertOptions, _ work: URL)
        -> Result<URL, ConvertError> {
        guard let ffmpeg = Self.ffmpegPath else {
            return .failure(ConvertError(message: "ffmpeg is not installed (brew install ffmpeg)."))
        }
        let out = work.appendingPathComponent("out").appendingPathExtension(format.ext)
        var lastError = "The conversion failed."
        for variant in ConverterSupport.ffmpegVariants(for: format.id, quality: options.quality) {
            try? FileManager.default.removeItem(at: out)
            let args = ["-nostdin", "-y", "-v", "error", "-i", input.path] + variant + [out.path]
            let result = run(ffmpeg, args)
            if isCancelled { return .failure(ConvertError(message: "Stopped")) }
            if result.status == 0, FileManager.default.fileExists(atPath: out.path) { return .success(out) }
            lastError = Self.lastLine(result.stderr)
        }
        return .failure(ConvertError(message: lastError))
    }

    // MARK: Images

    private func loadImage(_ url: URL) -> CGImage? {
        if url.pathExtension.lowercased() == "svg" {
            guard let image = NSImage(contentsOf: url) else { return nil }
            // Rasterise vectors at a useful size rather than their nominal one.
            let size = image.size
            let scale = max(1, 2048 / max(size.width, size.height, 1))
            let target = NSSize(width: size.width * scale, height: size.height * scale)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            image.draw(in: NSRect(origin: .zero, size: target))
            NSGraphicsContext.restoreGraphicsState()
            return context.makeImage()
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height, 1)
        // The thumbnail path applies the EXIF orientation; a plain decode would not.
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ] as CFDictionary)
        return thumbnail ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func flattened(_ image: CGImage) -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    private func writeImage(_ image: CGImage, ext: String, quality: Double, to url: URL) -> Bool {
        let type: UTType
        var cg = image
        switch ext {
        case "jpg": type = .jpeg; cg = flattened(image)
        case "png": type = .png
        case "heic": type = .heic
        case "tiff": type = .tiff
        case "gif": type = .gif
        case "bmp": type = .bmp; cg = flattened(image)
        default: return false
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, cg,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private func viaImageIO(_ input: URL, _ format: ConvertFormat, _ options: ConvertOptions, _ work: URL)
        -> Result<URL, ConvertError> {
        guard let image = loadImage(input) else {
            return .failure(ConvertError(message: "This image could not be read."))
        }
        let out = work.appendingPathComponent("out").appendingPathExtension(format.ext)
        guard writeImage(image, ext: format.ext, quality: options.quality.imageQuality, to: out) else {
            return .failure(ConvertError(message: "This Mac cannot write \(format.label)."))
        }
        return .success(out)
    }

    private func viaCWebP(_ input: URL, _ options: ConvertOptions, _ work: URL) -> Result<URL, ConvertError> {
        guard let cwebp = Self.cwebpPath else {
            return .failure(ConvertError(message: "cwebp is not installed (brew install webp)."))
        }
        guard let image = loadImage(input) else {
            return .failure(ConvertError(message: "This image could not be read."))
        }
        let png = work.appendingPathComponent("source.png")
        guard writeImage(image, ext: "png", quality: 1, to: png) else {
            return .failure(ConvertError(message: "This image could not be prepared."))
        }
        let out = work.appendingPathComponent("out.webp")
        let result = run(cwebp, ["-quiet", "-q", String(Int(options.quality.imageQuality * 100)),
                                 png.path, "-o", out.path])
        guard result.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            return .failure(ConvertError(message: Self.lastLine(result.stderr)))
        }
        return .success(out)
    }

    // MARK: PDF

    private func viaPDFKit(_ input: URL, _ format: ConvertFormat, _ options: ConvertOptions, _ work: URL)
        -> Result<URL, ConvertError> {
        switch format.id {
        case "img-pdf":
            guard let cg = loadImage(input) else {
                return .failure(ConvertError(message: "This image could not be read."))
            }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            guard let page = PDFPage(image: image) else {
                return .failure(ConvertError(message: "This image could not be placed in a PDF."))
            }
            let document = PDFDocument()
            document.insert(page, at: 0)
            let out = work.appendingPathComponent("out.pdf")
            return document.write(to: out) ? .success(out)
                : .failure(ConvertError(message: "The PDF could not be written."))
        case "pdf-png", "pdf-jpg":
            guard let document = PDFDocument(url: input), document.pageCount > 0 else {
                return .failure(ConvertError(message: "This PDF could not be read."))
            }
            let ext = format.ext
            let folder = work.appendingPathComponent("pages", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let digits = String(document.pageCount).count
            for index in 0..<document.pageCount {
                if isCancelled { return .failure(ConvertError(message: "Stopped")) }
                guard let page = document.page(at: index), let image = render(page, dpi: 150) else {
                    return .failure(ConvertError(message: "Page \(index + 1) could not be rendered."))
                }
                let name = document.pageCount == 1
                    ? "page" : "page-" + String(format: "%0\(digits)d", index + 1)
                let file = folder.appendingPathComponent(name).appendingPathExtension(ext)
                guard writeImage(image, ext: ext, quality: options.quality.imageQuality, to: file) else {
                    return .failure(ConvertError(message: "Page \(index + 1) could not be saved."))
                }
            }
            if document.pageCount == 1 {
                let single = work.appendingPathComponent("out").appendingPathExtension(ext)
                try? FileManager.default.moveItem(at: folder.appendingPathComponent("page").appendingPathExtension(ext),
                                                  to: single)
                return .success(single)
            }
            return .success(folder)
        case "pdf-txt":
            guard let text = PDFDocument(url: input)?.string, !text.isEmpty else {
                return .failure(ConvertError(message: "This PDF has no selectable text."))
            }
            let out = work.appendingPathComponent("out.txt")
            do { try text.write(to: out, atomically: true, encoding: .utf8) } catch {
                return .failure(ConvertError(message: "The text could not be written."))
            }
            return .success(out)
        default:
            return .failure(ConvertError(message: "Unsupported PDF conversion."))
        }
    }

    private func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0, width * height < 200_000_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: Documents

    private static let textutilNames: [String: String] = [
        "docx": "docx", "doc": "doc", "odt": "odt", "rtf": "rtf", "txt": "txt", "html": "html",
    ]

    private func markdownRTF(_ input: URL, _ work: URL) -> URL? {
        guard let source = try? String(contentsOf: input, encoding: .utf8) else { return nil }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: source, options: options) else { return nil }
        let ns = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        ns.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: ns.length))
        // Keep inline bold/italic from the markdown, which the line above replaced.
        let styled = NSAttributedString(attributed)
        styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attrs, range, _ in
            if let intent = attrs[NSAttributedString.Key("NSInlinePresentationIntent")] as? Int {
                var traits: NSFontTraitMask = []
                if intent & 1 != 0 { traits.insert(.italicFontMask) }
                if intent & 2 != 0 { traits.insert(.boldFontMask) }
                let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: traits)
                ns.addAttribute(.font, value: font, range: range)
            }
        }
        guard let data = try? ns.data(from: NSRange(location: 0, length: ns.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        else { return nil }
        let out = work.appendingPathComponent("markdown.rtf")
        return (try? data.write(to: out)) != nil ? out : nil
    }

    /// An input textutil can read: Markdown is turned into RTF first.
    private func textutilInput(_ input: URL, _ work: URL) -> URL? {
        let ext = input.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" { return markdownRTF(input, work) }
        return input
    }

    private func viaTextutil(_ input: URL, _ format: ConvertFormat, _ work: URL) -> Result<URL, ConvertError> {
        var source = input
        if format.kind == .pdf {
            guard let text = PDFDocument(url: input)?.string, !text.isEmpty else {
                return .failure(ConvertError(message: "This PDF has no selectable text."))
            }
            source = work.appendingPathComponent("pdf-text.txt")
            guard (try? text.write(to: source, atomically: true, encoding: .utf8)) != nil else {
                return .failure(ConvertError(message: "The text could not be prepared."))
            }
        } else if let prepared = textutilInput(input, work) {
            source = prepared
        } else {
            return .failure(ConvertError(message: "This document could not be read."))
        }
        guard let name = Self.textutilNames[format.ext] else {
            return .failure(ConvertError(message: "Unsupported document format."))
        }
        let out = work.appendingPathComponent("out").appendingPathExtension(format.ext)
        let result = run("/usr/bin/textutil", ["-convert", name, "-output", out.path, source.path], timeout: 300)
        guard result.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            return .failure(ConvertError(message: Self.lastLine(result.stderr)))
        }
        return .success(out)
    }

    /// Document to PDF: textutil normalises the source to RTF, CoreText lays
    /// it out across pages. Plain and styled text come through; embedded
    /// images and complex tables do not.
    private func viaCoreTextPDF(_ input: URL, _ options: ConvertOptions, _ work: URL) -> Result<URL, ConvertError> {
        var rtf: URL
        let ext = input.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            guard let made = markdownRTF(input, work) else {
                return .failure(ConvertError(message: "This Markdown file could not be read."))
            }
            rtf = made
        } else {
            rtf = work.appendingPathComponent("source.rtf")
            let result = run("/usr/bin/textutil", ["-convert", "rtf", "-output", rtf.path, input.path], timeout: 300)
            guard result.status == 0 else {
                return .failure(ConvertError(message: Self.lastLine(result.stderr)))
            }
        }
        guard let text = try? NSAttributedString(url: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil), text.length > 0 else {
            return .failure(ConvertError(message: "This document has no content."))
        }

        let out = work.appendingPathComponent("out.pdf")
        var media = CGRect(x: 0, y: 0, width: options.paper.size.width, height: options.paper.size.height)
        guard let context = CGContext(out as CFURL, mediaBox: &media, nil) else {
            return .failure(ConvertError(message: "The PDF could not be created."))
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let margin: CGFloat = 54
        let frameRect = media.insetBy(dx: margin, dy: margin)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            location += visible.length
        } while location < text.length
        context.closePDF()
        return .success(out)
    }

    // MARK: Spreadsheets

    private func viaNativeSpreadsheet(_ input: URL, _ format: ConvertFormat, _ work: URL) -> Result<URL, ConvertError> {
        let sheets: [XLSXReader.Sheet]
        do { sheets = try XLSXReader.read(input) } catch {
            return .failure(ConvertError(message: "This workbook could not be read."))
        }
        let delimiter: Character = format.ext == "csv" ? "," : "\t"
        func write(_ sheet: XLSXReader.Sheet, to url: URL) -> Bool {
            let text = ConverterSupport.delimited(sheet.rows, delimiter: delimiter)
            return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
        if sheets.count == 1 {
            let out = work.appendingPathComponent("out").appendingPathExtension(format.ext)
            return write(sheets[0], to: out) ? .success(out)
                : .failure(ConvertError(message: "The sheet could not be written."))
        }
        // One file per sheet, collected in a folder named after the workbook.
        let folder = work.appendingPathComponent("sheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var used = Set<String>()
        for sheet in sheets {
            let safe = sheet.name.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
            var name = safe.isEmpty ? "Sheet" : safe
            var n = 2
            while !used.insert(name.lowercased()).inserted { name = "\(safe) \(n)"; n += 1 }
            let file = folder.appendingPathComponent(name).appendingPathExtension(format.ext)
            guard write(sheet, to: file) else {
                return .failure(ConvertError(message: "Sheet \"\(sheet.name)\" could not be written."))
            }
        }
        return .success(folder)
    }

    private func viaLibreOffice(_ input: URL, _ format: ConvertFormat, _ work: URL,
                                filter: String? = nil, infilter: String? = nil) -> Result<URL, ConvertError> {
        guard let soffice = Self.libreOfficePath else {
            return .failure(ConvertError(message: "LibreOffice is not installed (brew install --cask libreoffice)."))
        }
        // A fallback attempt may follow a failed one, so start from a clean folder.
        let outDir = work.appendingPathComponent("lo-out", isDirectory: true)
        let profile = work.appendingPathComponent("lo-profile", isDirectory: true)
        try? FileManager.default.removeItem(at: outDir)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var args = ["--headless", "--norestore", "--nolockcheck",
                    "-env:UserInstallation=\(profile.absoluteString)"]
        if let infilter { args.append("--infilter=\(infilter)") }
        args += ["--convert-to", filter ?? ConverterSupport.libreOfficeFilter(for: format.ext),
                 "--outdir", outDir.path, input.path]
        let result = run(soffice, args, timeout: 900)
        let files = ((try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else {
            let detail = Self.lastLine(result.stderr)
            return .failure(ConvertError(message: result.status == 0 ? "LibreOffice produced no output." : detail))
        }
        if files.count == 1 {
            let out = work.appendingPathComponent("out").appendingPathExtension(format.ext)
            do { try FileManager.default.moveItem(at: files[0], to: out) } catch {
                return .failure(ConvertError(message: "The result could not be collected."))
            }
            return .success(out)
        }
        // Multi-sheet CSV exports come back as one file per sheet.
        return .success(outDir)
    }
}

private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        // Keep the tail: the last lines are where tools report the cause.
        data.append(chunk)
        if data.count > limit { data = data.suffix(limit) }
    }

    func string() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

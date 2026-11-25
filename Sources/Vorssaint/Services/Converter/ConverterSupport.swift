// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a file is, decided from its extension. The kind picks which target
/// formats the converter offers.
enum ConvertKind: String, CaseIterable {
    case audio, video, image, document, pdf, spreadsheet

    static let extensions: [ConvertKind: Set<String>] = [
        .audio: ["mp3", "wav", "opus", "flac", "m4a", "aac", "ogg", "oga", "wma", "aiff", "aif",
                 "ac3", "mp2", "amr", "caf"],
        .video: ["mp4", "mov", "mkv", "webm", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "mts",
                 "m2ts", "3gp"],
        .image: ["heic", "heif", "jpg", "jpeg", "png", "webp", "tif", "tiff", "gif", "bmp", "svg",
                 "avif", "dng", "cr2", "nef", "arw"],
        .document: ["docx", "doc", "odt", "rtf", "html", "htm", "txt", "md", "markdown"],
        .pdf: ["pdf"],
        .spreadsheet: ["xlsx", "xlsm", "xls", "ods", "csv", "tsv"],
    ]

    static func kind(forExtension ext: String) -> ConvertKind? {
        let lower = ext.lowercased()
        return allCases.first { extensions[$0]?.contains(lower) == true }
    }

    static func kind(of url: URL) -> ConvertKind? {
        kind(forExtension: url.pathExtension)
    }

    var symbolName: String {
        switch self {
        case .audio: return "waveform"
        case .video: return "film"
        case .image: return "photo"
        case .document: return "doc.text"
        case .pdf: return "doc.richtext"
        case .spreadsheet: return "tablecells"
        }
    }

    var title: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        case .image: return "Images"
        case .document: return "Documents"
        case .pdf: return "PDF"
        case .spreadsheet: return "Spreadsheets"
        }
    }
}

/// The program that produces a target format. Native engines need nothing
/// installed; the rest name the tool they shell out to.
enum ConvertEngine: Equatable {
    case ffmpeg
    case imageIO
    case cwebp
    case textutil
    case pdfKit
    case appKitPDF
    case nativeSpreadsheet
    case libreOffice
}

struct ConvertFormat: Hashable, Identifiable {
    let id: String
    let label: String
    let ext: String
    let kind: ConvertKind
    let engine: ConvertEngine

    static func == (lhs: ConvertFormat, rhs: ConvertFormat) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ConvertFormats {
    private static func f(_ id: String, _ label: String, _ ext: String, _ kind: ConvertKind,
                          _ engine: ConvertEngine) -> ConvertFormat {
        ConvertFormat(id: id, label: label, ext: ext, kind: kind, engine: engine)
    }

    static let audio: [ConvertFormat] = [
        f("mp3", "MP3", "mp3", .audio, .ffmpeg),
        f("m4a", "M4A (AAC)", "m4a", .audio, .ffmpeg),
        f("wav", "WAV", "wav", .audio, .ffmpeg),
        f("aiff", "AIFF", "aiff", .audio, .ffmpeg),
        f("flac", "FLAC", "flac", .audio, .ffmpeg),
        f("alac", "ALAC (M4A)", "m4a", .audio, .ffmpeg),
        f("opus", "Opus", "opus", .audio, .ffmpeg),
        f("ogg", "OGG Vorbis", "ogg", .audio, .ffmpeg),
        f("wma", "WMA", "wma", .audio, .ffmpeg),
        f("ac3", "AC3", "ac3", .audio, .ffmpeg),
        f("mp2", "MP2", "mp2", .audio, .ffmpeg),
    ]

    static let video: [ConvertFormat] = [
        f("mp4-h264", "MP4 (H.264)", "mp4", .video, .ffmpeg),
        f("mp4-hevc", "MP4 (HEVC)", "mp4", .video, .ffmpeg),
        f("mov", "MOV", "mov", .video, .ffmpeg),
        f("webm", "WebM (VP9)", "webm", .video, .ffmpeg),
        f("mkv", "MKV", "mkv", .video, .ffmpeg),
        f("gif", "Animated GIF", "gif", .video, .ffmpeg),
    ]

    /// Video can also be reduced to its soundtrack.
    static let videoAudio: [ConvertFormat] = audio.filter { ["mp3", "m4a", "wav", "flac", "opus"].contains($0.id) }

    static let image: [ConvertFormat] = [
        f("img-jpg", "JPEG", "jpg", .image, .imageIO),
        f("img-png", "PNG", "png", .image, .imageIO),
        f("img-heic", "HEIC", "heic", .image, .imageIO),
        f("img-webp", "WebP", "webp", .image, .cwebp),
        f("img-tiff", "TIFF", "tiff", .image, .imageIO),
        f("img-gif", "GIF", "gif", .image, .imageIO),
        f("img-bmp", "BMP", "bmp", .image, .imageIO),
        f("img-pdf", "PDF", "pdf", .image, .pdfKit),
    ]

    static let document: [ConvertFormat] = [
        f("doc-pdf", "PDF", "pdf", .document, .appKitPDF),
        f("doc-docx", "Word (DOCX)", "docx", .document, .textutil),
        f("doc-doc", "Word (DOC)", "doc", .document, .textutil),
        f("doc-odt", "ODT", "odt", .document, .textutil),
        f("doc-rtf", "RTF", "rtf", .document, .textutil),
        f("doc-txt", "Plain text", "txt", .document, .textutil),
        f("doc-html", "HTML", "html", .document, .textutil),
    ]

    static let pdf: [ConvertFormat] = [
        f("pdf-png", "PNG (one per page)", "png", .pdf, .pdfKit),
        f("pdf-jpg", "JPEG (one per page)", "jpg", .pdf, .pdfKit),
        f("pdf-txt", "Plain text", "txt", .pdf, .pdfKit),
        f("pdf-docx", "Word (DOCX)", "docx", .pdf, .textutil),
        f("pdf-odt", "ODT", "odt", .pdf, .textutil),
        f("pdf-rtf", "RTF", "rtf", .pdf, .textutil),
    ]

    static let spreadsheet: [ConvertFormat] = [
        f("sheet-csv", "CSV", "csv", .spreadsheet, .nativeSpreadsheet),
        f("sheet-tsv", "TSV", "tsv", .spreadsheet, .nativeSpreadsheet),
        f("sheet-txt", "Plain text", "txt", .spreadsheet, .nativeSpreadsheet),
        f("sheet-xlsx", "Excel (XLSX)", "xlsx", .spreadsheet, .libreOffice),
        f("sheet-xls", "Excel 97-2003 (XLS)", "xls", .spreadsheet, .libreOffice),
        f("sheet-ods", "OpenDocument (ODS)", "ods", .spreadsheet, .libreOffice),
        f("sheet-pdf", "PDF", "pdf", .spreadsheet, .libreOffice),
        f("sheet-html", "HTML", "html", .spreadsheet, .libreOffice),
    ]

    static var all: [ConvertFormat] { audio + video + image + document + pdf + spreadsheet }

    /// Document formats textutil can read, i.e. the ones that can sit on the
    /// left of a text conversion.
    static let xlsxFamily: Set<String> = ["xlsx", "xlsm"]

    /// Formats offered for a file with this extension. Same-format targets are
    /// dropped. Spreadsheet text exports from anything other than XLSX go
    /// through LibreOffice, so they are only offered when it is installed.
    static func targets(forExtension ext: String, libreOfficeAvailable: Bool) -> [ConvertFormat] {
        let lower = ext.lowercased()
        guard let kind = ConvertKind.kind(forExtension: lower) else { return [] }
        var list: [ConvertFormat]
        switch kind {
        case .audio: list = audio
        case .video: list = video + videoAudio
        case .image: list = image
        case .document: list = document
        case .pdf: list = pdf
        case .spreadsheet:
            list = spreadsheet.filter { format in
                switch format.engine {
                case .nativeSpreadsheet:
                    // Native parsing covers XLSX only; everything else needs LibreOffice.
                    return xlsxFamily.contains(lower) || libreOfficeAvailable
                default:
                    return libreOfficeAvailable
                }
            }
            if lower == "csv" || lower == "tsv" {
                list.removeAll { $0.engine == .nativeSpreadsheet }
            }
        }
        let same = lower == "jpeg" ? "jpg" : (lower == "tif" ? "tiff" : lower)
        return list.filter { $0.ext != same }
    }

    /// Targets every file of a batch can be turned into. A mixed batch keeps
    /// only the formats offered for all of them (video and audio mix freely,
    /// as the video list already includes the audio formats).
    static func commonTargets(for urls: [URL], libreOfficeAvailable: Bool) -> [ConvertFormat] {
        var common: [ConvertFormat]?
        for url in urls {
            let targets = targets(forExtension: url.pathExtension, libreOfficeAvailable: libreOfficeAvailable)
            if let existing = common {
                common = existing.filter { targets.contains($0) }
            } else {
                common = targets
            }
        }
        return common ?? []
    }
}

enum ConvertQuality: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var imageQuality: Double {
        switch self {
        case .low: return 0.55
        case .medium: return 0.8
        case .high: return 0.95
        }
    }

    /// x264/x265 CRF; lower is better.
    var crf: Int {
        switch self {
        case .low: return 30
        case .medium: return 23
        case .high: return 18
        }
    }

    var audioKbps: Int {
        switch self {
        case .low: return 128
        case .medium: return 192
        case .high: return 320
        }
    }
}

enum ConvertPaper: String, CaseIterable, Identifiable {
    case a4, letter
    var id: String { rawValue }
    var label: String { self == .a4 ? "A4" : "US Letter" }
    var size: (width: Double, height: Double) {
        self == .a4 ? (595.28, 841.89) : (612, 792)
    }
}

struct ConvertOptions: Equatable {
    var quality: ConvertQuality = .high
    var paper: ConvertPaper = .a4
    var trashOriginals = false
}

enum ConverterSupport {
    /// "name.ext", then "name 2.ext", "name 3.ext" … the first that does not
    /// exist. `exists` is injectable for tests.
    static func uniqueURL(directory: URL, baseName: String, ext: String,
                          exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        func make(_ n: Int) -> URL {
            let name = n == 1 ? baseName : "\(baseName) \(n)"
            return ext.isEmpty
                ? directory.appendingPathComponent(name, isDirectory: true)
                : directory.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var n = 1
        while exists(make(n)) { n += 1 }
        return make(n)
    }

    /// ffmpeg arguments (after the input) for each target, tried in order: the
    /// first that exits cleanly wins, so hardware encoders can back up
    /// software ones that a given ffmpeg build lacks (or the reverse).
    static func ffmpegVariants(for formatID: String, quality: ConvertQuality) -> [[String]] {
        let kbps = "\(quality.audioKbps)k"
        let crf = String(quality.crf)
        switch formatID {
        case "mp3": return [["-vn", "-c:a", "libmp3lame", "-b:a", kbps]]
        case "m4a": return [["-vn", "-c:a", "aac", "-b:a", kbps]]
        case "wav": return [["-vn", "-c:a", "pcm_s16le"]]
        case "aiff": return [["-vn", "-c:a", "pcm_s16be", "-f", "aiff"]]
        case "flac": return [["-vn", "-c:a", "flac"]]
        case "alac": return [["-vn", "-c:a", "alac", "-f", "ipod"]]
        case "opus": return [["-vn", "-c:a", "libopus", "-b:a", kbps]]
        case "ogg": return [["-vn", "-c:a", "libvorbis", "-b:a", kbps]]
        case "wma": return [["-vn", "-c:a", "wmav2", "-b:a", kbps]]
        case "ac3": return [["-vn", "-c:a", "ac3", "-b:a", kbps]]
        case "mp2": return [["-vn", "-c:a", "mp2", "-b:a", kbps]]
        case "mp4-h264":
            return [["-c:v", "libx264", "-crf", crf, "-preset", "medium", "-pix_fmt", "yuv420p",
                     "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"],
                    ["-c:v", "h264_videotoolbox", "-q:v", String(max(30, 100 - quality.crf * 2)),
                     "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]]
        case "mp4-hevc":
            return [["-c:v", "libx265", "-crf", String(quality.crf + 5), "-preset", "medium",
                     "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-c:a", "aac", "-b:a", "192k",
                     "-movflags", "+faststart"],
                    ["-c:v", "hevc_videotoolbox", "-q:v", String(max(30, 100 - quality.crf * 2)),
                     "-tag:v", "hvc1", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]]
        case "mov":
            return [["-c:v", "libx264", "-crf", crf, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"],
                    ["-c:v", "h264_videotoolbox", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]]
        case "webm":
            return [["-c:v", "libvpx-vp9", "-crf", String(quality.crf + 4), "-b:v", "0",
                     "-c:a", "libopus", "-b:a", "128k"]]
        case "mkv":
            return [["-c:v", "libx264", "-crf", crf, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"],
                    ["-c", "copy"]]
        case "gif":
            return [["-an", "-vf",
                     "fps=12,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"]]
        default: return []
        }
    }

    /// LibreOffice `--convert-to` filter for a spreadsheet target.
    static func libreOfficeFilter(for ext: String) -> String {
        switch ext {
        case "csv": return "csv:Text - txt - csv (StarCalc):44,34,76,1,,0,false,true,false,false,false,-1"
        case "tsv", "txt": return "csv:Text - txt - csv (StarCalc):9,34,76,1,,0,false,true,false,false,false,-1"
        case "pdf": return "pdf:calc_pdf_Export"
        case "html": return "html:HTML (StarCalc)"
        default: return ext
        }
    }

    // MARK: CSV

    static func csvField(_ value: String, delimiter: Character) -> String {
        let needsQuotes = value.contains(delimiter) || value.contains("\"")
            || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func delimited(_ rows: [[String]], delimiter: Character) -> String {
        rows.map { $0.map { csvField($0, delimiter: delimiter) }.joined(separator: String(delimiter)) }
            .joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
    }

    /// "B" -> 1, "AA" -> 26 (zero-based column index from a cell reference).
    static func columnIndex(fromReference ref: String) -> Int {
        var index = 0
        for scalar in ref.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90
                || (scalar.value >= 97 && scalar.value <= 122) else { break }
            index = index * 26 + Int((scalar.value & ~0x20) - 64)
        }
        return max(0, index - 1)
    }

    /// Excel serial date (1900 system) as ISO text; nil when out of range.
    static func isoString(fromExcelSerial serial: Double, uses1904: Bool = false) -> String? {
        guard serial.isFinite, serial >= 0, serial < 2_958_466 else { return nil }
        // 1899-12-30 absorbs Excel's phantom 1900-02-29 for every date after
        // it; the 1904 system starts four years (1462 days) later.
        let epochOffset = uses1904 ? 1462.0 : 0
        let days = floor(serial)
        let seconds = ((serial - days) * 86_400).rounded()
        let reference = Date(timeIntervalSince1970: -2_209_161_600) // 1899-12-30 UTC
        let date = reference.addingTimeInterval((days + epochOffset) * 86_400 + seconds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let datePart = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        if serial < 1 { return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0) }
        if seconds == 0 { return datePart }
        return datePart + String(format: " %02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Built-in Excel number formats that are dates or times.
    static let builtInDateFormatIDs: Set<Int> = Set(14...22).union(45...47)

    static func isDateFormatCode(_ code: String) -> Bool {
        // Strip quoted literals and escaped characters, then look for date tokens.
        var cleaned = ""
        var inQuote = false
        var skip = false
        for ch in code {
            if skip { skip = false; continue }
            if ch == "\\" || ch == "_" { skip = true; continue }
            if ch == "\"" { inQuote.toggle(); continue }
            if !inQuote { cleaned.append(ch) }
        }
        cleaned = cleaned.lowercased()
        // Drop [Red]-style colour/condition blocks, keep [h]/[mm]/[ss] elapsed tokens.
        var result = ""
        var inBracket = false
        var bracket = ""
        for ch in cleaned {
            if ch == "[" { inBracket = true; bracket = ""; continue }
            if ch == "]" {
                inBracket = false
                if ["h", "hh", "m", "mm", "s", "ss"].contains(bracket) { result += bracket }
                continue
            }
            if inBracket { bracket.append(ch) } else { result.append(ch) }
        }
        return result.contains { "ymdhs".contains($0) }
    }
}

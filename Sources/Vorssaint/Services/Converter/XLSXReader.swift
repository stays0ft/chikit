// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the cell values of an .xlsx/.xlsm workbook without Excel or
/// LibreOffice: the file is a zip of XML parts, which /usr/bin/unzip streams
/// out and XMLParser walks. Formulas are exported as their cached results,
/// dates as ISO text, everything else as the stored text.
enum XLSXReader {
    struct Sheet {
        let name: String
        let rows: [[String]]
    }

    enum ReadError: Error { case unreadable, noSheets }

    static func isXLSX(_ url: URL) -> Bool {
        ConvertFormats.xlsxFamily.contains(url.pathExtension.lowercased())
    }

    static func read(_ url: URL) throws -> [Sheet] {
        guard let workbook = part("xl/workbook.xml", in: url) else { throw ReadError.unreadable }
        let book = WorkbookParser.parse(workbook)
        guard !book.sheets.isEmpty else { throw ReadError.noSheets }

        let rels = part("xl/_rels/workbook.xml.rels", in: url).map(RelationshipParser.parse) ?? [:]
        let strings = part("xl/sharedStrings.xml", in: url).map(SharedStringParser.parse) ?? []
        let dateStyles = part("xl/styles.xml", in: url).map(StyleParser.parse) ?? []

        var sheets: [Sheet] = []
        for (index, entry) in book.sheets.enumerated() {
            var target = rels[entry.relID] ?? "worksheets/sheet\(index + 1).xml"
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            guard let data = part(target, in: url) else { continue }
            let rows = SheetParser.parse(data, strings: strings, dateStyles: dateStyles,
                                         uses1904: book.uses1904)
            sheets.append(Sheet(name: entry.name, rows: rows))
        }
        guard !sheets.isEmpty else { throw ReadError.noSheets }
        return sheets
    }

    private static func part(_ path: String, in url: URL) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    // MARK: Parsers

    private final class WorkbookParser: NSObject, XMLParserDelegate {
        var sheets: [(name: String, relID: String)] = []
        var uses1904 = false

        static func parse(_ data: Data) -> (sheets: [(name: String, relID: String)], uses1904: Bool) {
            let delegate = WorkbookParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return (delegate.sheets, delegate.uses1904)
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "sheet" {
                sheets.append((attributes["name"] ?? "Sheet\(sheets.count + 1)",
                               attributes["r:id"] ?? ""))
            } else if name == "workbookPr" {
                uses1904 = attributes["date1904"] == "1" || attributes["date1904"] == "true"
            }
        }
    }

    private final class RelationshipParser: NSObject, XMLParserDelegate {
        var map: [String: String] = [:]

        static func parse(_ data: Data) -> [String: String] {
            let delegate = RelationshipParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return delegate.map
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
                map[id] = target
            }
        }
    }

    private final class SharedStringParser: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = ""
        private var inT = false
        private var phoneticDepth = 0

        static func parse(_ data: Data) -> [String] {
            let delegate = SharedStringParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return delegate.strings
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "si": current = ""
            case "rPh": phoneticDepth += 1
            case "t": inT = phoneticDepth == 0
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inT { current += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            switch name {
            case "t": inT = false
            case "rPh": phoneticDepth = max(0, phoneticDepth - 1)
            case "si": strings.append(current)
            default: break
            }
        }
    }

    /// Whether each cell style (by its index in `cellXfs`) formats dates.
    private final class StyleParser: NSObject, XMLParserDelegate {
        private var customCodes: [Int: String] = [:]
        private var isDate: [Bool] = []
        private var inCellXfs = false

        static func parse(_ data: Data) -> [Bool] {
            let delegate = StyleParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return delegate.isDate
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "numFmt":
                if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"] {
                    customCodes[id] = code
                }
            case "cellXfs": inCellXfs = true
            case "xf" where inCellXfs:
                let id = attributes["numFmtId"].flatMap(Int.init) ?? 0
                if let code = customCodes[id] {
                    isDate.append(ConverterSupport.isDateFormatCode(code))
                } else {
                    isDate.append(ConverterSupport.builtInDateFormatIDs.contains(id))
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if name == "cellXfs" { inCellXfs = false }
        }
    }

    private final class SheetParser: NSObject, XMLParserDelegate {
        private let strings: [String]
        private let dateStyles: [Bool]
        private let uses1904: Bool
        private var rows: [[String]] = []
        private var row: [String] = []
        private var rowIndex = 0
        private var cellColumn = 0
        private var cellType = ""
        private var cellStyle = 0
        private var text = ""
        private var capture = false
        private var inInline = false

        init(strings: [String], dateStyles: [Bool], uses1904: Bool) {
            self.strings = strings
            self.dateStyles = dateStyles
            self.uses1904 = uses1904
        }

        static func parse(_ data: Data, strings: [String], dateStyles: [Bool], uses1904: Bool) -> [[String]] {
            let delegate = SheetParser(strings: strings, dateStyles: dateStyles, uses1904: uses1904)
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            // Trailing blank rows add nothing.
            while let last = delegate.rows.last, last.allSatisfy(\.isEmpty) { delegate.rows.removeLast() }
            return delegate.rows
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "row":
                row = []
                if let r = attributes["r"].flatMap(Int.init), r - 1 > rowIndex {
                    // Preserve skipped rows so row positions survive.
                    for _ in rowIndex..<(r - 1) { rows.append([]) }
                    rowIndex = r - 1
                }
            case "c":
                cellColumn = ConverterSupport.columnIndex(fromReference: attributes["r"] ?? "")
                if attributes["r"] == nil { cellColumn = row.count }
                cellType = attributes["t"] ?? "n"
                cellStyle = attributes["s"].flatMap(Int.init) ?? 0
                text = ""
            case "v": capture = true; text = ""
            case "is": inInline = true; text = ""
            case "t" where inInline: capture = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capture { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            switch name {
            case "v", "t": capture = false
            case "is": inInline = false
            case "c":
                while row.count < cellColumn { row.append("") }
                let value = resolved()
                if row.count == cellColumn { row.append(value) } else if cellColumn < row.count { row[cellColumn] = value }
            case "row":
                rows.append(row)
                rowIndex += 1
            default: break
            }
        }

        private func resolved() -> String {
            switch cellType {
            case "s":
                guard let i = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                      strings.indices.contains(i) else { return "" }
                return strings[i]
            case "b": return text == "1" ? "TRUE" : "FALSE"
            case "inlineStr", "str", "e": return text
            default:
                guard !text.isEmpty else { return "" }
                if cellStyle < dateStyles.count, dateStyles[cellStyle], let number = Double(text),
                   let iso = ConverterSupport.isoString(fromExcelSerial: number, uses1904: uses1904) {
                    return iso
                }
                return text
            }
        }
    }
}

import Foundation
import HushCore

/// Writes the notes as a Word document (notities.docx) next to notities.md.
/// Built by hand because NSAttributedString's Word export drops tables.
enum DocxExporter {
    /// The Word file for a recording, created from the notes if it does not exist yet (older recordings).
    static func ensureDocument(for recording: Recording) -> URL? {
        let url = recording.notesDocxURL
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let markdown = try? String(contentsOf: recording.notesURL, encoding: .utf8) else { return nil }
        return (try? write(markdown: markdown, to: url)) == nil ? nil : url
    }

    static func write(markdown: String, to url: URL) throws {
        let files: [(String, String)] = [
            ("[Content_Types].xml", contentTypes),
            ("_rels/.rels", rootRels),
            ("word/_rels/document.xml.rels", documentRels),
            ("word/styles.xml", styles),
            ("word/document.xml", document(markdown)),
        ]
        try Zip.stored(files.map { ($0.0, Data($0.1.utf8)) }).write(to: url, options: .atomic)
    }

    // MARK: Markdown to WordprocessingML

    /// Headings, bullets, tables, paragraphs and **bold**, enough for the notes Claude and ChatGPT write.
    static func document(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var body = ""
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1
            if line.isEmpty { continue }
            if MarkdownTable.isRow(line) {
                var rows = [line]
                while i < lines.count, MarkdownTable.isRow(lines[i]) {
                    rows.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1
                }
                body += table(rows)
                continue
            }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if hashes > 0, line.dropFirst(hashes).hasPrefix(" ") {
                let size = hashes == 1 ? 36 : hashes == 2 ? 28 : 24
                body += paragraph(String(line.dropFirst(hashes + 1)), size: size, bold: true, spaceBefore: 240)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                body += paragraph("•\t" + String(line.dropFirst(2)), indent: 360, hanging: 360)
            } else {
                body += paragraph(line)
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)\
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>\
        </w:body></w:document>
        """
    }

    private static func paragraph(_ text: String, size: Int = 22, bold: Bool = false, spaceBefore: Int = 0,
                                  indent: Int = 0, hanging: Int = 0) -> String {
        var props = "<w:spacing w:before=\"\(spaceBefore)\" w:after=\"120\"/>"
        if indent > 0 { props += "<w:ind w:left=\"\(indent)\" w:hanging=\"\(hanging)\"/>" }
        return "<w:p><w:pPr>\(props)</w:pPr>\(runs(text, size: size, bold: bold))</w:p>"
    }

    /// `**bold**` toggles bold; a tab in the text becomes a Word tab.
    private static func runs(_ text: String, size: Int, bold: Bool) -> String {
        var result = ""
        for (i, part) in text.components(separatedBy: "**").enumerated() where !part.isEmpty {
            let isBold = bold || i % 2 == 1
            let props = "<w:rPr>\(isBold ? "<w:b/>" : "")<w:sz w:val=\"\(size)\"/></w:rPr>"
            let pieces = part.components(separatedBy: "\t")
            let inner = pieces.map { "<w:t xml:space=\"preserve\">\(escape($0))</w:t>" }.joined(separator: "<w:tab/>")
            result += "<w:r>\(props)\(inner)</w:r>"
        }
        return result
    }

    /// A Markdown table (`| a | b |` rows, with a `|---|---|` divider after the header) as a real Word table.
    private static func table(_ rows: [String]) -> String {
        let data = MarkdownTable.parse(rows)
        let columns = data.map(\.count).max() ?? 0
        guard columns > 0 else { return "" }
        let width = 9026 / columns
        let border = ["top", "left", "bottom", "right", "insideH", "insideV"]
            .map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"999999\"/>" }.joined()
        var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"9026\" w:type=\"dxa\"/><w:tblBorders>\(border)</w:tblBorders>"
            + "<w:tblCellMar><w:top w:w=\"60\" w:type=\"dxa\"/><w:left w:w=\"100\" w:type=\"dxa\"/><w:bottom w:w=\"60\" w:type=\"dxa\"/><w:right w:w=\"100\" w:type=\"dxa\"/></w:tblCellMar>"
            + "</w:tblPr><w:tblGrid>" + String(repeating: "<w:gridCol w:w=\"\(width)\"/>", count: columns) + "</w:tblGrid>"
        for (r, row) in data.enumerated() {
            xml += r == 0 ? "<w:tr><w:trPr><w:tblHeader/></w:trPr>" : "<w:tr>"
            for c in 0..<columns {
                let shade = r == 0 ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"E7E7E7\"/>" : ""
                let text = c < row.count ? row[c] : ""
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>\(shade)</w:tcPr>"
                    + "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\"/></w:pPr>\(runs(text, size: 21, bold: r == 0))</w:p></w:tc>"
            }
            xml += "</w:tr>"
        }
        // Word needs a paragraph after a table.
        return xml + "</w:tbl><w:p/>"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Fixed parts

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
    """
    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """
    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:lang w:val="nl-NL"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>
    """
}

/// Minimal zip writer (stored, no compression), enough for a .docx.
enum Zip {
    static func stored(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for file in files {
            let name = Data(file.name.utf8)
            let crc = crc32(file.data)
            let offset = UInt32(out.count)
            out += le32(0x04034b50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            out += le32(crc) + le32(UInt32(file.data.count)) + le32(UInt32(file.data.count))
            out += le16(UInt16(name.count)) + le16(0) + name + file.data
            central += le32(0x02014b50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            central += le32(crc) + le32(UInt32(file.data.count)) + le32(UInt32(file.data.count))
            central += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let start = UInt32(out.count)
        out += central
        out += le32(0x06054b50) + le16(0) + le16(0) + le16(UInt16(files.count)) + le16(UInt16(files.count))
        out += le32(UInt32(central.count)) + le32(start) + le16(0)
        return out
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(UInt32.max) { crcTable[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}

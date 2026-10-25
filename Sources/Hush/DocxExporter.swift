import AppKit
import HushCore

/// Writes the notes as a Word document (notities.docx) next to notities.md.
enum DocxExporter {
    static func write(markdown: String, to url: URL) throws {
        let text = attributed(markdown)
        let data = try text.data(from: NSRange(location: 0, length: text.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        try data.write(to: url, options: .atomic)
    }

    /// The Word file for a recording, created from the notes if it does not exist yet (older recordings).
    static func ensureDocument(for recording: Recording) -> URL? {
        let url = recording.notesDocxURL
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let markdown = try? String(contentsOf: recording.notesURL, encoding: .utf8) else { return nil }
        return (try? write(markdown: markdown, to: url)) == nil ? nil : url
    }

    /// Headings, bullets, numbered lines, paragraphs and **bold**, enough for the notes Claude and ChatGPT write.
    static func attributed(_ markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 11)
        for raw in markdown.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            var font = body
            var prefix = ""
            if line.isEmpty { out.append(NSAttributedString(string: "\n", attributes: [.font: body])); continue }
            if let hashes = line.prefix(while: { $0 == "#" }) as Substring?, !hashes.isEmpty, line.dropFirst(hashes.count).hasPrefix(" ") {
                line = String(line.dropFirst(hashes.count + 1))
                font = .boldSystemFont(ofSize: hashes.count == 1 ? 18 : hashes.count == 2 ? 14 : 12)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = String(line.dropFirst(2)); prefix = "•  "
            }
            out.append(NSAttributedString(string: prefix, attributes: [.font: font]))
            out.append(inline(line, font: font))
            out.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        }
        return out
    }

    private static func inline(_ s: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bold = NSFont.boldSystemFont(ofSize: font.pointSize)
        for (i, part) in s.components(separatedBy: "**").enumerated() where !part.isEmpty {
            result.append(NSAttributedString(string: part, attributes: [.font: i % 2 == 1 ? bold : font]))
        }
        return result
    }
}

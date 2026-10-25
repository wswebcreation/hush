import Foundation

/// Markdown pipe tables (`| a | b |`, divider row `|---|---|`), shared by the notes view and the Word export.
public enum MarkdownTable {
    public static func isRow(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }

    /// Rows of trimmed cells, without the divider row.
    public static func parse(_ lines: [String]) -> [[String]] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.allSatisfy { "|-: ".contains($0) } }
            .map { row in
                var cells = row.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
                return cells
            }
    }
}

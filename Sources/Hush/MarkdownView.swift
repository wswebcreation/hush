import SwiftUI

/// Minimal block Markdown renderer: headings, bullets, numbered and checklist items, paragraphs, **bold**.
struct MarkdownView: View {
    let text: String

    private enum Block: Identifiable {
        case heading(Int, String), bullet(String, Int), numbered(String, String), paragraph(String), spacer
        var id: UUID { UUID() }
    }

    private var blocks: [Block] {
        text.components(separatedBy: "\n").map { raw in
            let line = raw.trimmingCharacters(in: .init(charactersIn: "\r"))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .spacer }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                return .heading(hashes, trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
            }
            let indent = line.prefix { $0 == " " }.count / 2
            if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
                return .bullet(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces), indent)
            }
            let digits = trimmed.prefix { $0.isNumber }
            let rest = trimmed.dropFirst(digits.count)
            if !digits.isEmpty, let sep = rest.first, ".)".contains(sep), rest.dropFirst().first == " " {
                return .numbered(String(digits), rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
            return .paragraph(trimmed)
        }
    }

    private func inline(_ s: String) -> Text {
        let attributed = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        return Text(attributed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                switch block {
                case .heading(let level, let t):
                    inline(t).font(.system(size: level <= 1 ? 15 : 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .padding(.top, 8).accessibilityAddTraits(.isHeader)
                case .bullet(let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.textSecondary)
                        inline(t).foregroundStyle(Theme.textPrimary)
                    }.padding(.leading, CGFloat(indent) * 16)
                case .numbered(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(Theme.textSecondary)
                        inline(t).foregroundStyle(Theme.textPrimary)
                    }
                case .paragraph(let t): inline(t).foregroundStyle(Theme.textPrimary)
                case .spacer: Color.clear.frame(height: 2)
                }
            }
        }
        .font(Theme.body)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

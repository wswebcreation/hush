import SwiftUI
import HushCore

/// Callout under the menu bar icon: a bouncing arrow and one line on how to start.
struct MenuBarHintView: View {
    let shortcut: String
    /// Horizontal distance from the middle of the callout to the icon it points at.
    let caretOffset: CGFloat
    static let width: CGFloat = 280

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        VStack(spacing: 0) {
            Triangle().fill(Theme.surfaceRaised).frame(width: 18, height: 9)
                .overlay(Triangle().stroke(Theme.border, lineWidth: 1))
                .offset(x: caretOffset, y: reduceMotion ? 0 : (up ? -4 : 2))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
                    .offset(y: reduceMotion ? 0 : (up ? -3 : 3))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.hintTitle).font(Theme.bodySemibold).foregroundStyle(Theme.textPrimary)
                    Text(L10n.hintBody(shortcut)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(width: Self.width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        }
        .padding(.bottom, 6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { up = true }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

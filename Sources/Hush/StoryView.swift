import SwiftUI
import HushCore

/// Logo as a small speaker equaliser: the bars move while text is typed and settle to a quiet line.
struct SpeakerLogo: View {
    var activity: Double
    var time: TimeInterval
    private let phases: [Double] = [0.0, 1.3, 2.4, 0.7, 1.9]
    private let speeds: [Double] = [7.0, 9.5, 6.0, 8.5, 7.5]

    var body: some View {
        RoundedRectangle(cornerRadius: 18).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
            .overlay(
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        let wave = abs(sin(time * speeds[i] + phases[i]))
                        Capsule().fill(Theme.accent).frame(width: 5, height: 4 + 34 * wave * activity)
                    }
                }
            )
            .frame(width: 80, height: 80)
            .accessibilityHidden(true)
    }
}

/// Explains the name Hush by typing the story out, with the logo reacting to the typing.
struct StoryView: View {
    let buttonTitle: String
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var skipped = false

    private let writer = Typewriter(segments: [
        L10n.storyTitle, L10n.storyIntro,
        L10n.storyBackgroundTitle, L10n.storyBackgroundBody,
        L10n.storyOthersTitle, L10n.storyOthersBody,
        L10n.storyPrivateTitle, L10n.storyPrivateBody,
        L10n.storyConsent,
    ])

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(paused: reduceMotion || skipped)) { context in
                let t = reduceMotion || skipped ? writer.duration : context.date.timeIntervalSince(started)
                let frame = writer.frame(at: t)
                content(frame: frame, time: t)
            }
            FlowFooter {
                if !(reduceMotion || skipped) {
                    Button(L10n.storySkip) { skipped = true }.buttonStyle(SecondaryButtonStyle())
                }
            } trailing: {
                Button(buttonTitle, action: onFinish).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560, height: 600)
        .background(Theme.background)
        .onAppear { started = Date() }
    }

    private func content(frame: Typewriter.Frame, time: TimeInterval) -> some View {
        let v = frame.visible
        return VStack(spacing: 24) {
            SpeakerLogo(activity: skipped || reduceMotion ? 0 : frame.activity, time: time)
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    typed(writer.segments[0], v[0], font: .system(size: 24, weight: .semibold), color: Theme.textPrimary)
                    typed(writer.segments[1], v[1], font: Theme.body, color: Theme.textSecondary)
                }
                block(2, v)
                block(4, v)
                block(6, v)
                typed(writer.segments[8], v[8], font: Theme.body, color: Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48).padding(.top, 8).padding(.bottom, 16)
        // VoiceOver reads the finished text at once instead of one letter at a time.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(writer.segments.joined(separator: " "))
    }

    private func block(_ i: Int, _ v: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            typed(writer.segments[i], v[i], font: Theme.bodySemibold, color: Theme.textPrimary)
            typed(writer.segments[i + 1], v[i + 1], font: Theme.body, color: Theme.textSecondary)
        }
    }

    /// The full text is laid out invisibly so the layout does not jump while typing.
    private func typed(_ full: String, _ shown: String, font: Font, color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            Text(full).font(font).hidden()
            Text(shown).font(font).foregroundStyle(color)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

import SwiftUI
import AppKit
import HushCore

struct FlowView: View {
    @ObservedObject var model: FlowModel

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(flow: model.flow)
            Group {
                switch model.flow.step {
                case .transcribe: model.flow.failed ? AnyView(TranscribeFailedStep(model: model)) : AnyView(TranscribeStep(model: model))
                case .review: ReviewStep(model: model).eraseToAnyView()
                case .notes: NotesChoiceStep(model: model).eraseToAnyView()
                case .generate: GenerateStep(model: model).eraseToAnyView()
                case .finish: FinishStep(model: model).eraseToAnyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
    }
}

extension View { func eraseToAnyView() -> AnyView { AnyView(self) } }

struct StepIndicator: View {
    let flow: PostRecordingFlow
    var body: some View {
        HStack(spacing: 8) {
            ForEach(FlowStep.allCases, id: \.rawValue) { step in
                let state = flow.state(of: step)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(barColor(state)).frame(height: 4)
                    HStack(spacing: 4) {
                        if state == .completed { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.success) }
                        if state == .failed { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Theme.warning) }
                        Text(step.label)
                            .font(.system(size: 11, weight: state == .current || state == .failed ? .semibold : .regular))
                            .foregroundStyle(labelColor(state))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.label), \(stateName(state))")
            }
        }
        .padding(16)
    }
    private func barColor(_ s: StepState) -> Color { s == .upcoming ? Theme.border : (s == .failed ? Theme.warning : Theme.accent) }
    private func labelColor(_ s: StepState) -> Color {
        switch s { case .current: Theme.textPrimary; case .failed: Theme.warning; default: Theme.textSecondary }
    }
    private func stateName(_ s: StepState) -> String {
        switch s { case .completed: "klaar"; case .current: "huidige stap"; case .upcoming: "nog te doen"; case .failed: "mislukt" }
    }
}

struct FlowFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            Divider1()
            HStack(spacing: 8) {
                leading
                Spacer(minLength: 8)
                trailing
            }
            .padding(16)
        }
    }
}

// MARK: 3.1

struct TranscribeStep: View {
    @ObservedObject var model: FlowModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(model.title).font(Theme.title).foregroundStyle(Theme.textPrimary)
                    Text(L10n.flowSources(model.app.format.duration(model.recording.meta.durationSeconds)))
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.flowTranscribing).font(Theme.body).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(Int(model.progress * 100))%").font(Theme.body.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.border)
                                Capsule().fill(Theme.accent).frame(width: geo.size.width * model.progress)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityElement()
                        .accessibilityLabel(L10n.flowTranscribing)
                        .accessibilityValue("\(Int(model.progress * 100)) procent")
                        if let left = model.secondsLeft {
                            Text(L10n.flowTimeLeft(model.app.format.remaining(left))).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                    Text(L10n.flowOnDevice)
                }
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 48)
            Spacer()
            FlowFooter {
                Text(L10n.flowCancelHint).font(Theme.secondary).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            } trailing: {
                Button(L10n.flowCancel) { model.cancelTranscription() }.buttonStyle(SecondaryButtonStyle())
                Button(L10n.flowBackground) { model.moveToBackground() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct TranscribeFailedStep: View {
    @ObservedObject var model: FlowModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(model.title).font(Theme.title).foregroundStyle(Theme.textPrimary)
                    Text(L10n.flowSources(model.app.format.duration(model.recording.meta.durationSeconds)))
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                WarningBanner(title: L10n.flowTranscribeFailed, detail: L10n.flowTranscribeFailedHint)
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(Theme.textSecondary)
                    Text(model.displayFolder + "/" + (FileManager.default.fileExists(atPath: model.recording.audioURL.path) ? "audio.m4a" : "mic.caf"))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 48)
            Spacer()
            FlowFooter { EmptyView() } trailing: {
                Button(L10n.flowClose) { model.app.windows.closeFlow(model.recording.id) }.buttonStyle(SecondaryButtonStyle())
                Button(L10n.flowRetry) { model.startTranscription() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: 3.2

struct TranscriptLines: View {
    let segments: [TranscriptSegment]
    let youName: String
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(DutchFormat.clock(s.start)).foregroundStyle(Theme.textSecondary).frame(width: 64, alignment: .leading)
                        Text(s.speaker.rawValue).fontWeight(.semibold)
                            .foregroundStyle(s.speaker == .you ? Theme.accent : Theme.textSecondary).frame(width: 56, alignment: .leading)
                        Text(s.text).foregroundStyle(Theme.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(Theme.transcript)
            .textSelection(.enabled)
            .padding(16)
        }
    }
}

struct ReviewStep: View {
    @ObservedObject var model: FlowModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.flowReviewTitle).font(Theme.title).foregroundStyle(Theme.textPrimary)
                    Text("\(model.title) · \(L10n.flowYouAndThem)").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(L10n.flowReadOnly).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
            TranscriptLines(segments: model.segments, youName: model.app.settings.userName)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 16)
            FlowFooter {
                Button { model.copyTranscript() } label: { Label(L10n.flowCopy, systemImage: "doc.on.doc") }.buttonStyle(SecondaryButtonStyle())
                Button { model.reveal() } label: { Label(L10n.flowReveal, systemImage: "folder") }.buttonStyle(SecondaryButtonStyle())
            } trailing: {
                Button(L10n.flowBack) { model.flow.back() }.buttonStyle(SecondaryButtonStyle())
                Button(L10n.flowNext) { model.flow.reviewDone() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: 3.3

struct NotesChoiceStep: View {
    @ObservedObject var model: FlowModel
    @State private var input = ""
    @State private var keyTick = 0

    private var isSkip: Bool { model.choice == .skip }
    private var selectedProvider: NotesProviderKind? { if case .provider(let p) = model.choice { p } else { nil } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.flowNotesTitle).font(Theme.title).foregroundStyle(Theme.textPrimary)
                    Text("\(model.title) · \(model.app.format.duration(model.recording.meta.durationSeconds))")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                segmented
                if !isSkip {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.flowParticipants).font(Theme.body).foregroundStyle(Theme.textPrimary)
                        participantsField
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text(PostRecordingFlow.notice(model.choice))
                }
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                keysObserver
                if let p = selectedProvider, !model.hasKey(p) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(L10n.flowNoKey(p.displayName))
                        }.font(Theme.secondary).foregroundStyle(Theme.warning)
                        Button(L10n.flowAddKey(p.displayName)) {
                            model.app.windows.showSettings(model: model.app, tab: .notes)
                        }.buttonStyle(LinkButtonStyle())
                        Button(L10n.keyHelpLink) { model.app.windows.showKeyHelp(model: model.app, provider: p) }.buttonStyle(LinkButtonStyle())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 48).padding(.top, 24)
            FlowFooter {
                Button(L10n.flowBack) { model.flow.back() }.buttonStyle(SecondaryButtonStyle())
            } trailing: {
                Button(PostRecordingFlow.sendLabel(model.choice)) { model.submitNotes() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!model.canSubmit).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var keysObserver: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .hushKeysChanged)) { _ in keyTick += 1 }
            .id(keyTick)
    }

    private var segmented: some View {
        let options: [(String, NotesChoice)] = [("Claude", .provider(.claude)), ("ChatGPT", .provider(.openai)), (L10n.flowSkip, .skip)]
        return HStack(spacing: 2) {
            ForEach(options, id: \.0) { label, choice in
                let selected = model.choice == choice
                Button { model.choice = choice } label: {
                    Text(label).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accentFill : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    private var suggestions: [String] {
        let q = input.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return model.app.settings.recentParticipants.filter {
            $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
                && !model.participants.contains($0)
        }.prefix(3).map { $0 }
    }

    private var participantsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 6) {
                ForEach(model.participants, id: \.self) { name in
                    HStack(spacing: 4) {
                        Text(name).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                        Button { model.participants.removeAll { $0 == name } } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.flowRemoveParticipant(name))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.border))
                }
                TextField(model.participants.isEmpty ? L10n.flowParticipantsPlaceholder : "", text: $input)
                    .textFieldStyle(.plain).font(Theme.body).frame(minWidth: 160)
                    .onSubmit {
                        model.addParticipant(suggestions.first ?? input)
                        input = ""
                    }
                    .accessibilityLabel(L10n.flowParticipants)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { model.addParticipant(s); input = "" }.buttonStyle(LinkButtonStyle())
                    }
                }
            }
        }
    }
}

/// Wrapping horizontal layout for tokens.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 400, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (i, p) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var positions: [CGPoint] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxX = max(maxX, x)
        }
        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: 3.4

struct Spinner: View {
    @State private var angle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Theme.border, lineWidth: 3)
            Circle().trim(from: 0, to: 0.25).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
        .frame(width: 24, height: 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { angle = 360 }
        }
        .accessibilityHidden(true)
    }
}

struct GenerateStep: View {
    @ObservedObject var model: FlowModel

    var body: some View {
        if model.flow.failed { failed } else if model.isBusy { waiting } else { done }
    }

    private var provider: NotesProviderKind { model.currentProvider }

    private var waiting: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Spinner()
                Text(L10n.flowWaiting(provider.displayName)).font(Theme.title).foregroundStyle(Theme.textPrimary)
                Text(L10n.flowSentTo(provider.company)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            FlowFooter { EmptyView() } trailing: {
                Button(L10n.flowNext) {}.buttonStyle(PrimaryButtonStyle()).disabled(true)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.flowNotesHeader).font(Theme.title).foregroundStyle(Theme.textPrimary)
                    Text(model.title).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").foregroundStyle(Theme.success)
                        Text(L10n.flowMadeBy(model.recording.meta.notesProvider?.displayName ?? provider.displayName))
                    }
                    if let usage = model.recording.meta.notesUsage { Text(L10n.usageLine(usage)) }
                }.font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
            ScrollView { MarkdownView(text: model.notes).padding(16) }
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 16)
            FlowFooter {
                Button { model.copyNotes() } label: { Label(L10n.flowCopy, systemImage: "doc.on.doc") }.buttonStyle(SecondaryButtonStyle())
                Button { model.openNotesFile() } label: { Label(L10n.flowOpenWord, systemImage: "arrow.up.right.square") }.buttonStyle(SecondaryButtonStyle())
            } trailing: {
                Button(L10n.flowNext) { model.skipNotes() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { model.loadNotes() }
    }

    private var failed: some View {
        let failedProvider = model.failureProvider ?? provider
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.flowNotesHeader).font(Theme.title).foregroundStyle(Theme.textPrimary)
                    Text(model.title).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                WarningBanner(title: L10n.flowNotesFailed(failedProvider.displayName),
                              detail: L10n.flowNotesFailedHint(failedProvider.other.displayName))
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(Theme.textSecondary)
                    Text(model.displayFolder + "/transcript.txt").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 48).padding(.top, 8)
            FlowFooter {
                Button(L10n.flowSkipShort) { model.skipNotes() }.buttonStyle(SecondaryButtonStyle())
            } trailing: {
                Button(L10n.flowUseOther(failedProvider.other.displayName)) { model.switchProvider() }.buttonStyle(SecondaryButtonStyle())
                Button(L10n.flowRetry) { model.retryNotes() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: 3.5

struct FinishStep: View {
    @ObservedObject var model: FlowModel

    private var items: [(String, String)] {
        var rows = [("Transcript", "transcript.txt")]
        if model.hasNotes { rows.append(("Notities", "notities.docx")) }
        rows.append(("Audio", "audio.m4a"))
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.flowSaved).font(Theme.title).foregroundStyle(Theme.textPrimary)
                    Text(model.title).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                Panel(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                Text(item.0).font(Theme.body).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(item.1).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 16).frame(height: 40)
                            if i < items.count - 1 { Divider1() }
                        }
                        Divider1()
                        HStack(spacing: 8) {
                            Image(systemName: "folder").foregroundStyle(Theme.textSecondary)
                            Text(model.displayFolder).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(L10n.flowRevealShort) { model.reveal() }.buttonStyle(SecondaryButtonStyle(height: 24))
                        }
                        .padding(.horizontal, 16).frame(height: 44)
                    }
                }
                Divider1()
                Toggle(isOn: $model.deleteAudio) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.flowDeleteAudio).font(Theme.body).foregroundStyle(Theme.textPrimary)
                        Text(L10n.flowDeleteAudioHint).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!model.transcriptUsable)
                Spacer()
            }
            .padding(.horizontal, 48).padding(.top, 8)
            FlowFooter {
                EmptyView()
            } trailing: {
                Button(L10n.flowOpenInLibrary) { model.finish(openLibrary: true) }.buttonStyle(SecondaryButtonStyle())
                Button(L10n.flowDone) { model.finish(openLibrary: false) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            model.deleteAudio = AudioDeletionPolicy.initialChoice(settingDefault: model.app.settings.deleteAudioByDefault,
                                                                  transcriptUsable: model.transcriptUsable)
        }
    }
}

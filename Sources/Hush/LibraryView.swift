import SwiftUI
import AVFoundation
import AppKit
import HushCore

@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var current: Double = 0
    @Published var duration: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL?) {
        stop()
        guard let url, FileManager.default.fileExists(atPath: url.path), let p = try? AVAudioPlayer(contentsOf: url) else { duration = 0; return }
        player = p; duration = p.duration; current = 0
        p.prepareToPlay()
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying { player.pause(); isPlaying = false; timer?.invalidate() }
        else {
            player.play(); isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let p = self.player else { return }
                    self.current = p.currentTime
                    if !p.isPlaying { self.isPlaying = false; self.timer?.invalidate() }
                }
            }
        }
    }

    func seek(_ t: Double) { player?.currentTime = t; current = t }
    func stop() { player?.stop(); player = nil; timer?.invalidate(); isPlaying = false; current = 0 }
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""

    private var filtered: [Recording] { model.store.search(model.recordings, query: query) }
    private var groups: [(String, [Recording])] {
        var result: [(String, [Recording])] = []
        for r in filtered {
            let label = model.format.groupLabel(for: r.meta.start)
            if let i = result.firstIndex(where: { $0.0 == label }) { result[i].1.append(r) } else { result.append((label, [r])) }
        }
        return result
    }
    private var selected: Recording? { model.recordings.first { $0.id == model.selectedRecordingID } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 260)
            Rectangle().fill(Theme.border).frame(width: 1)
            Group {
                if model.recordings.isEmpty { emptyState }
                else if let selected { RecordingDetail(recording: selected).id(selected.id) }
                else { Color.clear }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .onAppear {
            model.reloadRecordings()
            if model.selectedRecordingID == nil { model.selectedRecordingID = model.recordings.first?.id }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                TextField(L10n.libSearch, text: $query).textFieldStyle(.plain).font(Theme.body)
                    .accessibilityLabel(L10n.libSearch)
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceRaised))
            .padding(.horizontal, 12).padding(.top, 44).padding(.bottom, 8)
            .disabled(model.recordings.isEmpty).opacity(model.recordings.isEmpty ? 0.5 : 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    ForEach(groups, id: \.0) { label, items in
                        Text(label).font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
                        ForEach(items) { r in SidebarRow(recording: r, selected: r.id == model.selectedRecordingID) {
                            model.selectedRecordingID = r.id
                        } }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .background(Theme.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.surface).overlay(Circle().stroke(Theme.border, lineWidth: 1))
                Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 64, height: 64)
            Text(L10n.libEmpty).font(Theme.title).foregroundStyle(Theme.textPrimary)
            Text(L10n.libEmptyHint(model.shortcut.display)).font(Theme.body).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct SidebarRow: View {
    @EnvironmentObject var model: AppModel
    let recording: Recording
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let m = recording.meta
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.format.timeRange(m.start, m.end).replacingOccurrences(of: " tot ", with: " tot "))
                        .font(Theme.body).foregroundStyle(selected ? Color.white : Theme.textPrimary)
                    Text(model.format.duration(m.durationSeconds)).font(Theme.secondary)
                        .foregroundStyle(selected ? Theme.selectedDuration : Theme.textSecondary)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if m.transcriptStatus == .failed { icon("exclamationmark.triangle.fill", L10n.a11yFailed, Theme.warning) }
                    if recording.hasTranscript { icon("text.alignleft", L10n.a11yTranscript) }
                    if recording.hasNotes { icon("doc.text", L10n.a11yNotes) }
                    if m.audioDeleted { icon("waveform.slash", L10n.a11yAudioDeleted, selected ? .white : Theme.deletedIcon) }
                    else { icon("waveform", L10n.a11yAudioKept) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accentFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func icon(_ name: String, _ label: String, _ color: Color? = nil) -> some View {
        Image(systemName: name).font(.system(size: 12))
            .foregroundStyle(selected ? Color.white : (color ?? Theme.textSecondary))
            .accessibilityLabel(label)
    }
}

struct RecordingDetail: View {
    @EnvironmentObject var model: AppModel
    let recording: Recording
    enum Tab { case notes, transcript }
    @State private var tab: Tab = .transcript
    @StateObject private var player = AudioPlayerModel()

    private var m: RecordingMeta { recording.meta }
    private var notes: String? { model.store.notesText(for: recording) }
    private var transcript: String? { model.store.transcriptText(for: recording) }

    private var subtitle: String {
        var s = model.format.duration(m.durationSeconds)
        if !m.participants.isEmpty { s += " · " + L10n.libWith(m.participants.joined(separator: ", ")) }
        if let usage = m.notesUsage { s += " · " + L10n.usageLine(usage) }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if notes != nil {
                tabs.padding(.horizontal, 24).padding(.bottom, 12)
            }
            if model.recoveredIDs.contains(recording.id) && m.transcriptStatus != .done {
                WarningBanner(title: L10n.crashRecovered(minutes: Int((m.durationSeconds / 60).rounded())))
                    .overlay(alignment: .trailing) {
                        Button(L10n.crashTranscribeNow) { model.openFlow(for: recording) }
                            .buttonStyle(SecondaryButtonStyle(height: 24)).padding(.trailing, 16)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 12)
            } else if m.transcriptStatus == .failed {
                WarningBanner(title: L10n.flowTranscribeFailed)
                    .overlay(alignment: .trailing) {
                        Button(L10n.flowRetry) { model.openFlow(for: recording, step: .transcribe) }
                            .buttonStyle(SecondaryButtonStyle(height: 24)).padding(.trailing, 16)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider1()
            content
            if !m.audioDeleted, FileManager.default.fileExists(atPath: playbackURL?.path ?? "") { Divider1(); audioBar }
        }
        .onAppear {
            tab = notes != nil ? .notes : .transcript
            player.load(m.audioDeleted ? nil : playbackURL)
        }
        .onDisappear { player.stop() }
    }

    private var playbackURL: URL? {
        FileManager.default.fileExists(atPath: recording.audioURL.path) ? recording.audioURL
            : (FileManager.default.fileExists(atPath: recording.micURL.path) ? recording.micURL : nil)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.format.longTitle(m.start, m.end)).font(Theme.title).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(L10n.libMakeNotes) { model.openFlow(for: recording, step: .notes) }
                .buttonStyle(SecondaryButtonStyle()).disabled(!recording.hasTranscript)
            if recording.hasNotes {
                Button(L10n.flowOpenWord) {
                    if let url = DocxExporter.ensureDocument(for: recording) { NSWorkspace.shared.open(url) }
                }.buttonStyle(SecondaryButtonStyle())
            }
            Button(L10n.flowReveal) { model.reveal(recording) }.buttonStyle(SecondaryButtonStyle())
            Menu {
                Button(L10n.libDelete, role: .destructive) { model.deleteRecording(recording) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).frame(width: 28)
            .accessibilityLabel(L10n.libMore)
        }
        .padding(.top, 38).padding(.horizontal, 24).padding(.bottom, 12)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(L10n.libTabNotes, .notes)
            tabButton(L10n.libTabTranscript, .transcript)
        }
        .padding(2)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabButton(_ title: String, _ value: Tab) -> some View {
        let on = tab == value
        return Button { tab = value } label: {
            Text(title).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? Color.white : Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.accentFill : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        if tab == .notes, let notes {
            ScrollView {
                MarkdownView(text: notes).frame(maxWidth: 640, alignment: .leading).padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let transcript, !transcript.isEmpty {
            TranscriptLines(segments: Transcript.parse(transcript), youName: model.settings.userName)
        } else {
            Spacer()
        }
    }

    private var audioBar: some View {
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11)).foregroundStyle(Color.white)
                    .frame(width: 28, height: 28).background(Circle().fill(Theme.accentFill))
            }
            .buttonStyle(.plain).accessibilityLabel(player.isPlaying ? L10n.libPause : L10n.libPlay)
            Text(DutchFormat.clock(player.current).dropFirst(3)).font(Theme.secondary.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            Scrubber(value: Binding(get: { player.current }, set: { player.seek($0) }), range: max(player.duration, 0.01))
            Text(DutchFormat.clock(player.duration).dropFirst(3)).font(Theme.secondary.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text(playbackURL?.lastPathComponent ?? "audio.m4a").font(.system(size: 11, design: .monospaced))
            }.foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16).frame(height: 48).background(Theme.surface)
    }
}

struct Scrubber: View {
    @Binding var value: Double
    let range: Double
    var body: some View {
        GeometryReader { geo in
            let fraction = min(max(value / range, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border).frame(height: 4)
                Capsule().fill(Theme.accent).frame(width: geo.size.width * fraction, height: 4)
                Circle().fill(Color.white).frame(width: 12, height: 12).offset(x: max(0, geo.size.width * fraction - 6))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(max(g.location.x / geo.size.width, 0), 1) * range
            })
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel("Afspeelpositie")
        .accessibilityValue(DutchFormat.clock(value))
        .accessibilityAdjustableAction { dir in
            value = min(max(value + (dir == .increment ? 10 : -10), 0), range)
        }
    }
}

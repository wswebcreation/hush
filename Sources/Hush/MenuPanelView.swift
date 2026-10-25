import SwiftUI
import AppKit
import HushCore

struct PulsingDot: View {
    var size: CGFloat = 8
    var paused = false
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle().fill(Theme.recording).frame(width: size, height: size)
            .opacity(paused ? 0.45 : (dim ? 0.45 : 1))
            .onAppear {
                guard !reduceMotion, !paused else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

struct LevelMeter: View {
    let icon: String
    let label: String
    let level: Float
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).frame(width: 16)
            Text(label).font(Theme.secondary).foregroundStyle(Theme.textSecondary).frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.border)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(level))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(level * 100)) procent")
    }
}

struct MenuPanelView: View {
    @EnvironmentObject var model: AppModel
    var close: () -> Void
    @State private var startAnyway = false

    var body: some View {
        VStack(spacing: model.phase == .recording ? 12 : 8) {
            if model.phase == .recording { recordingContent } else { idleContent }
            VStack(spacing: 0) {
                menuRow(L10n.menuOpen, shortcut: "⌘O", key: "o") { close(); model.openInLibrary(nil) }
                menuRow(L10n.menuSettings, shortcut: "⌘,", key: ",") { close(); model.windows.showSettings(model: model) }
                menuRow(L10n.storyMenu, shortcut: "⌘I", key: "i") { close(); model.windows.showStory(model: model) }
                menuRow(L10n.menuQuit, shortcut: "⌘Q", key: "q") { close(); NSApp.terminate(nil) }
            }
        }
        .padding(8)
        .frame(width: 280)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Idle

    private var idleContent: some View {
        VStack(spacing: 8) {
            if model.diskLow && !startAnyway {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                        Text(L10n.diskLow).foregroundStyle(Theme.warning)
                    }.font(Theme.secondary)
                    Button(L10n.diskStartAnyway) { startAnyway = true }.buttonStyle(LinkButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            Button {
                close(); model.startRecording()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 10))
                    Text(L10n.menuStart)
                    Spacer()
                    Text(model.shortcut.display).font(.system(size: 13)).fontWeight(.regular)
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 32, fullWidth: true))
            .disabled(model.diskLow && !startAnyway)

            sourceLine
            Divider1().padding(.horizontal, -8)
            Text(L10n.menuRecent).font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
            VStack(spacing: 0) {
                ForEach(model.recordings.prefix(3)) { r in recentRow(r) }
            }
            Divider1().padding(.horizontal, -8)
        }
    }

    @ViewBuilder private var sourceLine: some View {
        if !model.micAllowed {
            sourceWarning(L10n.permMicOff)
        } else if !model.settings.captureSystemAudio {
            sourceWarning(L10n.permSystemAudioOff)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "mic").font(.system(size: 11))
                Text(L10n.menuSources(model.micDeviceName.isEmpty ? L10n.setSystemDefault : model.micDeviceName)).lineLimit(1)
            }
            .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
        }
    }

    private func sourceWarning(_ text: String) -> some View {
        Button { close(); model.windows.showSettings(model: model, tab: .recording) } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(text).multilineTextAlignment(.leading)
            }
            .font(Theme.secondary).foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.permOpenSettings)
    }

    private func recentRow(_ r: Recording) -> some View {
        Button { close(); model.openInLibrary(r.id) } label: {
            HStack {
                Text(model.format.title(r.meta.start, r.meta.end)).font(Theme.secondary).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                if let badge = RecentBadge(for: r) {
                    switch badge.kind {
                    case .notes: Badge(text: L10n.badgeNotes, style: .notes)
                    case .transcript: Badge(text: L10n.badgeTranscript, style: .neutral)
                    case .failed: Badge(text: L10n.badgeFailed, style: .warning)
                    }
                }
            }
            .padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }

    // MARK: Recording

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PulsingDot(paused: model.isPaused)
                    Text(L10n.menuRecordingSince(model.startedAt.map { model.format.time($0) } ?? ""))
                        .font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
                }
                Text(DutchFormat.clock(model.elapsed)).font(Theme.timer).foregroundStyle(Theme.recording)
                    .accessibilityLabel("Verstreken tijd \(DutchFormat.clock(model.elapsed))")
            }
            .padding(.horizontal, 8)

            VStack(spacing: 8) {
                LevelMeter(icon: "mic", label: L10n.menuYou, level: model.micLevel, color: Theme.accent)
                LevelMeter(icon: "speaker.wave.2", label: L10n.menuThem, level: model.systemLevel, color: Theme.textSecondary)
            }
            .padding(.horizontal, 8)

            if let m = model.systemSilenceMinutes { silence(L10n.menuSilence(minutes: m, source: L10n.menuThem)) }
            else if let m = model.micSilenceMinutes { silence(L10n.menuSilence(minutes: m, source: L10n.menuYou)) }

            Button { close(); model.stopRecording() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.fill").font(.system(size: 10)).foregroundStyle(Theme.recording)
                    Text(L10n.menuStop)
                    Spacer()
                    Text(model.shortcut.display).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(StopButtonStyle())

            Button { model.togglePause() } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill").font(.system(size: 11))
                    Text(model.isPaused ? L10n.menuResume : L10n.menuPause)
                }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32, fullWidth: true))

            Divider1().padding(.horizontal, -8)
        }
    }

    private func silence(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
        }
        .font(Theme.secondary).foregroundStyle(Theme.warning).padding(.horizontal, 8)
    }

    private func menuRow(_ title: String, shortcut: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.body).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(shortcut).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .keyboardShortcut(key, modifiers: .command)
    }
}

struct HoverRowStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(hover || configuration.isPressed ? Theme.surfaceRaised : Color.clear))
            .onHover { hover = $0 }
    }
}

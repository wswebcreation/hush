import SwiftUI
import AppKit
import HushCore

struct AboutView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18).fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
                .overlay(Image(systemName: "waveform").font(.system(size: 36)).foregroundStyle(Theme.accent))
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("Hush").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(L10n.aboutVersion(version, build)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Text(L10n.aboutTagline).font(Theme.body).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    row(L10n.setTranscription, L10n.setEngineValue)
                    Divider1()
                    row(L10n.setLanguages, L10n.aboutLanguagesValue)
                }
            }
            Button(L10n.storyMenu) { AppModel.shared.windows.showStory(model: AppModel.shared) }.buttonStyle(SecondaryButtonStyle())
            Spacer(minLength: 0)
            Text(L10n.aboutBuiltBy).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            // No update mechanism in v1, so there is no "Zoek naar updates" button.
            Button(L10n.aboutWhatsNew) {
                if let url = URL(string: "https://github.com/techchamps/hush/releases") { NSWorkspace.shared.open(url) }
            }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, 8).padding(.horizontal, 32).padding(.bottom, 24)
        .frame(width: 360, height: 440)
        .background(Theme.background)
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l).font(Theme.body).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(v).font(Theme.body).foregroundStyle(Theme.textPrimary)
        }.padding(.horizontal, 16).frame(height: 32)
    }
}

struct HelpView: View {
    @EnvironmentObject var model: AppModel
    var onClose: () -> Void
    @State private var dontShow = false

    private var steps: [(String, String)] {
        [(L10n.helpStep1Title, L10n.helpStep1Body(model.shortcut.display)),
         (L10n.helpStep2Title, L10n.helpStep2Body),
         (L10n.helpStep3Title, L10n.helpStep3Body),
         (L10n.helpStep4Title, L10n.helpStep4Body(model.displayPath))]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.helpTitle).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(L10n.helpSubtitle).font(Theme.body).foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.badgeNotesText)
                                .frame(width: 24, height: 24).background(Circle().fill(Theme.badgeNotesBg)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.0).font(Theme.bodySemibold).foregroundStyle(Theme.textPrimary)
                                Text(step.1).font(Theme.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Panel {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.success)
                        Text(L10n.helpSafety).font(Theme.body).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40).padding(.top, 8)
            FlowFooter {
                Toggle(L10n.helpDontShow, isOn: $dontShow).toggleStyle(.checkbox).font(Theme.body).foregroundStyle(Theme.textSecondary)
            } trailing: {
                Button(L10n.menuSettings) { model.windows.showSettings(model: model) }.buttonStyle(SecondaryButtonStyle())
                Button(L10n.helpUnderstood) {
                    if dontShow { model.settings.hasSeenHelp = true }
                    onClose()
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
        .onAppear { dontShow = model.settings.hasSeenHelp }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    /// Only the permissions that are still missing.
    let steps: [PermissionStep]
    var onFinish: () -> Void
    @State private var step = 0
    @State private var micDone = false
    @State private var systemDone = false
    @State private var level: Float = 0
    @State private var probe: AudioProbe?

    private var isMic: Bool { steps[step] == .mic }
    private var granted: Bool { isMic ? micDone : systemDone }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: isMic ? "mic" : "speaker.wave.2").font(.system(size: 28)).foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(isMic ? L10n.onbMicTitle : L10n.onbSystemTitle).font(Theme.title).foregroundStyle(Theme.textPrimary)
                Text(isMic ? L10n.onbMicBody : L10n.onbSystemBody).font(Theme.body).foregroundStyle(Theme.textSecondary)
                if granted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                        Text(L10n.setAllowed).font(Theme.body).foregroundStyle(Theme.textSecondary)
                    }
                    LevelMeter(icon: isMic ? "mic" : "speaker.wave.2", label: isMic ? L10n.menuYou : L10n.menuThem,
                               level: level, color: isMic ? Theme.accent : Theme.textSecondary).frame(width: 240)
                } else {
                    Button(L10n.setGrantAccess) { grant() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
            Spacer()
            FlowFooter {
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { Circle().fill($0 == step ? Theme.accent : Theme.border).frame(width: 6, height: 6) }
                }
            } trailing: {
                Button(L10n.flowNext) {
                    probe?.stop(); probe = nil; level = 0
                    if step + 1 < steps.count { step += 1 } else { onFinish() }
                }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
        .onDisappear { probe?.stop() }
    }

    private func grant() {
        if isMic {
            Task {
                micDone = await model.ensureMicAccess()
                if !micDone { Permissions.openPrivacy("Privacy_Microphone") } else { startProbe(system: false) }
            }
        } else {
            Permissions.requestSystemAudio {
                systemDone = Permissions.systemAudioTested
                if systemDone { startProbe(system: true) }
            }
        }
    }

    private func startProbe(system: Bool) {
        let p = AudioProbe(system: system) { v in Task { @MainActor in level = v } }
        probe = p
        p.start()
    }
}

/// Live test meter for onboarding: records to a throwaway file and reports the level.
final class AudioProbe: @unchecked Sendable {
    private let system: Bool
    private let onLevel: (Float) -> Void
    private var recorder: AudioRecorder?
    private var timer: Timer?
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hush-probe-\(UUID().uuidString)")

    init(system: Bool, onLevel: @escaping (Float) -> Void) { self.system = system; self.onLevel = onLevel }

    func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rec = Recording(folder: folder, meta: RecordingMeta(start: Date()))
        let r = AudioRecorder(recording: rec, micDeviceUID: AppModel.shared.settings.micDeviceUID, captureSystem: system)
        guard (try? r.start()) != nil else { return }
        recorder = r
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let r = self.recorder else { return }
                self.onLevel(self.system ? r.systemLevel : r.micLevel)
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Intro after an update: what changed since the version the user last opened.
struct ReleaseNotesView: View {
    let entries: [ReleaseEntry]
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L10n.releaseNotesTitle(entries.first?.version ?? "")).font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    ForEach(entries, id: \.version) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            if entries.count > 1 {
                                Text(L10n.releaseNotesVersion(entry.version)).font(Theme.bodySemibold).foregroundStyle(Theme.textPrimary)
                            }
                            ForEach(entry.notes, id: \.self) { note in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").foregroundStyle(Theme.accent)
                                    Text(note).font(Theme.body).foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 48).padding(.vertical, 32)
            }
            FlowFooter { EmptyView() } trailing: {
                Button(L10n.flowDone, action: onFinish).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
    }
}

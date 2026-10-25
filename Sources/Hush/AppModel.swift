import AppKit
import AVFoundation
import Combine
import HushCore
import ServiceManagement
import UserNotifications
import os

private let log = Logger(subsystem: "nl.techchamps.hush", category: "app")

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = SettingsStore()
    let secrets: SecretStore = KeychainStore()
    let format = DutchFormat()

    var store: RecordingStore { RecordingStore(root: settings.recordingsFolder) }

    // Library
    @Published var recordings: [Recording] = []
    @Published var selectedRecordingID: UUID?
    @Published var recoveredIDs: Set<UUID> = []

    // Recording session
    enum Phase: Equatable { case idle, recording }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0
    @Published private(set) var micSilenceMinutes: Int?
    @Published private(set) var systemSilenceMinutes: Int?
    @Published var micDeviceName = ""
    @Published var diskLow = false
    @Published var micAllowed = true
    @Published var panelOpen = false { didSet { rescheduleTimer() } }
    @Published var shortcut: Shortcut

    private var recorder: AudioRecorder?
    private var current: Recording?
    private var timer: Timer?
    private var micSilence = SilenceDetector()
    private var systemSilence = SilenceDetector()
    private var systemWasEverLoud = false

    // Post recording flows, kept alive while transcribing in the background.
    @Published private(set) var flows: [UUID: FlowModel] = [:]

    let windows = WindowManager()
    /// Set after a first run or an update: when the launch windows are done, point at the menu bar icon.
    var pendingMenuBarHint = false
    var showMenuBarHint: (() -> Void)?
    var onRecordingStateChange: (() -> Void)?

    private init() {
        shortcut = settings.shortcut
        micDeviceName = AudioDevices.device(uid: settings.micDeviceUID)?.name ?? ""
    }

    // MARK: Launch

    func start() {
        reloadRecordings()
        recoverCrashedRecordings()
        refreshDiskAndPermissions()
        applyDockPolicy()
        applyLaunchAtLogin()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let plan = LaunchPlan.decide(onboardingDone: settings.hasCompletedOnboarding, lastSeenVersion: settings.lastSeenVersion, current: version)
        settings.lastSeenVersion = version
        switch plan {
        case .firstRun:
            pendingMenuBarHint = true
            windows.showStory(model: self, thenOnboarding: true)
        case .updated(let notes):
            // Intro, then what is new, then any permission that is still missing.
            pendingMenuBarHint = true
            windows.showStory(model: self) { [weak self] in
                guard let self else { return }
                self.windows.showReleaseNotes(entries: notes) { [weak self] in
                    guard let self else { return }
                    self.windows.showOnboarding(model: self, thenHelp: false)
                }
            }
        case .nothing:
            windows.showOnboarding(model: self, thenHelp: !settings.hasSeenHelp)
        }
    }

    func reloadRecordings() {
        recordings = store.scan()
    }

    func refreshDiskAndPermissions() {
        diskLow = store.isDiskLow()
        micAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        micDeviceName = AudioDevices.device(uid: settings.micDeviceUID)?.name ?? micDeviceName
    }

    /// A recording without an end time never finished: keep the audio and offer transcription.
    private func recoverCrashedRecordings() {
        for rec in store.unfinishedRecordings() {
            let seconds = Self.audioSeconds(of: rec.micURL)
            guard seconds > 0, let fixed = try? store.recover(rec, audioSeconds: seconds) else { continue }
            recoveredIDs.insert(fixed.id)
            notify(title: "Hush", body: L10n.crashRecovered(minutes: Int((seconds / 60).rounded())), identifier: "recover-\(fixed.id)")
        }
        reloadRecordings()
    }

    static func audioSeconds(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // MARK: Settings side effects

    func applyDockPolicy() {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { log.error("launch at login failed: \(error.localizedDescription)") }
    }

    func updateShortcut(_ s: Shortcut) {
        settings.shortcut = s
        shortcut = s
        HotKeyCenter.shared.register(s) { [weak self] in Task { @MainActor in self?.toggleRecording() } }
    }

    // MARK: Recording

    func toggleRecording() {
        phase == .recording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard phase == .idle else { return }
        Task {
            guard await ensureMicAccess() else { windows.showSettings(model: self, tab: .recording); return }
            do {
                let meta = RecordingMeta(start: Date(), micDevice: AudioDevices.device(uid: settings.micDeviceUID)?.name ?? "",
                                         systemAudioCaptured: settings.captureSystemAudio,
                                         appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                let rec = try store.create(meta: meta)
                let recorder = AudioRecorder(recording: rec, micDeviceUID: settings.micDeviceUID, captureSystem: settings.captureSystemAudio)
                try recorder.start()
                self.recorder = recorder
                current = rec
                micDeviceName = recorder.micDeviceName
                micSilence.reset(); systemSilence.reset(); systemWasEverLoud = false
                elapsed = 0; isPaused = false; startedAt = meta.start
                micSilenceMinutes = nil; systemSilenceMinutes = nil
                phase = .recording
                rescheduleTimer()
                onRecordingStateChange?()
            } catch {
                log.error("start failed: \(String(describing: error))")
                NSSound.beep()
            }
        }
    }

    func ensureMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micAllowed = true; return true
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            micAllowed = ok
            return ok
        default: micAllowed = false; return false
        }
    }

    func togglePause() {
        guard phase == .recording else { return }
        isPaused.toggle()
        recorder?.setPaused(isPaused)
        onRecordingStateChange?()
    }

    func stopRecording() {
        guard phase == .recording, let recorder, let rec = current else { return }
        let seconds = recorder.stop()
        timer?.invalidate(); timer = nil
        self.recorder = nil; current = nil
        phase = .idle; isPaused = false; micLevel = 0; systemLevel = 0
        onRecordingStateChange?()

        var finished = rec
        finished.meta.end = rec.meta.start.addingTimeInterval(seconds)
        finished.meta.durationSeconds = seconds
        try? store.save(finished)

        if seconds < RecordingStore.minimumRecordingSeconds {
            if confirmShortRecording() { openFlow(for: finished) } else { try? store.delete(finished); reloadRecordings() }
            return
        }
        reloadRecordings()
        openFlow(for: finished)
    }

    private func confirmShortRecording() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.tooShortTitle
        alert.addButton(withTitle: L10n.tooShortKeep)
        alert.addButton(withTitle: L10n.tooShortDelete)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Returns true when it is fine to quit now.
    func confirmQuit() -> Bool {
        guard phase == .recording else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.quitWhileRecording
        alert.addButton(withTitle: L10n.quitStopAndSave)
        alert.addButton(withTitle: L10n.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        stopRecording()
        return true
    }

    // MARK: Timer / levels

    private func rescheduleTimer() {
        timer?.invalidate(); timer = nil
        guard phase == .recording else { return }
        // Meters only move while the panel is open; otherwise a slow tick is enough for silence detection.
        let interval: TimeInterval = panelOpen ? 0.1 : 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = interval / 4
    }

    private func tick() {
        guard let recorder else { return }
        elapsed = recorder.micSeconds
        let mic = recorder.micLevel, sys = recorder.systemLevel
        if panelOpen { micLevel = isPaused ? 0 : mic; systemLevel = isPaused ? 0 : sys }
        guard !isPaused else { return }
        // meterValue maps -60 dB…0 dB to 0…1, so ~0.0 means silence.
        micSilence.update(rms: mic > 0.01 ? 1 : 0, at: elapsed)
        systemSilence.update(rms: sys > 0.01 ? 1 : 0, at: elapsed)
        let micMin = micSilence.isWarning(at: elapsed) ? micSilence.warningMinutes(at: elapsed) : nil
        let sysMin = (systemSilence.isWarning(at: elapsed) && settings.captureSystemAudio) ? systemSilence.warningMinutes(at: elapsed) : nil
        if micMin != micSilenceMinutes { micSilenceMinutes = micMin }
        if sysMin != systemSilenceMinutes { systemSilenceMinutes = sysMin }
    }

    // MARK: Post recording flow

    func openFlow(for recording: Recording, step: FlowStep? = nil) {
        let model: FlowModel
        if let existing = flows[recording.id] {
            model = existing
        } else {
            model = FlowModel(recording: recording, app: self)
            flows[recording.id] = model
        }
        if let step, model.flow.step != step, !model.isBusy { model.flow = PostRecordingFlow(step: step) }
        windows.showFlow(model: model, app: self)
        if model.flow.step == .transcribe, !model.isBusy, !model.flow.failed, recording.meta.transcriptStatus != .done {
            model.startTranscription()
        }
    }

    func flowFinished(_ id: UUID) {
        flows[id] = nil
        reloadRecordings()
    }

    func notify(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        content.userInfo = ["id": identifier]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    // MARK: Library actions

    func openInLibrary(_ id: UUID?) {
        reloadRecordings()
        if let id { selectedRecordingID = id }
        windows.showLibrary(model: self)
    }

    func deleteRecording(_ r: Recording) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.deleteTitle
        alert.informativeText = L10n.deleteBody
        alert.addButton(withTitle: L10n.deleteConfirm)
        alert.addButton(withTitle: L10n.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.delete(r)
        if selectedRecordingID == r.id { selectedRecordingID = nil }
        reloadRecordings()
    }

    func reveal(_ r: Recording) { NSWorkspace.shared.activateFileViewerSelecting([r.folder]) }

    func notesProvider(for kind: NotesProviderKind) -> NotesProvider {
        switch kind {
        case .claude: ClaudeProvider(secrets: secrets, model: settings.claudeModel)
        case .openai: OpenAIProvider(secrets: secrets, model: settings.openAIModel)
        }
    }

    var displayPath: String {
        settings.recordingsFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

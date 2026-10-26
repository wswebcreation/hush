import AVFoundation
import AppKit
import HushCore
import SwiftUI
import os

private let log = Logger(subsystem: "nl.techchamps.hush", category: "audiotest")

/// Thread-safe level handed from the audio thread to the main-actor poll timer.
private final class LevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    var level: Float { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
}

/// Live meter tests for the microphone and for system audio. Nothing is kept: the system test writes to a temp file that is deleted.
@MainActor
final class AudioTest: ObservableObject {
    enum Kind { case mic, system }

    @Published private(set) var active: Kind?
    @Published private(set) var level: Float = 0
    @Published private(set) var verdict: LevelTest.Verdict = .listening
    @Published private(set) var systemFailed = false
    /// Last finished or running test, so the status line stays visible after a test ends.
    @Published private(set) var last: Kind?

    private var mic: MicCapture?
    private var tap: SystemTap?
    private var writer: ChannelWriter?
    private var tempURL: URL?
    private var chime: NSSound?
    private var timer: Timer?
    private var started = Date()
    private var judge = LevelTest()
    private let box = LevelBox()

    func startMic(deviceUID: String?) {
        stop()
        let box = box
        let mic = MicCapture(preferredUID: deviceUID) { buffer in
            guard let ch = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let rms = AudioLevels.rms(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
            box.level = AudioLevels.meterValue(rms: rms)
        }
        do { try mic.start() } catch {
            log.error("mic test failed: \(error.localizedDescription)")
            return begin(.mic, failed: true)
        }
        self.mic = mic
        begin(.mic)
    }

    func startSystem() {
        stop()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hush-test-\(UUID().uuidString).caf")
        do {
            let writer = try ChannelWriter(url: url)
            let tap = SystemTap()
            try tap.start(writer: writer, excludeOwnProcess: false)
            self.writer = writer; self.tap = tap; tempURL = url
        } catch {
            log.error("system test failed: \(String(describing: error))")
            try? FileManager.default.removeItem(at: url)
            return begin(.system, failed: true)
        }
        chime = NSSound(named: "Glass")
        chime?.play()
        begin(.system)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        mic?.stop(); mic = nil
        tap?.stop(); tap = nil
        writer = nil
        chime?.stop(); chime = nil
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        tempURL = nil
        active = nil
        level = 0
    }

    private func begin(_ kind: Kind, failed: Bool = false) {
        last = kind
        systemFailed = failed && kind == .system
        judge = LevelTest()
        started = Date()
        box.level = 0
        verdict = failed ? .silent : .listening
        guard !failed else { return }
        active = kind
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let kind = active else { return }
        let elapsed = Date().timeIntervalSince(started)
        level = kind == .mic ? box.level : (writer?.level ?? 0)
        judge.update(level: level)
        verdict = judge.verdict(at: elapsed)
        // The chime is short; replay once so a 3 second window always contains sound.
        if kind == .system {
            if let chime, !chime.isPlaying, elapsed < 2 { chime.play() }
            if elapsed >= judge.silentAfter + 0.5 || (verdict == .ok && elapsed > 1.5) { stop() }
        }
    }
}

struct AudioTestRows: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var test = AudioTest()
    let micUID: String?
    let systemAudio: Bool

    var body: some View {
        FormRow(label: L10n.setTest) {
            VStack(alignment: .leading, spacing: 10) {
                row(kind: .mic, title: L10n.testMic, meterLabel: L10n.testLevelMic, icon: "mic.fill") {
                    Task {
                        if await model.ensureMicAccess() { test.startMic(deviceUID: micUID) }
                        else { Permissions.openPrivacy("Privacy_Microphone") }
                    }
                }
                if systemAudio {
                    row(kind: .system, title: L10n.testSystem, meterLabel: L10n.testLevelSystem, icon: "speaker.wave.2.fill") {
                        test.startSystem()
                    }
                }
            }
        }
        .onChange(of: micUID) { _, _ in test.stop() }
        .onDisappear { test.stop() }
    }

    @ViewBuilder
    private func row(kind: AudioTest.Kind, title: String, meterLabel: String, icon: String, start: @escaping () -> Void) -> some View {
        let running = test.active == kind
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button(running ? L10n.testStop : title) { running ? test.stop() : start() }
                    .buttonStyle(SecondaryButtonStyle(height: 24))
                    .disabled(test.active != nil && !running)
                if test.last == kind {
                    LevelMeter(icon: icon, label: meterLabel, level: running ? test.level : 0,
                               color: test.verdict == .ok ? Theme.success : Theme.accent)
                        .frame(width: 160)
                }
            }
            if test.last == kind { Hint(status(kind)) }
        }
    }

    private func status(_ kind: AudioTest.Kind) -> String {
        switch (kind, test.verdict) {
        case (.mic, .listening): L10n.testMicListening
        case (.mic, .ok): L10n.testMicOk
        case (.mic, .silent): L10n.testMicSilent
        case (.system, .listening): L10n.testSystemListening
        case (.system, .ok): L10n.testSystemOk
        case (.system, .silent): test.systemFailed ? L10n.testSystemFailed : L10n.testSystemSilent
        }
    }
}

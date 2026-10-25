import AppKit
import AVFoundation
import HushCore

enum PermissionStep { case mic, system }

enum Permissions {
    /// The permissions Hush still needs, in the order they are asked.
    @MainActor static func missing(settings: SettingsStore) -> [PermissionStep] {
        var steps: [PermissionStep] = []
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { steps.append(.mic) }
        if settings.captureSystemAudio && !systemAudioTested { steps.append(.system) }
        return steps
    }

    private static let testedKey = "systemAudioTested"

    /// Core Audio has no public preflight for audio capture, so "tested" means a tap was created successfully.
    static var systemAudioTested: Bool { UserDefaults.standard.bool(forKey: testedKey) }

    static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    /// Creating a tap triggers the system prompt on first use.
    static func requestSystemAudio(completion: @escaping @MainActor () -> Void) {
        DispatchQueue.global().async {
            let tap = SystemTap()
            let probe = try? ChannelWriter(url: FileManager.default.temporaryDirectory.appendingPathComponent("hush-probe.caf"))
            var ok = false
            if let probe, (try? tap.start(writer: probe)) != nil { ok = true }
            Thread.sleep(forTimeInterval: 0.5)
            tap.stop()
            DispatchQueue.main.async {
                UserDefaults.standard.set(ok, forKey: testedKey)
                if !ok { openPrivacy("Privacy_AudioCapture") }
                Task { @MainActor in completion() }
            }
        }
    }
}

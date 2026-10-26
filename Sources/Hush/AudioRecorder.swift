import AVFoundation
import CoreAudio
import AudioToolbox
import HushCore
import os

private let log = Logger(subsystem: "nl.techchamps.hush", category: "recorder")

/// Converts any incoming buffer to 16 kHz mono 16 bit PCM, appends it to a CAF file, and tracks the level.
/// CAF stays readable after an abrupt stop, so a crash loses at most the unflushed tail.
final class ChannelWriter: @unchecked Sendable {
    static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    private let file: AVAudioFile
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var _level: Float = 0
    private var _paused = false
    private(set) var framesWritten: AVAudioFramePosition = 0

    init(url: URL) throws {
        file = try AVAudioFile(forWriting: url, settings: Self.outputFormat.settings,
                               commonFormat: .pcmFormatInt16, interleaved: true)
    }

    var level: Float { lock.withLock { _level } }
    var seconds: Double { Double(lock.withLock { framesWritten }) / 16_000 }
    var isPaused: Bool {
        get { lock.withLock { _paused } }
        set { lock.withLock { _paused = newValue } }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        // Level is measured on the source samples, before conversion.
        if let ch = buffer.floatChannelData, buffer.frameLength > 0 {
            let rms = AudioLevels.rms(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
            _level = AudioLevels.meterValue(rms: rms)
        }
        guard !_paused else { return }
        if converter == nil || sourceFormat != buffer.format {
            sourceFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: Self.outputFormat)
        }
        guard let converter else { return }
        let ratio = Self.outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            do {
                try file.write(from: out)
                framesWritten += AVAudioFramePosition(out.frameLength)
            } catch { log.error("write failed: \(error.localizedDescription)") }
        }
    }
}

enum RecorderError: Error { case noInputDevice, tapFailed(OSStatus), aggregateFailed(OSStatus) }

/// Captures the microphone (Jij) and system output (Anderen) into two CAF files.
final class AudioRecorder: @unchecked Sendable {
    private let recording: Recording
    private let micDeviceUID: String?
    private let captureSystem: Bool

    private var mic: MicCapture?
    private var micWriter: ChannelWriter?
    private(set) var systemWriter: ChannelWriter?
    private var tap = SystemTap()
    private var outputListener: AudioObjectPropertyListenerBlock?

    var micDeviceName: String { mic?.deviceName ?? "" }

    init(recording: Recording, micDeviceUID: String?, captureSystem: Bool) {
        self.recording = recording; self.micDeviceUID = micDeviceUID; self.captureSystem = captureSystem
    }

    var micLevel: Float { micWriter?.level ?? 0 }
    var systemLevel: Float { systemWriter?.level ?? 0 }
    var micSeconds: Double { micWriter?.seconds ?? 0 }

    func start() throws {
        let writer = try ChannelWriter(url: recording.micURL)
        micWriter = writer
        let mic = MicCapture(preferredUID: micDeviceUID) { buffer in writer.append(buffer) }
        try mic.start()
        self.mic = mic

        if captureSystem { startSystem() }
    }

    /// Called every second while recording: picks up a microphone that was switched on or unplugged, and restarts a stalled one.
    func restartMicIfStopped() { mic?.refresh() }

    private func startSystem() {
        do {
            let sysWriter = try systemWriter ?? ChannelWriter(url: recording.systemURL)
            systemWriter = sysWriter
            try tap.start(writer: sysWriter)
            installOutputListener()
        } catch {
            log.error("system tap failed: \(String(describing: error))")
        }
    }

    /// Headphones plugged in or AirPods connected: rebuild the tap without stopping the session.
    private func installOutputListener() {
        guard outputListener == nil else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let writer = self.systemWriter else { return }
            self.tap.stop()
            try? self.tap.start(writer: writer)
        }
        outputListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    func setPaused(_ paused: Bool) {
        micWriter?.isPaused = paused
        systemWriter?.isPaused = paused
    }

    /// Returns recorded seconds (mic track length).
    @discardableResult
    func stop() -> Double {
        if let block = outputListener {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                  mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
            outputListener = nil
        }
        mic?.stop()
        mic = nil
        tap.stop()
        let seconds = micWriter?.seconds ?? 0
        micWriter = nil
        systemWriter = nil
        return seconds
    }
}

/// Core Audio process tap in a private aggregate device. Not muted, so the meeting stays audible.
final class SystemTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "nl.techchamps.hush.tap", qos: .userInitiated)

    private func ownProcessObject() -> [AudioObjectID] {
        var pid = getpid()
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? [object] : []
    }

    /// `excludeOwnProcess: false` lets the tap hear Hush itself, which the output test needs for its chime.
    func start(writer: ChannelWriter, excludeOwnProcess: Bool = true) throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: excludeOwnProcess ? ownProcessObject() : [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw RecorderError.tapFailed(status) }

        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hush tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw RecorderError.aggregateFailed(status) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &format)
        guard status == noErr, let avFormat = AVAudioFormat(streamDescription: &format) else { stop(); throw RecorderError.tapFailed(status) }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, bufferListNoCopy: input, deallocator: nil) else { return }
            writer.append(buffer)
        }
        guard status == noErr else { stop(); throw RecorderError.aggregateFailed(status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { stop(); throw RecorderError.aggregateFailed(status) }
    }

    func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = kAudioObjectUnknown }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
    }
}

/// Mixes mic.caf and system.caf into one playback file (audio.m4a).
enum AudioMixer {
    static func export(mic: URL, system: URL?, to output: URL) async throws {
        let composition = AVMutableComposition()
        for url in [mic, system].compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.noInputDevice
        }
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .m4a)
    }
}

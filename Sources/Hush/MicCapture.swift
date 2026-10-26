import AVFoundation
import CoreAudio
import os

private let log = Logger(subsystem: "nl.techchamps.hush", category: "mic")

/// Records one input device on its own, independent of the output device. AVAudioEngine ties input and output to a
/// single device, which breaks when the microphone and the speakers/AirPods are different devices.
/// Follows the microphone: a device that is switched on or plugged in during the meeting is taken over, and a
/// session that stopped by itself is started again.
final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let preferredUID: String?
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let queue = DispatchQueue(label: "nl.techchamps.hush.mic")
    private let lock = NSLock()
    private var session: AVCaptureSession?
    private var currentUID: String?
    private var _deviceName = ""
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(preferredUID: String?, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.preferredUID = preferredUID
        self.onBuffer = onBuffer
    }

    var deviceName: String { lock.withLock { _deviceName } }

    func start() throws {
        guard let device = Self.resolve(preferredUID) else { throw RecorderError.noInputDevice }
        try queue.sync { try attach(device) }
        installListeners()
    }

    func stop() {
        removeListeners()
        queue.sync {
            session?.stopRunning()
            session = nil
            currentUID = nil
        }
    }

    /// Called every second while recording and whenever the devices change: switch to the right microphone, or restart.
    func refresh() {
        queue.async { [self] in
            guard session != nil, let device = Self.resolve(preferredUID) else { return }
            if device.uniqueID != currentUID {
                log.notice("microphone changed to \(device.localizedName)")
                try? attach(device)
            } else if let session, !session.isRunning {
                log.notice("microphone session restarted")
                session.startRunning()
            }
        }
    }

    // MARK: Session

    /// Must run on `queue`.
    private func attach(_ device: AVCaptureDevice) throws {
        session?.stopRunning()
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecorderError.noInputDevice }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        // Float32, one buffer per channel: the same shape the level meter and converter already expect.
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                                AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecorderError.noInputDevice }
        session.addOutput(output)
        session.startRunning()
        self.session = session
        currentUID = device.uniqueID
        lock.withLock { _deviceName = device.localizedName }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        var streamDescription = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                           into: buffer.mutableAudioBufferList) == noErr else { return }
        onBuffer(buffer)
    }

    // MARK: Device choice

    /// The chosen device when it is connected, otherwise whatever the system uses as input right now.
    private static func resolve(_ uid: String?) -> AVCaptureDevice? {
        if let uid, let device = AVCaptureDevice(uniqueID: uid) { return device }
        if let id = AudioDevices.defaultInput()?.uid, let device = AVCaptureDevice(uniqueID: id) { return device }
        return AVCaptureDevice.default(for: .audio)
    }

    private func installListeners() {
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            listeners.append((address, block))
        }
    }

    private func removeListeners() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
        listeners = []
    }
}

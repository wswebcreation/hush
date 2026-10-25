import AppKit
import SwiftUI
import Combine
import HushCore

final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// NSStatusItem plus a custom opaque panel (no NSMenu, no popover material).
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var panel: MenuPanel?
    private var monitors: [Any] = []
    private var pulseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseDown])
        updateIcon()
        Publishers.CombineLatest3(model.$phase, model.$isPaused, model.$startedAt)
            .sink { [weak self] _, _, _ in self?.updateIcon() }.store(in: &cancellables)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func updateIcon() {
        pulseTimer?.invalidate(); pulseTimer = nil
        guard let button = item.button else { return }
        if model.phase == .recording {
            button.image = Self.dotImage()
            button.image?.isTemplate = false
            button.toolTip = L10n.a11yStatusRecording
            button.setAccessibilityLabel(L10n.a11yStatusRecording)
            button.alphaValue = model.isPaused ? 0.45 : 1
            if !model.isPaused, !reduceMotion {
                // 1.6 s ease-in-out between 1.0 and 0.45.
                let start = Date()
                pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak button] _ in
                    let t = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 1.6) / 1.6
                    let eased = 0.5 - 0.5 * cos(t * 2 * .pi)
                    button?.alphaValue = 1.0 - 0.55 * eased
                }
            }
        } else {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: L10n.a11yStatusIdle)
            image?.isTemplate = true
            button.image = image
            button.alphaValue = 1
            button.toolTip = L10n.a11yStatusIdle
            button.setAccessibilityLabel(L10n.a11yStatusIdle)
        }
    }

    private static func dotImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            Theme.ns(0xE5484D).setFill()
            NSBezierPath(ovalIn: NSRect(x: (rect.width - 10) / 2, y: (rect.height - 10) / 2, width: 10, height: 10)).fill()
            return true
        }
        return image
    }

    // MARK: First launch hint

    private var hintPanel: NSPanel?
    private var hintTimers: [Timer] = []
    private var hintMonitor: Any?

    /// Points at the icon for a few seconds: a callout under it and a pulsing icon. Clicking anywhere dismisses it.
    func showHint() {
        guard let button = item.button, let buttonWindow = button.window, model.phase == .idle else { return }
        hideHint()
        let shortcut = model.shortcut.display
        let probe = NSHostingView(rootView: MenuBarHintView(shortcut: shortcut, caretOffset: 0))
        let size = probe.fittingSize
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonFrame.midX - size.width / 2
        if let screen = buttonWindow.screen { x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8) }
        let offset = buttonFrame.midX - (x + size.width / 2)
        let host = NSHostingView(rootView: MenuBarHintView(shortcut: shortcut, caretOffset: offset).preferredColorScheme(.dark))
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.appearance = NSAppearance(named: .darkAqua)
        p.setFrameOrigin(NSPoint(x: x, y: buttonFrame.minY - size.height - 2))
        p.orderFrontRegardless()
        hintPanel = p

        if !reduceMotion {
            let start = Date()
            hintTimers.append(Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak button] _ in
                let t = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 1.0)
                button?.alphaValue = 0.35 + 0.65 * (0.5 + 0.5 * cos(t * 2 * .pi))
            })
        }
        hintTimers.append(Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideHint() }
        })
        hintMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            Task { @MainActor in self?.hideHint() }
        }
    }

    func hideHint() {
        hintTimers.forEach { $0.invalidate() }
        hintTimers = []
        if let hintMonitor { NSEvent.removeMonitor(hintMonitor) }
        hintMonitor = nil
        guard let closing = hintPanel else { return }
        hintPanel = nil
        item.button?.alphaValue = 1
        closing.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = closing }
    }

    @objc func toggle() {
        hideHint()
        panel?.isVisible == true ? close() : open()
    }

    func open() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        model.refreshDiskAndPermissions()
        model.reloadRecordings()
        let root = MenuPanelView(close: { [weak self] in self?.close() }).environmentObject(model)
        let host = NSHostingView(rootView: root.preferredColorScheme(.dark))
        host.setFrameSize(host.fittingSize)
        let size = host.fittingSize
        let p = MenuPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.appearance = NSAppearance(named: .darkAqua)
        p.isReleasedWhenClosed = false
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - size.height - 4)
        if let screen = buttonWindow.screen { origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8) }
        p.setFrameOrigin(origin)
        p.makeKeyAndOrderFront(nil)
        panel = p
        model.panelOpen = true
        button.highlight(true)

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }  // Esc
            return event
        } as Any)
    }

    func close() {
        let closing = panel
        closing?.orderOut(nil)
        panel = nil
        // The panel is closed from inside its own button clicks; free it after the event, not during it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = closing }
        model.panelOpen = false
        item.button?.highlight(false)
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }
}

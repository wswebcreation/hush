import AppKit
import SwiftUI
import UserNotifications
import HushCore

@main
struct HushMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: StatusItemController?
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        installMainMenu()
        statusItem = StatusItemController(model: model)
        model.showMenuBarHint = { [weak self] in self?.statusItem?.showHint() }
        model.start()
        HotKeyCenter.shared.register(model.shortcut) { [weak self] in
            Task { @MainActor in self?.model.toggleRecording() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.confirmQuit() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.openInLibrary(nil) }
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        await MainActor.run {
            let uuidString = id.replacingOccurrences(of: "done-", with: "").replacingOccurrences(of: "recover-", with: "")
            guard let uuid = UUID(uuidString: uuidString) else { return }
            if id.hasPrefix("done-"), let flow = model.flows[uuid] {
                model.openFlow(for: flow.recording, step: .review)
            } else {
                model.openInLibrary(uuid)
            }
        }
    }

    // MARK: Main menu (needed for ⌘C / ⌘V in text fields and for ⌘, ⌘O ⌘Q while a window is key)

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Over Hush", action: #selector(showAbout), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: L10n.menuSettings, action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(withTitle: L10n.menuOpen, action: #selector(showLibrary), keyEquivalent: "o").target = self
        app.addItem(.separator())
        app.addItem(withTitle: L10n.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Bewerk")
        edit.addItem(withTitle: "Knip", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieer", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Plak", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecteer alles", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Venster")
        window.addItem(withTitle: "Sluit", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = window
        NSApp.windowsMenu = window

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: L10n.helpTitle, action: #selector(showHelp), keyEquivalent: "").target = self
        help.addItem(withTitle: L10n.storyMenu, action: #selector(showStory), keyEquivalent: "").target = self
        helpItem.submenu = help
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    @objc private func showAbout() { model.windows.showAbout(model: model) }
    @objc private func showSettings() { model.windows.showSettings(model: model) }
    @objc private func showLibrary() { model.openInLibrary(nil) }
    @objc private func showHelp() { model.windows.showHelp(model: model) }
    @objc private func showStory() { model.windows.showStory(model: model) }
}

import AppKit
import SwiftUI
import HushCore

/// Hosts every SwiftUI screen in an opaque dark NSWindow.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private var flowWindows: [UUID: NSWindow] = [:]
    private var forceClose: Set<UUID> = []
    private var library: NSWindow?
    private var settings: NSWindow?
    private var about: NSWindow?
    private var help: NSWindow?
    private var onboarding: NSWindow?
    private var story: NSWindow?
    private var afterStory: (() -> Void)?
    private var releaseNotes: NSWindow?
    private var afterReleaseNotes: (() -> Void)?
    private var keyHelp: NSWindow?
    let settingsTab = SettingsTabModel()

    private func makeWindow<V: View>(_ view: V, size: NSSize, title: String, resizable: Bool = false,
                                     minSize: NSSize? = nil, closable: Bool = true, miniaturizable: Bool = false,
                                     fullSizeContent: Bool = false) -> NSWindow {
        var mask: NSWindow.StyleMask = [.titled]
        if closable { mask.insert(.closable) }
        if miniaturizable { mask.insert(.miniaturizable) }
        if resizable { mask.insert(.resizable) }
        if fullSizeContent { mask.insert(.fullSizeContentView) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        let host = NSHostingController(rootView: view.preferredColorScheme(.dark))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(size)
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.backgroundNS
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let minSize { window.contentMinSize = minSize }
        if fullSizeContent {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        window.center()
        return window
    }

    /// Buttons that close their own window run it after the click has finished, so the window is not torn down inside its own event.
    private func afterClick(_ action: @escaping () -> Void) -> () -> Void {
        { DispatchQueue.main.async(execute: action) }
    }

    /// The last window of a first run or update is gone: show where Hush lives now.
    private func launchWindowsDone(_ model: AppModel) {
        guard model.pendingMenuBarHint else { return }
        model.pendingMenuBarHint = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak model] in model?.showMenuBarHint?() }
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Flow

    func showFlow(model: FlowModel, app: AppModel) {
        if let w = flowWindows[model.recording.id] { present(w); return }
        let w = makeWindow(FlowView(model: model), size: NSSize(width: 560, height: 520), title: L10n.flowWindow)
        flowWindows[model.recording.id] = w
        present(w)
    }

    func closeFlow(_ id: UUID, force: Bool = false) {
        if force { forceClose.insert(id) }
        flowWindows[id]?.close()
        flowWindows[id] = nil
        forceClose.remove(id)
    }

    // MARK: Library

    func showLibrary(model: AppModel) {
        if let w = library { present(w); return }
        let w = makeWindow(LibraryView().environmentObject(model), size: NSSize(width: 1100, height: 700), title: L10n.libTitle,
                           resizable: true, minSize: NSSize(width: 800, height: 500), miniaturizable: true, fullSizeContent: true)
        library = w
        present(w)
    }

    // MARK: Settings

    func showSettings(model: AppModel, tab: SettingsTab = .general) {
        settingsTab.tab = tab
        if let w = settings { present(w); return }
        let w = makeWindow(SettingsView(tabs: settingsTab).environmentObject(model),
                           size: NSSize(width: 640, height: 480), title: tab.title, miniaturizable: false)
        settings = w
        settingsTab.window = w
        present(w)
    }

    // MARK: About / Help / Onboarding

    func showAbout(model: AppModel) {
        if let w = about { present(w); return }
        let w = makeWindow(AboutView(), size: NSSize(width: 360, height: 440), title: "Over Hush")
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        about = w
        present(w)
    }

    func showHelp(model: AppModel) {
        if let w = help { present(w); return }
        let w = makeWindow(HelpView(onClose: afterClick { [weak self] in self?.help?.close() }).environmentObject(model),
                           size: NSSize(width: 560, height: 520), title: L10n.helpTitle)
        help = w
        present(w)
    }

    /// Asks for the permissions that are still missing; with nothing missing it goes straight on.
    func showOnboarding(model: AppModel, thenHelp: Bool = true) {
        if let w = onboarding { present(w); return }
        let steps = Permissions.missing(settings: model.settings)
        let finish: (AppModel) -> Void = { [weak self] model in
            model.settings.hasCompletedOnboarding = true
            self?.onboarding?.close()
            if thenHelp { self?.showHelp(model: model) } else { self?.launchWindowsDone(model) }
        }
        guard !steps.isEmpty else { finish(model); return }
        let w = makeWindow(OnboardingView(steps: steps, onFinish: afterClick { [weak model] in if let model { finish(model) } }).environmentObject(model), size: NSSize(width: 560, height: 520), title: L10n.flowWindow)
        onboarding = w
        present(w)
    }

    /// `thenOnboarding`: first launch. Onboarding follows however the story window is closed.
    /// `then`: runs once the story window is closed (after an update).
    func showStory(model: AppModel, thenOnboarding: Bool = false, then next: (() -> Void)? = nil) {
        if let w = story { present(w); return }
        if thenOnboarding { afterStory = { [weak self, weak model] in if let model { self?.showOnboarding(model: model) } } }
        else if let next { afterStory = next }
        let w = makeWindow(StoryView(buttonTitle: thenOnboarding ? L10n.storyStart : (next != nil ? L10n.flowNext : L10n.storyClose),
                                     onFinish: afterClick { [weak self] in self?.story?.close() }),
                           size: NSSize(width: 560, height: 600), title: L10n.storyMenu)
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        story = w
        present(w)
    }

    func showReleaseNotes(entries: [ReleaseEntry], then next: (() -> Void)? = nil) {
        if let w = releaseNotes { present(w); return }
        afterReleaseNotes = next
        let w = makeWindow(ReleaseNotesView(entries: entries, onFinish: afterClick { [weak self] in self?.releaseNotes?.close() }),
                           size: NSSize(width: 560, height: 520), title: L10n.releaseNotesWindow)
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        releaseNotes = w
        present(w)
    }

    func showKeyHelp(model: AppModel, provider: NotesProviderKind) {
        keyHelp?.close()
        let w = makeWindow(KeyHelpView(provider: provider, onClose: afterClick { [weak self] in self?.keyHelp?.close() }).environmentObject(model),
                           size: NSSize(width: 560, height: 520), title: L10n.keyHelpTitle(provider.displayName))
        keyHelp = w
        present(w)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing a flow window with the red button never deletes anything.
        true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // A button often closes its own window in the middle of its click. Keep the window and its SwiftUI views alive
        // until that event is finished instead of freeing them inside it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = window }
        if window === library { library = nil }
        if window === settings { settings = nil }
        if window === about { about = nil }
        if window === help {
            help = nil; AppModel.shared.settings.hasSeenHelp = true
            launchWindowsDone(AppModel.shared)
        }
        if window === onboarding { onboarding = nil }
        if window === keyHelp { keyHelp = nil }
        if window === releaseNotes {
            releaseNotes = nil
            let next = afterReleaseNotes; afterReleaseNotes = nil
            if let next { DispatchQueue.main.async { next() } }
        }
        if window === story {
            story = nil
            let next = afterStory; afterStory = nil
            // Open the follow-up window after this close has finished, not inside it.
            if let next { DispatchQueue.main.async { next() } }
        }
        if let id = flowWindows.first(where: { $0.value === window })?.key {
            flowWindows[id] = nil
            guard !forceClose.contains(id), let flow = AppModel.shared.flows[id] else { return }
            // Red button on a flow window: audio stays; the flow ends unless it is still transcribing in the background.
            if !flow.isBusy { AppModel.shared.flowFinished(id) }
        }
    }
}

@MainActor
final class SettingsTabModel: ObservableObject {
    @Published var tab: SettingsTab = .general { didSet { window?.title = tab.title } }
    weak var window: NSWindow?
}

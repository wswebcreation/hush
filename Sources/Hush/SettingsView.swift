import SwiftUI
import AppKit
import AVFoundation
import HushCore

enum SettingsTab: CaseIterable, Identifiable {
    case general, recording, storage, transcription, notes
    var id: Self { self }
    var title: String {
        switch self {
        case .general: L10n.setGeneral
        case .recording: L10n.setRecording
        case .storage: L10n.setStorage
        case .transcription: L10n.setTranscription
        case .notes: L10n.setNotes
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .recording: "mic"
        case .storage: "folder"
        case .transcription: "doc.text"
        case .notes: "text.alignleft"
        }
    }
}

/// Two-column form row: label right-aligned in a 136 px column.
struct FormRow<Content: View>: View {
    let label: String?
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label ?? "").font(Theme.body).foregroundStyle(Theme.textSecondary)
                .frame(width: 136, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) { content }
            Spacer(minLength: 0)
        }
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Theme.secondary).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tabs: SettingsTabModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    let selected = tabs.tab == tab
                    Button { tabs.tab = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon).font(.system(size: 18)).foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                            Text(tab.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        }
                        .frame(width: 88, height: 48)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.surfaceRaised : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 8)
            Divider1()
            Group {
                switch tabs.tab {
                case .general: GeneralSettings()
                case .recording: RecordingSettings()
                case .storage: StorageSettings()
                case .transcription: TranscriptionSettings()
                case .notes: NotesSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 640, height: tabs.tab == .notes ? 680 : 380)
        .background(Theme.background)
        .onChange(of: tabs.tab) { _, tab in
            guard let w = tabs.window else { return }
            let h: CGFloat = tab == .notes ? 680 : 380
            var frame = w.frame
            let newHeight = h + (frame.height - w.contentLayoutRect.height)
            frame.origin.y += frame.height - newHeight
            frame.size.height = newHeight
            w.setFrame(frame, display: true, animate: false)
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""
    @State private var launch = true
    @State private var dock = false
    @State private var recordingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormRow(label: L10n.setName) {
                TextField("", text: $name).textFieldStyle(HushTextFieldStyle()).frame(width: 240)
                    .onChange(of: name) { _, v in model.settings.userName = v }
                    .accessibilityLabel(L10n.setName)
                Hint(L10n.setNameHint)
            }
            Divider1()
            FormRow(label: L10n.setStartup) {
                HStack(spacing: 8) {
                    HushSwitch(isOn: $launch, label: L10n.setLaunchAtLogin)
                    Text(L10n.setLaunchAtLogin).font(Theme.body).foregroundStyle(Theme.textPrimary)
                }
            }
            FormRow(label: L10n.setDock) {
                HStack(spacing: 8) {
                    HushSwitch(isOn: $dock, label: L10n.setShowDock)
                    Text(L10n.setShowDock).font(Theme.body).foregroundStyle(Theme.textPrimary)
                }
            }
            Divider1()
            FormRow(label: L10n.setShortcut) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(recordingShortcut ? ["…"] : model.shortcut.keyCaps, id: \.self) { cap in
                            Text(cap).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                .frame(minWidth: 22).padding(.vertical, 3).padding(.horizontal, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceRaised))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sneltoets \(model.shortcut.display)")
                    Button(L10n.setChange) { recordingShortcut = true; ShortcutRecorder.shared.begin { s in
                        recordingShortcut = false
                        if let s { model.updateShortcut(s) }
                    } }.buttonStyle(SecondaryButtonStyle(height: 24))
                    Button(L10n.setReset) { model.updateShortcut(.default) }.buttonStyle(LinkButtonStyle())
                }
                Hint(L10n.setShortcutHint)
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .onAppear { name = model.settings.userName; launch = model.settings.launchAtLogin; dock = model.settings.showInDock }
        .onChange(of: launch) { _, v in model.settings.launchAtLogin = v; model.applyLaunchAtLogin() }
        .onChange(of: dock) { _, v in model.settings.showInDock = v; model.applyDockPolicy() }
    }
}

/// Captures the next key combination with at least one of ⌃ ⌥ ⌘.
@MainActor
final class ShortcutRecorder {
    static let shared = ShortcutRecorder()
    private var monitor: Any?

    func begin(_ completion: @escaping (Shortcut?) -> Void) {
        end()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.end(); completion(nil); return nil }
            var mods = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { mods |= Shortcut.cmdKey }
            if flags.contains(.option) { mods |= Shortcut.optionKey }
            if flags.contains(.control) { mods |= Shortcut.controlKey }
            if flags.contains(.shift) { mods |= Shortcut.shiftKey }
            let label = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            let shortcut = Shortcut(keyCode: Int(event.keyCode), modifiers: mods, keyLabel: label)
            guard shortcut.isValid else { NSSound.beep(); return nil }
            self?.end(); completion(shortcut)
            return nil
        }
    }
    func end() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}

// MARK: Recording

struct AccessRow: View {
    let label: String
    let allowed: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.body).foregroundStyle(Theme.textPrimary).frame(width: 100, alignment: .leading)
            if allowed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                Text(L10n.setAllowed).font(Theme.body).foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Button(L10n.setGrantAccess, action: action).buttonStyle(SecondaryButtonStyle(height: 24))
            }
        }
    }
}

struct RecordingSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var devices: [InputDevice] = []
    @State private var selected = ""
    @State private var systemAudio = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormRow(label: L10n.setMicrophone) {
                Picker("", selection: $selected) {
                    Text(L10n.setSystemDefault).tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                .labelsHidden().frame(width: 240)
                .accessibilityLabel(L10n.setMicrophone)
            }
            FormRow(label: L10n.setSystemAudio) {
                HStack(spacing: 8) {
                    HushSwitch(isOn: $systemAudio, label: L10n.setSystemAudioToggle)
                    Text(L10n.setSystemAudioToggle).font(Theme.body).foregroundStyle(Theme.textPrimary)
                }
            }
            Divider1()
            AudioTestRows(micUID: selected.isEmpty ? nil : selected, systemAudio: systemAudio)
            Divider1()
            FormRow(label: L10n.setAccess) {
                AccessRow(label: L10n.setMicrophone, allowed: model.micAllowed) {
                    Task { if !(await model.ensureMicAccess()) { Permissions.openPrivacy("Privacy_Microphone") } }
                }
                AccessRow(label: L10n.setSystemAudio, allowed: systemAudio && Permissions.systemAudioTested) {
                    Permissions.requestSystemAudio { model.objectWillChange.send() }
                }
                if !systemAudio { Hint(L10n.permSystemAudioOff) }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .onAppear {
            devices = AudioDevices.inputDevices()
            selected = model.settings.micDeviceUID ?? ""
            systemAudio = model.settings.captureSystemAudio
            model.refreshDiskAndPermissions()
        }
        .onChange(of: selected) { _, v in model.settings.micDeviceUID = v.isEmpty ? nil : v; model.refreshDiskAndPermissions() }
        .onChange(of: systemAudio) { _, v in model.settings.captureSystemAudio = v; model.objectWillChange.send() }
    }
}

// MARK: Storage

struct StorageSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var path = ""
    @State private var deleteAudio = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormRow(label: L10n.setFolder) {
                HStack(spacing: 8) {
                    Text(path).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceRaised))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                    Button(L10n.setChoose) { choose() }.buttonStyle(SecondaryButtonStyle(height: 24))
                    Button(L10n.setShow) {
                        try? FileManager.default.createDirectory(at: model.settings.recordingsFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(model.settings.recordingsFolder)
                    }.buttonStyle(SecondaryButtonStyle(height: 24))
                }
            }
            Divider1()
            FormRow(label: L10n.setAfterFinish) {
                HStack(spacing: 8) {
                    HushSwitch(isOn: $deleteAudio, label: L10n.setDeleteAudioDefault)
                    Text(L10n.setDeleteAudioDefault).font(Theme.body).foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .onAppear { path = model.displayPath; deleteAudio = model.settings.deleteAudioByDefault }
        .onChange(of: deleteAudio) { _, v in model.settings.deleteAudioByDefault = v }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = model.settings.recordingsFolder
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.recordingsFolder = url
            path = model.displayPath
            model.reloadRecordings()
        }
    }
}

// MARK: Transcription

struct TranscriptionSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var installed: Bool?
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var localeID = "nl_NL"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormRow(label: L10n.setEngine) {
                Text(L10n.setEngineValue).font(Theme.body).foregroundStyle(Theme.textPrimary)
            }
            FormRow(label: "Taal") {
                Picker("", selection: $localeID) {
                    Text("Nederlands").tag("nl_NL")
                    Text("English").tag("en_US")
                }
                .labelsHidden().frame(width: 240, alignment: .leading).padding(.leading, -8)
                .accessibilityLabel("Taal van de opname")
            }
            FormRow(label: L10n.setLanguages) {
                switch installed {
                case .some(true):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                        Text(L10n.setLanguagesInstalled).font(Theme.body).foregroundStyle(Theme.textPrimary)
                    }
                case .some(false):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                        Text(L10n.setLanguagesMissing).font(Theme.body).foregroundStyle(Theme.warning)
                        Button(L10n.setDownload) { download() }.buttonStyle(SecondaryButtonStyle(height: 24)).disabled(downloading)
                    }
                    if let downloadError { Hint(downloadError) }
                case .none:
                    Text("…").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .onAppear { localeID = model.settings.transcriptionLocaleID; Task { await refresh() } }
        .onChange(of: localeID) { _, v in model.settings.transcriptionLocaleID = v; Task { await refresh() } }
    }

    private func refresh() async {
        installed = await Transcriber.assetsInstalled(for: model.settings.transcriptionLocale)
    }

    private func download() {
        downloading = true
        Task {
            do { try await Transcriber.installAssets(for: model.settings.transcriptionLocale); downloadError = nil }
            catch { downloadError = error.localizedDescription }
            downloading = false
            await refresh()
        }
    }
}

// MARK: Notes

struct KeyField: View {
    @EnvironmentObject var model: AppModel
    let provider: NotesProviderKind
    let placeholder: String
    @State private var saved = false
    @State private var input = ""
    @State private var replacing = false
    @State private var testing = false
    @State private var result: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if saved && !replacing {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.success).font(.system(size: 11))
                        Text(L10n.setSavedInKeychain).font(Theme.body).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button(L10n.setReplace) { replacing = true }.buttonStyle(SecondaryButtonStyle(height: 22))
                    }
                    .padding(.horizontal, 8).frame(width: 300, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceRaised))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                } else {
                    SecureField(placeholder, text: $input).textFieldStyle(HushTextFieldStyle()).frame(width: 300)
                        .onSubmit(save)
                        .accessibilityLabel(provider == .claude ? L10n.setClaudeKey : L10n.setOpenAIKey)
                    if replacing || !input.isEmpty {
                        Button(L10n.setSave) { save() }.buttonStyle(SecondaryButtonStyle(height: 24)).disabled(input.isEmpty)
                    }
                }
                Button(L10n.setTest) { test() }.buttonStyle(SecondaryButtonStyle(height: 24)).disabled(!saved || testing)
            }
            Button(L10n.keyHelpLink) { model.windows.showKeyHelp(model: model, provider: provider) }.buttonStyle(LinkButtonStyle())
            if let result {
                HStack(spacing: 6) {
                    Image(systemName: result ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Text(result ? L10n.setKeyWorks : L10n.setKeyFails)
                }
                .font(Theme.secondary).foregroundStyle(result ? Theme.success : Theme.warning)
            }
        }
        .onAppear { saved = model.secrets.hasKey(for: provider) }
        .onReceive(NotificationCenter.default.publisher(for: .hushKeysChanged)) { _ in
            saved = model.secrets.hasKey(for: provider); replacing = false; input = ""
        }
    }

    private func save() {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        try? model.secrets.write(key, account: provider.keychainAccount)
        input = ""; replacing = false; saved = true; result = nil
    }

    private func test() {
        testing = true; result = nil
        let p = model.notesProvider(for: provider)
        Task {
            let ok = await p.testKey()
            result = ok; testing = false
        }
    }
}

struct NotesSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var claudeModel = ""
    @State private var openAIModel = ""
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                FormRow(label: L10n.setClaudeKey) { KeyField(provider: .claude, placeholder: L10n.setPasteClaudeKey) }
                FormRow(label: L10n.setClaudeModel) {
                    Picker("", selection: $claudeModel) {
                        Text(L10n.setDefaultModel).tag("")
                        ForEach(ClaudeProvider.knownModels, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 240).accessibilityLabel(L10n.setClaudeModel)
                }
                Divider1()
                FormRow(label: L10n.setOpenAIKey) { KeyField(provider: .openai, placeholder: L10n.setPasteOpenAIKey) }
                FormRow(label: L10n.setOpenAIModel) {
                    Picker("", selection: $openAIModel) {
                        Text(L10n.setDefaultModel).tag("")
                        ForEach(["gpt-5", "gpt-5-mini", "gpt-4.1"], id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 240).accessibilityLabel(L10n.setOpenAIModel)
                }
                Divider1()
                FormRow(label: L10n.setPrompt) {
                    TextEditor(text: $prompt)
                        .font(Theme.transcript).scrollContentBackground(.hidden)
                        .padding(6).frame(height: 184)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceRaised))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                        .accessibilityLabel(L10n.setPrompt)
                    HStack {
                        Hint(L10n.setVariables)
                        Spacer()
                        Button(L10n.setResetDefault) { prompt = PromptTemplate.defaultTemplate }.buttonStyle(SecondaryButtonStyle(height: 24))
                    }
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
            Spacer(minLength: 0)
            Divider1()
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text(L10n.setKeysFooter)
            }
            .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 32).frame(height: 36).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            claudeModel = model.settings.claudeModel; openAIModel = model.settings.openAIModel; prompt = model.settings.promptTemplate
        }
        .onChange(of: claudeModel) { _, v in model.settings.claudeModel = v }
        .onChange(of: openAIModel) { _, v in model.settings.openAIModel = v }
        .onChange(of: prompt) { _, v in model.settings.promptTemplate = v }
    }
}

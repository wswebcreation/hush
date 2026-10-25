import SwiftUI
import AppKit
import HushCore

struct KeyHelpView: View {
    @EnvironmentObject var model: AppModel
    let provider: NotesProviderKind
    var onClose: () -> Void

    enum Outcome { case none, invalid, saved(Bool) }
    @State private var outcome: Outcome = .none
    @State private var working = false

    private var steps: [String] {
        [L10n.keyHelpStep1(provider.keyPageHost), L10n.keyHelpStep2, L10n.keyHelpStep3, L10n.keyHelpStep4]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.keyHelpTitle(provider.displayName)).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(L10n.keyHelpIntro).font(Theme.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.badgeNotesText)
                                .frame(width: 24, height: 24).background(Circle().fill(Theme.badgeNotesBg)).accessibilityHidden(true)
                            Text(text).font(Theme.body).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text(L10n.keyHelpCost)
                }.font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                result
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40).padding(.top, 8)
            FlowFooter {
                Button(L10n.keyHelpOpen(provider.keyPageHost)) { NSWorkspace.shared.open(provider.keyPageURL) }
                    .buttonStyle(SecondaryButtonStyle())
            } trailing: {
                Button(L10n.keyHelpClose) { onClose() }.buttonStyle(SecondaryButtonStyle())
                Button(L10n.keyHelpPaste) { paste() }.buttonStyle(PrimaryButtonStyle()).disabled(working)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
    }

    @ViewBuilder private var result: some View {
        switch outcome {
        case .none: EmptyView()
        case .invalid: status(L10n.keyHelpNotAKey, ok: false)
        case .saved(let works):
            status(works ? "\(L10n.keyHelpSaved). \(L10n.setKeyWorks)." : "\(L10n.keyHelpSaved). \(L10n.setKeyFails)", ok: works)
        }
    }

    private func status(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(text)
        }.font(Theme.body).foregroundStyle(ok ? Theme.success : Theme.warning)
    }

    private func paste() {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        guard KeyFormat.looksValid(clip, for: provider) else { outcome = .invalid; return }
        working = true
        try? model.secrets.write(KeyFormat.clean(clip), account: provider.keychainAccount)
        NSPasteboard.general.clearContents()  // the key should not linger on the clipboard
        NotificationCenter.default.post(name: .hushKeysChanged, object: nil)
        let p = model.notesProvider(for: provider)
        Task {
            let ok = await p.testKey()
            outcome = .saved(ok); working = false
            if ok { try? await Task.sleep(for: .seconds(1.2)); onClose() }
        }
    }
}

extension Notification.Name { static let hushKeysChanged = Notification.Name("hushKeysChanged") }

import SwiftUI
import AppKit

/// Design tokens. Views never use raw hex.
enum Theme {
    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static func ns(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static let background = hex(0x111214)
    static let surface = hex(0x1A1B1E)
    static let surfaceRaised = hex(0x232428)
    static let border = hex(0x2E3035)
    static let textPrimary = hex(0xE8E9EB)
    static let textSecondary = hex(0x9A9DA3)
    static let textTertiary = hex(0xC4C7CC)
    static let accent = hex(0x5B8DEF)
    static let accentFill = hex(0x3A6BD4)
    static let recording = hex(0xE5484D)
    static let success = hex(0x3FB950)
    static let warning = hex(0xD29922)
    static let warningSurface = hex(0x241E12)
    static let warningBorder = hex(0x4A3B1A)
    static let badgeNotesBg = hex(0x1E2A44)
    static let badgeNotesText = hex(0x7FA6F3)
    static let badgeNeutralBg = hex(0x26282C)
    static let badgeWarningBg = hex(0x2A2312)
    static let disabledText = hex(0x6B6E74)
    static let deletedIcon = hex(0x7A7D84)
    static let selectedDuration = hex(0xDCE5F8)

    static let backgroundNS = ns(0x111214)
    static let surfaceNS = ns(0x1A1B1E)

    // Typography
    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodySemibold = Font.system(size: 13, weight: .semibold)
    static let secondary = Font.system(size: 11)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let transcript = Font.system(size: 12, design: .monospaced)
    static let timer = Font.system(size: 32, weight: .medium, design: .monospaced).monospacedDigit()
}

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodySemibold)
            .foregroundStyle(enabled ? Color.white : Theme.disabledText)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(enabled ? Theme.accentFill : Theme.surfaceRaised))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body)
            .foregroundStyle(enabled ? Theme.textPrimary : Theme.disabledText)
            .padding(.horizontal, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodySemibold)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.recording, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.secondary).foregroundStyle(Theme.accent).opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct Divider1: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

struct WarningBanner: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.bodySemibold).foregroundStyle(Theme.warning)
                if let detail { Text(detail).font(Theme.body).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.warningSurface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.warningBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct Badge: View {
    enum Style { case notes, neutral, warning }
    let text: String
    let style: Style
    var body: some View {
        HStack(spacing: 3) {
            if style == .warning { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(bg))
    }
    private var fg: Color { switch style { case .notes: Theme.badgeNotesText; case .neutral: Theme.textTertiary; case .warning: Theme.warning } }
    private var bg: Color { switch style { case .notes: Theme.badgeNotesBg; case .neutral: Theme.badgeNeutralBg; case .warning: Theme.badgeWarningBg } }
}

/// Custom switch (32 × 18) so the on track uses accentFill.
struct HushSwitch: View {
    @Binding var isOn: Bool
    var label: String
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.accentFill : Theme.border).frame(width: 32, height: 18)
                Circle().fill(isOn ? Color.white : Theme.textSecondary).frame(width: 14, height: 14).padding(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Aan" : "Uit")
        .accessibilityAddTraits(.isToggle)
    }
}

struct HushTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Theme.body).foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }
}

/// Opaque window background; never a material.
struct WindowBackground: View {
    var color: Color = Theme.background
    var body: some View { color.ignoresSafeArea() }
}

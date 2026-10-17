import SwiftUI

enum SettingsPalette {
    static let background = Color(nsColor: .adaptive(0xfafafa, 0x141416))
    static let sidebar = Color(nsColor: .adaptive(0xf6f6f7, 0x18181b))
    static let card = Color(nsColor: .adaptive(0xffffff, 0x1c1c1e))
    static let control = Color(nsColor: .adaptive(0xffffff, 0x242426))
    static let hover = Color(nsColor: .adaptive(0xf4f4f5, 0x2c2c30))
    static let border = Color(nsColor: .adaptive(0xe7e7ea, 0x343438))
    static let secondary = Color(nsColor: .adaptive(0x737378, 0xa1a1aa))
    static let focus = Color(nsColor: .adaptive(0x0060e2, 0x4d8dff))
    static let shadow = Color.black.opacity(0.04)
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SettingsPalette.border, lineWidth: 0.5))
            .shadow(color: SettingsPalette.shadow, radius: 2, y: 1)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(SettingsPalette.border).frame(height: 0.5)
    }
}

struct SettingsNavigationStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? Theme.text : SettingsPalette.secondary)
            .padding(.horizontal, 12).frame(height: 38)
            .background(selected ? SettingsPalette.card : hovering || configuration.isPressed ? SettingsPalette.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? SettingsPalette.border : .clear, lineWidth: 0.5))
            .shadow(color: selected ? SettingsPalette.shadow : .clear, radius: 2, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

struct GlintToggle: View {
    let title: String
    var detail = ""
    var symbol: String? = nil
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(SettingsPalette.secondary)
                    .frame(width: 30, height: 30).background(SettingsPalette.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsPalette.border, lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Theme.text).controlSize(.small)
        }.frame(minHeight: 36).opacity(enabled ? 1 : 0.4)
    }
}

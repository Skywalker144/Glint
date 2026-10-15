import SwiftUI

struct ControlSurface: ViewModifier {
    var active = false
    var hovering = false
    var radius: CGFloat = 7
    @ViewState<Bool> private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(hovering || hovered ? Theme.hover : Theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(active ? Theme.text.opacity(0.55) : Theme.border, lineWidth: 1))
            .onHover { hovered = $0 }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .modifier(ControlSurface(hovering: configuration.isPressed))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct SettingsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration.textFieldStyle(.plain).modifier(FieldSurface())
    }
}

struct FieldSurface: ViewModifier {
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .modifier(ControlSurface(active: focused))
            .opacity(enabled ? 1 : 0.4)
    }
}

struct ChoiceMenu<Value: Hashable, Options: View>: View {
    let title: String
    let value: String
    @Binding var selection: Value
    var compact = false
    @ViewBuilder var options: Options
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options }.pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: compact ? 4 : 8) {
                Text(value).lineLimit(1)
                if !compact { Spacer(minLength: 0) }
                Image(systemName: "chevron.down").font(.system(size: compact ? 8 : 9, weight: .semibold)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .font(.system(size: 12, weight: compact ? .regular : .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, compact ? 7 : 10)
            .frame(height: compact ? 24 : 30)
            .modifier(ControlSurface(radius: compact ? 6 : 7))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize(horizontal: compact, vertical: true)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title).accessibilityValue(value)
    }
}

struct ModelPicker: View {
    @Binding var value: String
    let items: [String]
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("模型名", text: $value).textFieldStyle(.plain).focused($focused)
                .padding(.leading, 10).accessibilityLabel("模型")
            Menu {
                ForEach(items, id: \.self) { item in
                    Button(item) { value = item }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted).frame(width: 28, height: 30)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(items.isEmpty).accessibilityLabel("选择模型")
        }
        .font(.system(size: 12)).frame(height: 30)
        .modifier(ControlSurface(active: focused))
    }
}

struct PromptEditor: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text).font(.system(size: 12)).scrollContentBackground(.hidden)
            .focused($focused).padding(8).frame(height: 154)
            .modifier(ControlSurface(active: focused, radius: 9))
            .accessibilityLabel(title)
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 12)
            accessory
        }.frame(minHeight: 30)
    }
}

struct PermissionBadge: View {
    let granted: Bool

    var body: some View {
        Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "circle.dashed")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(granted ? Theme.text : Theme.muted)
            .padding(.horizontal, 8).padding(.vertical, 5).background(Theme.surface, in: Capsule())
    }
}

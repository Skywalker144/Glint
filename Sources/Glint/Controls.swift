import SwiftUI
import AppKit

struct NavigationSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let moveSelection: (Int) -> Void
    final class SearchField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { window.makeFirstResponder(self) } }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SearchField {
        let view = SearchField()
        view.isBordered = false; view.drawsBackground = false; view.focusRingType = .none
        view.font = .systemFont(ofSize: 12); view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: SearchField, context: Context) {
        context.coordinator.parent = self; view.placeholderString = placeholder
        if view.stringValue != text { view.stringValue = text }
        view.setAccessibilityLabel(placeholder)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NavigationSearchField
        init(_ parent: NavigationSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveDown(_:)) { parent.moveSelection(1); return true }
            if commandSelector == #selector(NSResponder.moveUp(_:)) { parent.moveSelection(-1); return true }
            return false
        }
    }
}

struct CopyButton: View {
    let title: String
    let text: String
    @ViewState<Int> private var copyRevision = 0
    @ViewState<Bool> private var copied = false
    var body: some View {
        Button { AppModel.copy(text); copied = true; copyRevision += 1 } label: {
            ZStack {
                Text(title).opacity(copied ? 0 : 1)
                Text("已复制").opacity(copied ? 1 : 0)
            }
        }
            .buttonStyle(GlintButtonStyle()).font(.system(size: 12))
            .accessibilityLabel(copied ? "已复制" : title)
            .task(id: copyRevision) {
                guard copyRevision > 0 else { return }
                do { try await Task.sleep(for: .seconds(1.2)); copied = false } catch {}
            }
            .onChange(of: text) { _, _ in copied = false }
    }
}

struct ControlSurface: ViewModifier {
    var active = false
    var hovering = false
    var radius: CGFloat = 7
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Bool> private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(hovering || hovered ? (compact ? Theme.hover : SettingsPalette.hover) : (compact ? Theme.surface : SettingsPalette.control), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(active ? SettingsPalette.focus.opacity(0.6) : (compact ? Theme.border : SettingsPalette.border), lineWidth: compact ? 1 : 0.5))
            .shadow(color: active ? SettingsPalette.focus.opacity(0.12) : .clear, radius: 3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: active)
            .onHover { hovered = $0 }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.role == .destructive ? Color(nsColor: .systemRed) : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .modifier(ControlSurface(hovering: configuration.isPressed))
            .shadow(color: SettingsPalette.shadow, radius: 1, y: 1)
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
            .frame(height: 32)
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
            .frame(height: compact ? 24 : 32)
            .modifier(ControlSurface(radius: compact ? 6 : 7, compact: compact))
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
                    .foregroundStyle(Theme.muted).frame(width: 28, height: 32)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(items.isEmpty).accessibilityLabel("选择模型")
        }
        .font(.system(size: 12)).frame(height: 32)
        .modifier(ControlSurface(active: focused))
    }
}

struct PromptEditor: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        TextEditor(text: $text).font(.system(size: 12)).scrollContentBackground(.hidden)
            .focused($focused).padding(8).frame(height: 154)
            .modifier(ControlSurface(active: focused, radius: 9))
            .opacity(enabled ? 1 : 0.4)
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
        }.frame(minHeight: 36)
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

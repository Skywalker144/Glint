import AppKit

@MainActor
final class SelectionMenuHost: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
    var monitor: Any?
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 8 && event.modifierFlags.contains(.command) {
                try? Data("copy shortcut".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            }
            return event
        }
        let menu = NSMenu()
        let application = NSMenuItem(title: "Selection Host", action: nil, keyEquivalent: "")
        application.submenu = NSMenu()
        application.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(application)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let items = NSMenu()
        items.autoenablesItems = false
        let style = NSMenuItem(title: "Copy Style", action: #selector(copyStyle), keyEquivalent: "c")
        style.keyEquivalentModifierMask = [.command, .shift]
        style.target = self
        items.addItem(style)
        let copy = NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copy.target = editor
        if CommandLine.arguments.contains("identifier") {
            copy.identifier = .init("copy:")
            copy.keyEquivalent = "x"
            copy.keyEquivalentModifierMask = [.command, .shift]
        }
        items.addItem(copy)
        edit.submenu = items
        menu.addItem(edit)
        NSApp.mainMenu = menu
        editor.isRichText = false
        editor.string = "First line\nSecond line\n\nThird paragraph\n\tIndented line"
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
            print("ready")
            fflush(stdout)
        }
    }

    @objc func copyStyle() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Incorrect Copy Style action", forType: .string)
    }
}

@main
@MainActor
enum SelectionMenuHostMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = SelectionMenuHost()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

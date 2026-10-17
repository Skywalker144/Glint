import AppKit

@MainActor
final class SelectionMenuDriver: NSObject, NSApplicationDelegate {
    let hotkeys = HotkeyManager()
    let selection = SelectionService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try hotkeys.register(["selection": "Control+Shift+Y"])
            hotkeys.onTrigger = { [self] _ in
                Task {
                    do {
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == Int32(CommandLine.arguments[2]) else {
                            try Data("Unexpected source application".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                            NSApp.terminate(nil)
                            return
                        }
                        let text = try await selection.selectedText()
                        try Data(text.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                    } catch {
                        try? Data(error.localizedDescription.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                    }
                    NSApp.terminate(nil)
                }
            }
            print("ready")
            fflush(stdout)
        } catch {
            print(error.localizedDescription)
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}

@main
@MainActor
enum SelectionMenuDriverMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = SelectionMenuDriver()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

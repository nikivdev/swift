import AppKit
import Launcher

class AppDelegate: NSObject, NSApplicationDelegate {
    var placeholder: String = "Search..."

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate after launch
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            let result = await Launcher.shared.show(placeholder: placeholder)

            // Output as simple key: value for parsing
            print("action: \(result.action.rawValue)")
            print("query: \(result.query ?? "(none)")")

            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegate.placeholder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Search..."
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

import AppKit
import Launcher

class AppDelegate: NSObject, NSApplicationDelegate {
    var placeholder: String = "Search..."
    var items: [LauncherItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            let result = await Launcher.shared.show(placeholder: placeholder, items: items)

            // Output as JSON for easy parsing
            var output: [String: Any] = [
                "action": result.action.rawValue,
                "query": result.query ?? NSNull()
            ]

            if let item = result.selectedItem {
                var itemDict: [String: Any] = [
                    "id": item.id,
                    "title": item.title
                ]
                if let subtitle = item.subtitle {
                    itemDict["subtitle"] = subtitle
                }
                if let icon = item.icon {
                    itemDict["icon"] = icon
                }
                output["selectedItem"] = itemDict
            }

            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }

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

        // Parse arguments
        let args = CommandLine.arguments.dropFirst()

        if args.isEmpty {
            delegate.placeholder = "Search..."
        } else {
            // First arg is placeholder (or --items for JSON input)
            let firstArg = args.first ?? ""

            if firstArg == "--items" || firstArg == "-i" {
                // Read JSON items from stdin
                delegate.placeholder = args.dropFirst().first ?? "Search..."
                delegate.items = readItemsFromStdin()
            } else if firstArg == "--json" || firstArg == "-j" {
                // Read full config from stdin as JSON
                if let config = readConfigFromStdin() {
                    delegate.placeholder = config.placeholder
                    delegate.items = config.items
                }
            } else {
                delegate.placeholder = firstArg

                // Check if there's a second argument with JSON items
                if args.count > 1 {
                    let secondArg = args.dropFirst().first ?? ""
                    if let data = secondArg.data(using: .utf8),
                       let items = try? JSONDecoder().decode([LauncherItem].self, from: data) {
                        delegate.items = items
                    }
                }
            }
        }

        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    static func readItemsFromStdin() -> [LauncherItem] {
        var input = ""
        while let line = readLine() {
            input += line
        }

        guard let data = input.data(using: .utf8),
              let items = try? JSONDecoder().decode([LauncherItem].self, from: data) else {
            return []
        }
        return items
    }

    static func readConfigFromStdin() -> LauncherConfig? {
        var input = ""
        while let line = readLine() {
            input += line
        }

        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let placeholder = json["placeholder"] as? String ?? "Search..."
        var items: [LauncherItem] = []

        if let itemsData = json["items"],
           let itemsJson = try? JSONSerialization.data(withJSONObject: itemsData),
           let decoded = try? JSONDecoder().decode([LauncherItem].self, from: itemsJson) {
            items = decoded
        }

        return LauncherConfig(placeholder: placeholder, items: items)
    }
}

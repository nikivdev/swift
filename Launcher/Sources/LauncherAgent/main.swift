import AppKit
import Carbon.HIToolbox
import Launcher

class LauncherAgent: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - run as background agent
        NSApp.setActivationPolicy(.accessory)

        // Create menu bar icon (optional - can be hidden)
        setupMenuBar()

        // Register global hotkey: Cmd+Shift+Space
        registerHotKey()

        print("[LauncherAgent] Running. Press Cmd+Shift+Space to show launcher.")
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "◎"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Launcher", action: #selector(showLauncher), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    func registerHotKey() {
        // Cmd+Shift+Space
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 49 // Space

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4C4E4348) // "LNCH"
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        // Install handler
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                // Get the app delegate and trigger launcher
                if let delegate = NSApp.delegate as? LauncherAgent {
                    DispatchQueue.main.async {
                        delegate.showLauncher()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        // Register the hotkey
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print("[LauncherAgent] Failed to register hotkey: \(status)")
        } else {
            print("[LauncherAgent] Hotkey registered: Cmd+Shift+Space")
        }
    }

    @objc func showLauncher() {
        print("[LauncherAgent] Showing launcher...")

        Task { @MainActor in
            let result = await Launcher.shared.show(placeholder: "Switch server...")
            print("[LauncherAgent] Result: \(result.action.rawValue) - \(result.query ?? "(none)")")

            // If submitted, could send to 1f via local HTTP or file
            if result.action == .submitted, let query = result.query {
                handleResult(query: query, action: result.action)
            }
        }
    }

    func handleResult(query: String, action: LauncherAction) {
        // Write result to a file that 1f can watch, or send via local HTTP
        let resultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".1focus-launcher-result")

        let data = "\(action.rawValue):\(query)"
        try? data.write(to: resultPath, atomically: true, encoding: .utf8)

        // Post distributed notification that 1f can listen to
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.1focus.launcher.result"),
            object: nil,
            userInfo: ["action": action.rawValue, "query": query],
            deliverImmediately: true
        )
    }

    @objc func quit() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        NSApp.terminate(nil)
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = LauncherAgent()
app.delegate = delegate
app.run()

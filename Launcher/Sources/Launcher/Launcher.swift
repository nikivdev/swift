import AppKit
import Foundation

/// Result action from the launcher
public enum LauncherAction: String, Sendable {
    case dismissed
    case submitted       // Return
    case command         // Cmd+Return
    case option          // Option+Return
}

/// Result from showing the launcher
public struct LauncherResult: Sendable {
    public let action: LauncherAction
    public let query: String?

    public init(action: LauncherAction, query: String?) {
        self.action = action
        self.query = query
    }
}

/// Configuration for the launcher appearance
public struct LauncherConfig: Sendable {
    public var placeholder: String
    public var width: CGFloat
    public var cornerRadius: CGFloat
    public var fontSize: CGFloat
    public var verticalOffset: CGFloat

    public init(
        placeholder: String = "Search...",
        width: CGFloat = 640,
        cornerRadius: CGFloat = 12,
        fontSize: CGFloat = 18,
        verticalOffset: CGFloat = 140
    ) {
        self.placeholder = placeholder
        self.width = width
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
        self.verticalOffset = verticalOffset
    }

    public static let `default` = LauncherConfig()
}

/// A Raycast-style search launcher
@MainActor
public final class Launcher {

    public static let shared = Launcher()

    private var window: LauncherWindow?
    private var textField: LauncherTextField?
    private var continuation: CheckedContinuation<LauncherResult, Never>?
    private var previousApp: NSRunningApplication?
    private var escapeMonitor: Any?
    private var escapeMonitorLocal: Any?
    private var config: LauncherConfig = .default

    private init() {}

    /// Show the launcher and wait for result
    public func show(config: LauncherConfig = .default) async -> LauncherResult {
        self.config = config

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.showWindow()
        }
    }

    /// Show with just a placeholder string
    public func show(placeholder: String) async -> LauncherResult {
        await show(config: LauncherConfig(placeholder: placeholder))
    }

    /// Hide the launcher programmatically
    public func hide() {
        dismiss(result: LauncherResult(action: .dismissed, query: nil))
    }

    /// Check if launcher is currently visible
    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - Private

    private func showWindow() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if window == nil {
            createWindow()
        }

        guard let window = window, let screen = NSScreen.main else { return }

        textField?.placeholderString = config.placeholder
        textField?.stringValue = ""

        let height: CGFloat = 56
        let x = (screen.frame.width - config.width) / 2
        let y = (screen.frame.height - height) / 2 + config.verticalOffset
        window.setFrame(NSRect(x: x, y: y, width: config.width, height: height), display: true)

        // Activate app first
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Show window
        window.makeKeyAndOrderFront(nil)

        // Multiple attempts to focus with increasing delays
        for delay in [0.05, 0.15, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, let tf = self.textField, let win = self.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                win.makeKey()
                win.makeFirstResponder(tf)
            }
        }

        registerEscapeMonitor()
    }

    private func dismiss(result: LauncherResult) {
        guard let window = window, window.isVisible else { return }

        window.orderOut(nil)
        unregisterEscapeMonitor()

        // Restore previous app
        if let prev = previousApp,
           prev.processIdentifier != NSRunningApplication.current.processIdentifier {
            if #available(macOS 14, *) {
                prev.activate(options: [])
            } else {
                prev.activate(options: [.activateIgnoringOtherApps])
            }
        }
        previousApp = nil

        let cont = continuation
        continuation = nil
        cont?.resume(returning: result)
    }

    private func submit(action: LauncherAction) {
        let query = textField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let q = query, !q.isEmpty else {
            dismiss(result: LauncherResult(action: .dismissed, query: nil))
            return
        }
        dismiss(result: LauncherResult(action: action, query: q))
    }

    private func createWindow() {
        let window = LauncherWindow(
            contentRect: NSRect(x: 0, y: 0, width: config.width, height: 56),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Visual effect background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = config.cornerRadius
        visualEffect.layer?.masksToBounds = true

        // Text field
        let field = LauncherTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: config.fontSize, weight: .regular)
        field.textColor = .labelColor
        field.translatesAutoresizingMaskIntoConstraints = false

        field.onSubmit = { [weak self] in
            self?.submit(action: .submitted)
        }
        field.onCommandReturn = { [weak self] in
            self?.submit(action: .command)
        }
        field.onOptionReturn = { [weak self] in
            self?.submit(action: .option)
        }
        field.onEscape = { [weak self] in
            self?.dismiss(result: LauncherResult(action: .dismissed, query: nil))
        }

        visualEffect.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -20),
            field.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor)
        ])

        window.contentView = visualEffect
        self.window = window
        self.textField = field
    }

    private func registerEscapeMonitor() {
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    DispatchQueue.main.async {
                        self?.dismiss(result: LauncherResult(action: .dismissed, query: nil))
                    }
                }
            }
        }

        if escapeMonitorLocal == nil {
            escapeMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    DispatchQueue.main.async {
                        self?.dismiss(result: LauncherResult(action: .dismissed, query: nil))
                    }
                    return nil
                }
                return event
            }
        }
    }

    private func unregisterEscapeMonitor() {
        if let m = escapeMonitor {
            NSEvent.removeMonitor(m)
            escapeMonitor = nil
        }
        if let m = escapeMonitorLocal {
            NSEvent.removeMonitor(m)
            escapeMonitorLocal = nil
        }
    }
}

// MARK: - Window

private final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - TextField

private final class LauncherTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onCommandReturn: (() -> Void)?
    var onOptionReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76

        if isReturn {
            if flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control) {
                onCommandReturn?()
                return true
            }
            if flags.contains(.option) && !flags.contains(.command) {
                onOptionReturn?()
                return true
            }
        }

        // Standard shortcuts
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a":
                NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: self)
                return true
            case "c":
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
                return true
            case "x":
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
                return true
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
                return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onEscape?()
        case 36, 76: // Return
            let flags = event.modifierFlags
            if flags.contains(.command) || flags.contains(.option) {
                return
            }
            onSubmit?()
        default:
            super.keyDown(with: event)
        }
    }
}

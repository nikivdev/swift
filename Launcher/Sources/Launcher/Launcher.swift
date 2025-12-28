import AppKit
import Foundation

// MARK: - Public Types

/// A single item in the launcher results
public struct LauncherItem: Codable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String?  // SF Symbol name or emoji

    public init(id: String, title: String, subtitle: String? = nil, icon: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }
}

/// Result action from the launcher
public enum LauncherAction: String, Sendable {
    case dismissed
    case submitted       // Return - selected item or typed query
    case command         // Cmd+Return
    case option          // Option+Return
}

/// Result from showing the launcher
public struct LauncherResult: Sendable {
    public let action: LauncherAction
    public let query: String?
    public let selectedItem: LauncherItem?

    public init(action: LauncherAction, query: String?, selectedItem: LauncherItem? = nil) {
        self.action = action
        self.query = query
        self.selectedItem = selectedItem
    }
}

/// Configuration for the launcher appearance
public struct LauncherConfig: Sendable {
    public var placeholder: String
    public var width: CGFloat
    public var cornerRadius: CGFloat
    public var fontSize: CGFloat
    public var verticalOffset: CGFloat
    public var maxVisibleItems: Int
    public var itemHeight: CGFloat
    public var items: [LauncherItem]

    public init(
        placeholder: String = "Search...",
        width: CGFloat = 640,
        cornerRadius: CGFloat = 12,
        fontSize: CGFloat = 18,
        verticalOffset: CGFloat = 140,
        maxVisibleItems: Int = 8,
        itemHeight: CGFloat = 44,
        items: [LauncherItem] = []
    ) {
        self.placeholder = placeholder
        self.width = width
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
        self.verticalOffset = verticalOffset
        self.maxVisibleItems = maxVisibleItems
        self.itemHeight = itemHeight
        self.items = items
    }

    public static let `default` = LauncherConfig()
}

// MARK: - Fuzzy Search

private func fuzzyMatch(_ query: String, in text: String) -> (matches: Bool, score: Int) {
    guard !query.isEmpty else { return (true, 0) }

    let query = query.lowercased()
    let text = text.lowercased()

    // Exact prefix match gets highest score
    if text.hasPrefix(query) {
        return (true, 1000 + (100 - text.count))
    }

    // Contains match
    if text.contains(query) {
        return (true, 500 + (100 - text.count))
    }

    // Fuzzy character match
    var queryIndex = query.startIndex
    var score = 0
    var consecutiveBonus = 0

    for char in text {
        if queryIndex < query.endIndex && char == query[queryIndex] {
            score += 10 + consecutiveBonus
            consecutiveBonus += 5
            queryIndex = query.index(after: queryIndex)
        } else {
            consecutiveBonus = 0
        }
    }

    let matched = queryIndex == query.endIndex
    return (matched, matched ? score : 0)
}

// MARK: - Launcher

/// A Raycast-style search launcher with results list
@MainActor
public final class Launcher {

    public static let shared = Launcher()

    private var window: LauncherWindow?
    private var textField: LauncherTextField?
    private var resultsView: ResultsListView?
    private var continuation: CheckedContinuation<LauncherResult, Never>?
    private var previousApp: NSRunningApplication?
    private var escapeMonitor: Any?
    private var escapeMonitorLocal: Any?
    private var config: LauncherConfig = .default
    private var filteredItems: [LauncherItem] = []
    private var selectedIndex: Int = 0

    private init() {}

    /// Show the launcher and wait for result
    public func show(config: LauncherConfig = .default) async -> LauncherResult {
        self.config = config
        self.filteredItems = config.items
        self.selectedIndex = 0

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.showWindow()
        }
    }

    /// Show with just a placeholder string
    public func show(placeholder: String) async -> LauncherResult {
        await show(config: LauncherConfig(placeholder: placeholder))
    }

    /// Show with placeholder and items
    public func show(placeholder: String, items: [LauncherItem]) async -> LauncherResult {
        await show(config: LauncherConfig(placeholder: placeholder, items: items))
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

        // Update results
        updateFilteredItems(query: "")
        resultsView?.reloadData()

        // Calculate height based on items
        let inputHeight: CGFloat = 56
        let resultsHeight = CGFloat(min(filteredItems.count, config.maxVisibleItems)) * config.itemHeight
        let totalHeight = inputHeight + (filteredItems.isEmpty ? 0 : resultsHeight + 1) // +1 for separator

        let x = (screen.frame.width - config.width) / 2
        let y = (screen.frame.height - totalHeight) / 2 + config.verticalOffset
        window.setFrame(NSRect(x: x, y: y, width: config.width, height: totalHeight), display: true)

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

    private func updateWindowHeight() {
        guard let window = window, NSScreen.main != nil else { return }

        let inputHeight: CGFloat = 56
        let resultsHeight = CGFloat(min(filteredItems.count, config.maxVisibleItems)) * config.itemHeight
        let totalHeight = inputHeight + (filteredItems.isEmpty ? 0 : resultsHeight + 1)

        let currentFrame = window.frame
        let newY = currentFrame.origin.y + currentFrame.height - totalHeight
        window.setFrame(NSRect(x: currentFrame.origin.x, y: newY, width: config.width, height: totalHeight), display: true)
    }

    private func updateFilteredItems(query: String) {
        if query.isEmpty {
            filteredItems = config.items
        } else {
            // Score and filter items
            let scored = config.items.compactMap { item -> (item: LauncherItem, score: Int)? in
                let titleMatch = fuzzyMatch(query, in: item.title)
                let subtitleMatch: (matches: Bool, score: Int)
                if let subtitle = item.subtitle {
                    subtitleMatch = fuzzyMatch(query, in: subtitle)
                } else {
                    subtitleMatch = (matches: false, score: 0)
                }

                let bestScore = max(titleMatch.score, subtitleMatch.score)
                if titleMatch.matches || subtitleMatch.matches {
                    return (item, bestScore)
                }
                return nil
            }

            filteredItems = scored.sorted { $0.score > $1.score }.map { $0.item }
        }

        // Reset selection
        selectedIndex = filteredItems.isEmpty ? -1 : 0
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

        // If we have a selected item, return it
        if selectedIndex >= 0 && selectedIndex < filteredItems.count {
            let item = filteredItems[selectedIndex]
            dismiss(result: LauncherResult(action: action, query: query, selectedItem: item))
            return
        }

        // Otherwise return just the query (if not empty)
        guard let q = query, !q.isEmpty else {
            dismiss(result: LauncherResult(action: .dismissed, query: nil))
            return
        }
        dismiss(result: LauncherResult(action: action, query: q))
    }

    private func moveSelection(by delta: Int) {
        guard !filteredItems.isEmpty else { return }

        selectedIndex = (selectedIndex + delta + filteredItems.count) % filteredItems.count
        resultsView?.updateSelection(selectedIndex)
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

        // Main container
        let container = NSView()
        container.wantsLayer = true

        // Visual effect background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = config.cornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(visualEffect)

        // Input container
        let inputContainer = NSView()
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(inputContainer)

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
        field.onArrowUp = { [weak self] in
            self?.moveSelection(by: -1)
        }
        field.onArrowDown = { [weak self] in
            self?.moveSelection(by: 1)
        }
        field.onTextChange = { [weak self] text in
            self?.handleTextChange(text)
        }

        inputContainer.addSubview(field)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(separator)

        // Results list
        let resultsView = ResultsListView(itemHeight: config.itemHeight)
        resultsView.translatesAutoresizingMaskIntoConstraints = false
        resultsView.onItemSelected = { [weak self] index in
            self?.selectedIndex = index
            self?.submit(action: .submitted)
        }
        visualEffect.addSubview(resultsView)

        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            inputContainer.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            inputContainer.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 56),

            field.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -20),
            field.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),

            separator.topAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),

            resultsView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            resultsView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            resultsView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            resultsView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        window.contentView = container
        self.window = window
        self.textField = field
        self.resultsView = resultsView
    }

    private func handleTextChange(_ text: String) {
        updateFilteredItems(query: text)
        resultsView?.items = filteredItems
        resultsView?.updateSelection(selectedIndex)
        updateWindowHeight()
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

private final class LauncherTextField: NSTextField, NSTextFieldDelegate {
    var onSubmit: (() -> Void)?
    var onCommandReturn: (() -> Void)?
    var onOptionReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onTextChange: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.delegate = self
    }

    func controlTextDidChange(_ obj: Notification) {
        onTextChange?(stringValue)
    }

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
        case 125: // Down arrow
            onArrowDown?()
        case 126: // Up arrow
            onArrowUp?()
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Results List View

private final class ResultsListView: NSView {
    var items: [LauncherItem] = [] {
        didSet { reloadData() }
    }
    var onItemSelected: ((Int) -> Void)?

    private let itemHeight: CGFloat
    private var itemViews: [ResultItemView] = []
    private var selectedIndex: Int = 0

    init(itemHeight: CGFloat) {
        self.itemHeight = itemHeight
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func reloadData() {
        // Remove old views
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()

        // Create new views
        for (index, item) in items.prefix(8).enumerated() {
            let view = ResultItemView(item: item, height: itemHeight)
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isSelected = index == selectedIndex

            view.onClick = { [weak self] in
                self?.onItemSelected?(index)
            }

            addSubview(view)
            itemViews.append(view)

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor, constant: CGFloat(index) * itemHeight),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.heightAnchor.constraint(equalToConstant: itemHeight),
            ])
        }
    }

    func updateSelection(_ index: Int) {
        selectedIndex = index
        for (i, view) in itemViews.enumerated() {
            view.isSelected = i == index
        }
    }
}

// MARK: - Result Item View

private final class ResultItemView: NSView {
    var onClick: (() -> Void)?

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    private let item: LauncherItem
    private let height: CGFloat
    private let backgroundView = NSView()
    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(item: LauncherItem, height: CGFloat) {
        self.item = item
        self.height = height
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupViews() {
        // Background for selection
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 6
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        // Icon (emoji or SF Symbol)
        iconLabel.font = .systemFont(ofSize: 20)
        iconLabel.textColor = .labelColor
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        if let icon = item.icon {
            if let sfImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                let attachment = NSTextAttachment()
                attachment.image = sfImage.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
                iconLabel.attributedStringValue = NSAttributedString(attachment: attachment)
            } else {
                iconLabel.stringValue = icon
            }
        } else {
            iconLabel.stringValue = "◦"
        }
        addSubview(iconLabel)

        // Title
        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Subtitle
        if let subtitle = item.subtitle {
            subtitleLabel.stringValue = subtitle
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subtitleLabel)
        }

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            iconLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: item.subtitle != nil ? -8 : 0),
        ])

        if item.subtitle != nil {
            NSLayoutConstraint.activate([
                subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
                subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            ])
        }

        updateAppearance()

        // Click gesture
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    private func updateAppearance() {
        if isSelected {
            backgroundView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        } else {
            backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    @objc private func handleClick() {
        onClick?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            backgroundView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        updateAppearance()
    }
}

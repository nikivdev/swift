import AppKit
import Foundation

// MARK: - App Initialization

private var appInitialized = false
private let initLock = NSLock()

private func ensureAppInitialized() {
    initLock.lock()
    defer { initLock.unlock() }

    guard !appInitialized else { return }
    appInitialized = true

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
}

// MARK: - C FFI Interface

/// C-compatible result codes
@frozen
public enum LauncherResultCode: Int32 {
    case dismissed = 0
    case submitted = 1
    case command = 2
    case option = 3
}

/// Callback type for async launcher result
public typealias LauncherCallback = @convention(c) (Int32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

/// Show the launcher asynchronously
/// - Parameters:
///   - placeholder: C string placeholder text
///   - callback: Called when launcher closes
///   - context: User context passed to callback
@_cdecl("launcher_show")
public func launcher_show(
    _ placeholder: UnsafePointer<CChar>?,
    _ callback: LauncherCallback?,
    _ context: UnsafeMutableRawPointer?
) {
    ensureAppInitialized()
    let placeholderStr = placeholder.map { String(cString: $0) } ?? ""

    DispatchQueue.main.async {
        Task { @MainActor in
            let result = await Launcher.shared.show(placeholder: placeholderStr)

            let code: Int32
            switch result.action {
            case .dismissed: code = 0
            case .submitted: code = 1
            case .command: code = 2
            case .option: code = 3
            }

            if let query = result.query {
                query.withCString { ptr in
                    callback?(code, ptr, context)
                }
            } else {
                callback?(code, nil, context)
            }
        }
    }
}

/// Hide the launcher
@_cdecl("launcher_hide")
public func launcher_hide() {
    DispatchQueue.main.async {
        Task { @MainActor in
            Launcher.shared.hide()
        }
    }
}

/// Check if launcher is visible
/// - Returns: 1 if visible, 0 if not
@_cdecl("launcher_is_visible")
public func launcher_is_visible() -> Int32 {
    var visible: Bool = false

    if Thread.isMainThread {
        // Use MainActor.assumeIsolated for sync access on main thread
        visible = MainActor.assumeIsolated {
            Launcher.shared.isVisible
        }
    } else {
        DispatchQueue.main.sync {
            visible = MainActor.assumeIsolated {
                Launcher.shared.isVisible
            }
        }
    }

    return visible ? 1 : 0
}

/// Synchronous show (blocks until user dismisses)
/// - Parameters:
///   - placeholder: C string placeholder
///   - queryBuffer: Buffer to write query result
///   - bufferSize: Size of query buffer
/// - Returns: Result code
@_cdecl("launcher_show_sync")
public func launcher_show_sync(
    _ placeholder: UnsafePointer<CChar>?,
    _ queryBuffer: UnsafeMutablePointer<CChar>?,
    _ bufferSize: Int32
) -> Int32 {
    ensureAppInitialized()
    let placeholderStr = placeholder.map { String(cString: $0) } ?? ""

    var done = false
    var resultCode: Int32 = 0
    var resultQuery: String?

    DispatchQueue.main.async {
        Task { @MainActor in
            let result = await Launcher.shared.show(placeholder: placeholderStr)

            switch result.action {
            case .dismissed: resultCode = 0
            case .submitted: resultCode = 1
            case .command: resultCode = 2
            case .option: resultCode = 3
            }
            resultQuery = result.query
            done = true
        }
    }

    // Run the run loop until done
    while !done {
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    if let buffer = queryBuffer, bufferSize > 0 {
        if let query = resultQuery {
            let bytes = Array(query.utf8)
            let copyLen = min(bytes.count, Int(bufferSize) - 1)
            for i in 0..<copyLen {
                buffer[i] = CChar(bitPattern: bytes[i])
            }
            buffer[copyLen] = 0
        } else {
            buffer[0] = 0
        }
    }

    return resultCode
}

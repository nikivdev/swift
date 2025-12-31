import AppKit
import Foundation

// Generate unique filename with timestamp
let timestamp = ISO8601DateFormatter().string(from: Date())
    .replacingOccurrences(of: ":", with: "-")
    .replacingOccurrences(of: "T", with: "_")
    .prefix(19)

let screenshotDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Screenshots")

// Create directory if needed
try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)

let filename = "screenshot_\(timestamp).png"
let filepath = screenshotDir.appendingPathComponent(filename).path

// Run screencapture with interactive selection
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
process.arguments = ["-i", filepath]

do {
    try process.run()
    process.waitUntilExit()

    // Check if file was created (user didn't cancel)
    if FileManager.default.fileExists(atPath: filepath) {
        // Copy filepath to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(filepath, forType: .string)

        print(filepath)
    } else {
        // User cancelled
        exit(0)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

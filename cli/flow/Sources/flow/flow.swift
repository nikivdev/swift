import ArgumentParser
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct Flow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flow",
        abstract: "Author and run lightweight step-based flows stored as JSON.",
        discussion:
            "Use `flow init` to scaffold a new flow definition and `flow run` to walk through its steps.",
        version: "1.0.0",
        subcommands: [Init.self, Run.self, Show.self, Api.self]
    )

    private static let paletteOptions: [CommandPalette.Option] = [
        .init(
            command: "init",
            description: Flow.Init.configuration.abstract
        ),
        .init(
            command: "run",
            description: Flow.Run.configuration.abstract
        ),
        .init(
            command: "show",
            description: Flow.Show.configuration.abstract
        ),
        .init(
            command: "api",
            description: Flow.Api.configuration.abstract
        )
    ]

    fileprivate static func resolvedExecutableName() -> String {
        if let explicit = Flow.configuration.commandName, !explicit.isEmpty {
            return explicit
        }
        guard let raw = CommandLine.arguments.first else {
            return "flow"
        }
        return URL(fileURLWithPath: raw).lastPathComponent
    }

    static func main() {
        var arguments = CommandLine.arguments

        if arguments.count <= 1 {
            do {
                let paletteArgs = try CommandPalette.selectCommandArguments(
                    executableName: resolvedExecutableName(),
                    options: paletteOptions
                )
                if paletteArgs.isEmpty {
                    Flow.exit(withError: CleanExit.helpRequest(Flow.self))
                }
                arguments = [arguments[0]] + paletteArgs
            } catch CommandPaletteError.exitRequested(let code) {
                Foundation.exit(code)
            } catch {
                Flow.exit(withError: error)
            }
        }

        do {
            var command = try Flow.parseAsRoot(Array(arguments.dropFirst()))
            try command.run()
        } catch {
            Flow.exit(withError: error)
        }
    }
}

private struct FlowDefinition: Codable {
    struct Step: Codable {
        let index: Int
        let title: String
        let notes: String?
    }

    let name: String
    let lastUpdated: Date
    let steps: [Step]

    init(name: String, steps: [Step], lastUpdated: Date = Date()) {
        self.name = name
        self.steps = steps
        self.lastUpdated = lastUpdated
    }
}

extension FlowDefinition {
    fileprivate static func load(from path: String) throws -> FlowDefinition {
        let url = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError(
                "No flow definition found at \(url.path). Run `flow init` first or point to an existing file with --file."
            )
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FlowDefinition.self, from: data)
    }

    fileprivate func save(to path: String, overwriting: Bool) throws {
        let url = URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let fm = FileManager.default

        if fm.fileExists(atPath: url.path) && !overwriting {
            throw ValidationError(
                "A flow definition already exists at \(url.path). Use --force to overwrite it.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

extension Flow {
    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Scaffold a new flow JSON file in the current directory.")

        @Option(name: .shortAndLong, help: "Friendly name for the flow.")
        var name: String = "My Flow"

        @Option(name: [.customShort("s"), .long], help: "Comma-separated list of step titles.")
        var steps: String = "Plan,Build,Ship"

        @Option(
            help: "Optional comma-separated notes for each step, matching the order of --steps.")
        var notes: String = ""

        @Option(name: .shortAndLong, help: "Destination path for the flow definition JSON.")
        var file: String = "flow.json"

        @Flag(help: "Overwrite the destination file if it already exists.")
        var force = false

        mutating func run() throws {
            let stepTitles =
                steps
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !stepTitles.isEmpty else {
                throw ValidationError("Provide at least one step via --steps.")
            }

            let stepNotes =
                notes
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let flowSteps: [FlowDefinition.Step] = stepTitles.enumerated().map { offset, title in
                let note =
                    offset < stepNotes.count
                    ? (stepNotes[offset].isEmpty ? nil : stepNotes[offset]) : nil
                return FlowDefinition.Step(index: offset + 1, title: title, notes: note)
            }

            let definition = FlowDefinition(name: name, steps: flowSteps)
            try definition.save(to: file, overwriting: force)
            print("Created flow ‘\(name)’ with \(flowSteps.count) step(s) at \(file).")
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stream the flow and highlight the next actionable step.")

        @Option(name: .shortAndLong, help: "Path to the flow definition JSON.")
        var file: String = "flow.json"

        @Option(name: .shortAndLong, help: "Run only the step with the matching index (1-based).")
        var step: Int?

        mutating func run() throws {
            let definition = try FlowDefinition.load(from: file)
            guard !definition.steps.isEmpty else {
                print("The flow ‘\(definition.name)’ has no steps yet. Edit \(file) to add some.")
                return
            }

            FlowPrinter.printHeader(for: definition)

            let stepsToPrint: [FlowDefinition.Step]
            if let step = step {
                guard let target = definition.steps.first(where: { $0.index == step }) else {
                    throw ValidationError("No step with index \(step) in \(file).")
                }
                stepsToPrint = [target]
            } else {
                stepsToPrint = definition.steps
            }

            for flowStep in stepsToPrint {
                FlowPrinter.printStep(flowStep)
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Display the configured flow without running it.")

        @Option(name: .shortAndLong, help: "Path to the flow definition JSON.")
        var file: String = "flow.json"

        mutating func run() throws {
            let definition = try FlowDefinition.load(from: file)
            FlowPrinter.printHeader(for: definition)
            if definition.steps.isEmpty {
                print("(no steps)")
            } else {
                for step in definition.steps {
                    FlowPrinter.printStep(step)
                }
            }
        }
    }

    struct Api: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all available Swift APIs.")

        @Flag(name: .shortAndLong, help: "Show detailed information for each API.")
        var verbose = false

        @Option(name: .shortAndLong, help: "Filter APIs by category (e.g., foundation, swiftui, uikit).")
        var category: String?

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        mutating func run() throws {
            let apis = SwiftAPIRegistry.allAPIs

            let filtered: [SwiftAPI]
            if let category = category?.lowercased() {
                filtered = apis.filter { $0.category.lowercased() == category }
            } else {
                filtered = apis
            }

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(filtered)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                if filtered.isEmpty {
                    print("No APIs found.")
                    return
                }

                let grouped = Dictionary(grouping: filtered, by: { $0.category })
                for (category, categoryAPIs) in grouped.sorted(by: { $0.key < $1.key }) {
                    print("\n\(category)")
                    print(String(repeating: "─", count: category.count))
                    for api in categoryAPIs.sorted(by: { $0.name < $1.name }) {
                        if verbose {
                            print("  \(api.name)")
                            print("    \(api.description)")
                            if !api.availability.isEmpty {
                                print("    Availability: \(api.availability)")
                            }
                        } else {
                            print("  \(api.name) - \(api.description)")
                        }
                    }
                }
                print("\nTotal: \(filtered.count) API(s)")
            }
        }
    }
}

struct SwiftAPI: Codable {
    let name: String
    let description: String
    let category: String
    let availability: String
}

enum SwiftAPIRegistry {
    static let allAPIs: [SwiftAPI] = [
        // Foundation
        SwiftAPI(name: "URLSession", description: "Perform HTTP/HTTPS requests", category: "Foundation", availability: "iOS 7.0+, macOS 10.9+"),
        SwiftAPI(name: "FileManager", description: "Manage files and directories", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "JSONEncoder", description: "Encode Codable types to JSON", category: "Foundation", availability: "iOS 11.0+, macOS 10.13+"),
        SwiftAPI(name: "JSONDecoder", description: "Decode JSON to Codable types", category: "Foundation", availability: "iOS 11.0+, macOS 10.13+"),
        SwiftAPI(name: "UserDefaults", description: "Store user preferences persistently", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "NotificationCenter", description: "Broadcast notifications within the app", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "Timer", description: "Schedule and fire timed events", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "DispatchQueue", description: "Execute tasks asynchronously or synchronously", category: "Foundation", availability: "iOS 4.0+, macOS 10.6+"),
        SwiftAPI(name: "ProcessInfo", description: "Access process environment and arguments", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "Bundle", description: "Access app resources and metadata", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "DateFormatter", description: "Format and parse dates", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "NumberFormatter", description: "Format and parse numbers", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "Locale", description: "Access locale-specific information", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "Calendar", description: "Perform calendar calculations", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "UUID", description: "Generate unique identifiers", category: "Foundation", availability: "iOS 6.0+, macOS 10.8+"),

        // Networking
        SwiftAPI(name: "URLRequest", description: "Configure HTTP request parameters", category: "Networking", availability: "iOS 2.0+, macOS 10.2+"),
        SwiftAPI(name: "URLResponse", description: "Handle HTTP response metadata", category: "Networking", availability: "iOS 2.0+, macOS 10.2+"),
        SwiftAPI(name: "URLCache", description: "Cache URL responses", category: "Networking", availability: "iOS 2.0+, macOS 10.2+"),
        SwiftAPI(name: "URLSessionTask", description: "Manage individual network requests", category: "Networking", availability: "iOS 7.0+, macOS 10.9+"),
        SwiftAPI(name: "URLSessionConfiguration", description: "Configure session behavior", category: "Networking", availability: "iOS 7.0+, macOS 10.9+"),

        // Concurrency
        SwiftAPI(name: "Task", description: "Create and manage async tasks", category: "Concurrency", availability: "iOS 15.0+, macOS 12.0+"),
        SwiftAPI(name: "TaskGroup", description: "Run multiple concurrent tasks", category: "Concurrency", availability: "iOS 15.0+, macOS 12.0+"),
        SwiftAPI(name: "AsyncSequence", description: "Iterate over async values", category: "Concurrency", availability: "iOS 15.0+, macOS 12.0+"),
        SwiftAPI(name: "AsyncStream", description: "Bridge callback-based APIs to async/await", category: "Concurrency", availability: "iOS 15.0+, macOS 12.0+"),
        SwiftAPI(name: "Actor", description: "Protect mutable state with actor isolation", category: "Concurrency", availability: "iOS 15.0+, macOS 12.0+"),
        SwiftAPI(name: "MainActor", description: "Run code on the main thread", category: "Concurrency", availability: "iOS 15.0+, macOS 12.0+"),

        // SwiftUI
        SwiftAPI(name: "View", description: "Define UI components", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "State", description: "Manage local view state", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "Binding", description: "Create two-way data binding", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "ObservableObject", description: "Publish changes to subscribers", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "EnvironmentObject", description: "Share data through the view hierarchy", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "StateObject", description: "Create and own observable objects", category: "SwiftUI", availability: "iOS 14.0+, macOS 11.0+"),
        SwiftAPI(name: "Observable", description: "Modern observation with @Observable macro", category: "SwiftUI", availability: "iOS 17.0+, macOS 14.0+"),
        SwiftAPI(name: "NavigationStack", description: "Manage navigation with value-based routing", category: "SwiftUI", availability: "iOS 16.0+, macOS 13.0+"),
        SwiftAPI(name: "List", description: "Display scrollable lists", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "Form", description: "Group controls for data entry", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+"),

        // UIKit
        SwiftAPI(name: "UIViewController", description: "Manage view hierarchy and lifecycle", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UIView", description: "Display and manage visual content", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UITableView", description: "Display data in scrollable rows", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UICollectionView", description: "Display data in customizable layouts", category: "UIKit", availability: "iOS 6.0+"),
        SwiftAPI(name: "UINavigationController", description: "Manage hierarchical navigation", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UITabBarController", description: "Manage tab-based interfaces", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UIApplication", description: "Manage app lifecycle and state", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UIImage", description: "Load and display images", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UILabel", description: "Display text content", category: "UIKit", availability: "iOS 2.0+"),
        SwiftAPI(name: "UIButton", description: "Create interactive buttons", category: "UIKit", availability: "iOS 2.0+"),

        // AppKit (macOS)
        SwiftAPI(name: "NSViewController", description: "Manage view hierarchy on macOS", category: "AppKit", availability: "macOS 10.5+"),
        SwiftAPI(name: "NSView", description: "Display content on macOS", category: "AppKit", availability: "macOS 10.0+"),
        SwiftAPI(name: "NSWindow", description: "Manage windows on macOS", category: "AppKit", availability: "macOS 10.0+"),
        SwiftAPI(name: "NSApplication", description: "Manage macOS app lifecycle", category: "AppKit", availability: "macOS 10.0+"),
        SwiftAPI(name: "NSTableView", description: "Display tabular data on macOS", category: "AppKit", availability: "macOS 10.0+"),

        // Data Persistence
        SwiftAPI(name: "CoreData", description: "Object graph and persistence framework", category: "Data", availability: "iOS 3.0+, macOS 10.4+"),
        SwiftAPI(name: "SwiftData", description: "Modern Swift-native persistence", category: "Data", availability: "iOS 17.0+, macOS 14.0+"),
        SwiftAPI(name: "Keychain", description: "Secure storage for sensitive data", category: "Data", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "CloudKit", description: "Store data in iCloud", category: "Data", availability: "iOS 8.0+, macOS 10.10+"),

        // System
        SwiftAPI(name: "Process", description: "Run external processes", category: "System", availability: "macOS 10.0+"),
        SwiftAPI(name: "Pipe", description: "Communicate between processes", category: "System", availability: "macOS 10.0+"),
        SwiftAPI(name: "FileHandle", description: "Read/write file descriptors", category: "System", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "CommandLine", description: "Access command-line arguments", category: "System", availability: "Swift 1.0+"),

        // Combine
        SwiftAPI(name: "Publisher", description: "Emit values over time", category: "Combine", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "Subscriber", description: "Receive and process values", category: "Combine", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "Subject", description: "Manually publish values", category: "Combine", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "PassthroughSubject", description: "Broadcast values to subscribers", category: "Combine", availability: "iOS 13.0+, macOS 10.15+"),
        SwiftAPI(name: "CurrentValueSubject", description: "Publish current and new values", category: "Combine", availability: "iOS 13.0+, macOS 10.15+"),

        // Observation
        SwiftAPI(name: "KVO", description: "Key-Value Observing for property changes", category: "Observation", availability: "iOS 2.0+, macOS 10.0+"),
        SwiftAPI(name: "Observation", description: "Swift-native observation framework", category: "Observation", availability: "iOS 17.0+, macOS 14.0+"),
    ]
}

private enum FlowPrinter {
    static func printHeader(for definition: FlowDefinition) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let timestamp = formatter.string(from: definition.lastUpdated)
        print("\n\(definition.name) — last updated \(timestamp)\n")
    }

    static func printStep(_ step: FlowDefinition.Step) {
        if let notes = step.notes {
            print("\(step.index). \(step.title)\n   ↳ \(notes)\n")
        } else {
            print("\(step.index). \(step.title)\n")
        }
    }
}

private enum CommandPaletteError: Error {
    case exitRequested(Int32)
}

private struct CommandPalette {
    struct Option {
        let command: String
        let description: String

        var arguments: [String] { [command] }
    }

    static func selectCommandArguments(
        executableName: String,
        options: [Option]
    ) throws -> [String] {
        guard !options.isEmpty else {
            return ["--help"]
        }

        guard isInteractive else {
            return ["--help"]
        }

        let process = Process()
        let selectionURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flow-palette-selection-\(UUID().uuidString)")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "fzf",
            "--height=40%",
            "--layout=reverse-list",
            "--border=rounded",
            "--prompt",
            "\(executableName)> ",
            "--info=inline",
            "--no-multi",
            "--header",
            "Select a \(executableName) command (Enter to run, ESC to cancel)",
            "--bind",
            "enter:execute-silent(echo {1} > \"$FLOW_FZF_SELECTION_PATH\")+accept"
        ]

        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        var environment = ProcessInfo.processInfo.environment
        environment["FLOW_FZF_SELECTION_PATH"] = selectionURL.path
        process.environment = environment

        do {
            try process.run()
        } catch {
            return ["--help"]
        }

        let writer = inputPipe.fileHandleForWriting
        for option in options {
            let sanitizedDescription = option.description.replacingOccurrences(of: "\n", with: " ")
            let line = "\(option.command)\t\(sanitizedDescription)\n"
            if let data = line.data(using: .utf8) {
                writer.write(data)
            }
        }
        writer.closeFile()

        process.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: selectionURL) }

        switch process.terminationStatus {
        case 0:
            guard
                let selectionData = try? Data(contentsOf: selectionURL),
                let selectionLine = String(data: selectionData, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                !selectionLine.isEmpty
            else {
                return ["--help"]
            }

            guard let match = options.first(where: { $0.command == selectionLine })
            else {
                return ["--help"]
            }
            return match.arguments
        case 130:
            throw CommandPaletteError.exitRequested(130)
        default:
            return ["--help"]
        }
    }

    private static var isInteractive: Bool {
        return isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }
}

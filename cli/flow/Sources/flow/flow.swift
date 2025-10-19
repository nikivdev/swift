import ArgumentParser
import Foundation

@main
struct Flow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flow",
        abstract: "Author and run lightweight step-based flows stored as JSON.",
        discussion:
            "Use `flow init` to scaffold a new flow definition and `flow run` to walk through its steps.",
        version: "1.0.0",
        subcommands: [Init.self, Run.self, Show.self],
        defaultSubcommand: Show.self
    )
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

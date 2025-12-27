import ArgumentParser
import Foundation

@main
struct SwiftDocs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-docs",
        abstract: "List all available Swift and Apple SDK APIs with annotations.",
        version: "1.0.0",
        subcommands: [List.self, Search.self, Categories.self],
        defaultSubcommand: List.self
    )
}

extension SwiftDocs {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all available APIs.")

        @Option(name: .shortAndLong, help: "Filter by category (e.g., Foundation, SwiftUI, Concurrency).")
        var category: String?

        @Option(name: .shortAndLong, help: "Filter by minimum iOS version (e.g., 15.0).")
        var ios: String?

        @Option(name: .shortAndLong, help: "Filter by minimum macOS version (e.g., 12.0).")
        var macos: String?

        @Flag(name: .shortAndLong, help: "Show detailed information.")
        var verbose = false

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        @Flag(name: .long, help: "Show only Swift standard library APIs.")
        var stdlib = false

        @Flag(name: .long, help: "Show only Apple SDK APIs.")
        var sdk = false

        mutating func run() throws {
            var apis = APIRegistry.allAPIs

            if stdlib {
                apis = apis.filter { $0.source == .swiftStdlib }
            } else if sdk {
                apis = apis.filter { $0.source == .appleSDK }
            }

            if let category = category?.lowercased() {
                apis = apis.filter { $0.category.lowercased().contains(category) }
            }

            if let ios = ios, let version = Double(ios) {
                apis = apis.filter { $0.iosVersion == nil || $0.iosVersion! <= version }
            }

            if let macos = macos, let version = Double(macos) {
                apis = apis.filter { $0.macosVersion == nil || $0.macosVersion! <= version }
            }

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(apis)
                print(String(data: data, encoding: .utf8)!)
            } else {
                printAPIs(apis, verbose: verbose)
            }
        }
    }

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search APIs by name or description.")

        @Argument(help: "Search query.")
        var query: String

        @Flag(name: .shortAndLong, help: "Show detailed information.")
        var verbose = false

        mutating func run() throws {
            let query = query.lowercased()
            let apis = APIRegistry.allAPIs.filter {
                $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }

            if apis.isEmpty {
                print("No APIs found matching '\(self.query)'")
            } else {
                printAPIs(apis, verbose: verbose)
            }
        }
    }

    struct Categories: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all available categories.")

        mutating func run() {
            let categories = Set(APIRegistry.allAPIs.map { $0.category }).sorted()
            print("Available categories:\n")
            for category in categories {
                let count = APIRegistry.allAPIs.filter { $0.category == category }.count
                print("  \(category) (\(count) APIs)")
            }
            print("\nTotal: \(categories.count) categories, \(APIRegistry.allAPIs.count) APIs")
        }
    }
}

private func printAPIs(_ apis: [API], verbose: Bool) {
    if apis.isEmpty {
        print("No APIs found.")
        return
    }

    let grouped = Dictionary(grouping: apis, by: { $0.category })
    for (category, categoryAPIs) in grouped.sorted(by: { $0.key < $1.key }) {
        print("\n\u{001B}[1;36m\(category)\u{001B}[0m")
        print(String(repeating: "─", count: category.count))

        for api in categoryAPIs.sorted(by: { $0.name < $1.name }) {
            let sourceTag = api.source == .swiftStdlib ? "[stdlib]" : "[SDK]"
            if verbose {
                print("  \u{001B}[1;33m\(api.name)\u{001B}[0m \u{001B}[2m\(sourceTag)\u{001B}[0m")
                print("    \(api.description)")
                print("    \u{001B}[2mAvailability: \(api.availability)\u{001B}[0m")
                if let example = api.example {
                    print("    \u{001B}[2mExample: \(example)\u{001B}[0m")
                }
                print()
            } else {
                print("  \(api.name) \u{001B}[2m\(sourceTag)\u{001B}[0m — \(api.description)")
            }
        }
    }
    print("\n\u{001B}[2mTotal: \(apis.count) API(s)\u{001B}[0m")
}

enum APISource: String, Codable {
    case swiftStdlib = "Swift Standard Library"
    case appleSDK = "Apple SDK"
}

struct API: Codable {
    let name: String
    let description: String
    let category: String
    let availability: String
    let source: APISource
    let iosVersion: Double?
    let macosVersion: Double?
    let example: String?

    init(
        name: String,
        description: String,
        category: String,
        availability: String,
        source: APISource,
        ios: Double? = nil,
        macos: Double? = nil,
        example: String? = nil
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.availability = availability
        self.source = source
        self.iosVersion = ios
        self.macosVersion = macos
        self.example = example
    }
}

enum APIRegistry {
    static let allAPIs: [API] = swiftStdlibAPIs + appleSDKAPIs

    // MARK: - Swift Standard Library

    static let swiftStdlibAPIs: [API] = [
        // Collections
        API(name: "Array", description: "Ordered, random-access collection", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib, example: "let arr = [1, 2, 3]"),
        API(name: "Dictionary", description: "Key-value hash map collection", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib, example: "let dict = [\"a\": 1]"),
        API(name: "Set", description: "Unordered collection of unique elements", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib, example: "let set: Set = [1, 2, 3]"),
        API(name: "ArraySlice", description: "View into a contiguous subrange of an Array", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "ContiguousArray", description: "Array with guaranteed contiguous storage", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Sequence", description: "Protocol for types providing sequential iteration", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Collection", description: "Protocol for indexed, multi-pass sequences", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "BidirectionalCollection", description: "Collection that supports backward traversal", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "RandomAccessCollection", description: "Collection with O(1) index movement", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "LazySequence", description: "Sequence with lazy evaluation of transforms", category: "Collections", availability: "Swift 1.0+", source: .swiftStdlib),

        // Strings
        API(name: "String", description: "Unicode-compliant text type", category: "Strings", availability: "Swift 1.0+", source: .swiftStdlib, example: "let s = \"Hello\""),
        API(name: "Substring", description: "Slice of a String sharing storage", category: "Strings", availability: "Swift 4.0+", source: .swiftStdlib),
        API(name: "Character", description: "Single extended grapheme cluster", category: "Strings", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Unicode.Scalar", description: "Single Unicode scalar value", category: "Strings", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "StaticString", description: "Compile-time constant string", category: "Strings", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "String.Index", description: "Position of a character in a String", category: "Strings", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "StringProtocol", description: "Protocol for String-like types", category: "Strings", availability: "Swift 4.0+", source: .swiftStdlib),

        // Numerics
        API(name: "Int", description: "Signed integer (platform word size)", category: "Numerics", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Double", description: "64-bit floating-point number", category: "Numerics", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Float", description: "32-bit floating-point number", category: "Numerics", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Bool", description: "Boolean true/false value", category: "Numerics", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Int8/16/32/64", description: "Fixed-width signed integers", category: "Numerics", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "UInt8/16/32/64", description: "Fixed-width unsigned integers", category: "Numerics", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Float16", description: "16-bit floating-point (half precision)", category: "Numerics", availability: "Swift 5.3+", source: .swiftStdlib),
        API(name: "Decimal", description: "Base-10 floating-point for financial calculations", category: "Numerics", availability: "Swift 1.0+", source: .swiftStdlib),

        // Optionals & Results
        API(name: "Optional", description: "Wrapper for values that may be absent", category: "Optionals", availability: "Swift 1.0+", source: .swiftStdlib, example: "let x: Int? = nil"),
        API(name: "Result", description: "Success or failure with associated values", category: "Optionals", availability: "Swift 5.0+", source: .swiftStdlib, example: "Result<Int, Error>"),
        API(name: "Never", description: "Uninhabited type for non-returning functions", category: "Optionals", availability: "Swift 3.0+", source: .swiftStdlib),

        // Error Handling
        API(name: "Error", description: "Protocol for throwable error types", category: "Error Handling", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "throw/try/catch", description: "Error propagation and handling keywords", category: "Error Handling", availability: "Swift 2.0+", source: .swiftStdlib),
        API(name: "rethrows", description: "Propagate errors from closure parameters", category: "Error Handling", availability: "Swift 2.0+", source: .swiftStdlib),
        API(name: "defer", description: "Execute cleanup code when scope exits", category: "Error Handling", availability: "Swift 2.0+", source: .swiftStdlib),

        // Protocols
        API(name: "Equatable", description: "Protocol for equality comparison", category: "Protocols", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Hashable", description: "Protocol for types usable as Dictionary keys", category: "Protocols", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Comparable", description: "Protocol for ordering comparison", category: "Protocols", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Codable", description: "Protocol for encoding/decoding types", category: "Protocols", availability: "Swift 4.0+", source: .swiftStdlib),
        API(name: "Identifiable", description: "Protocol for types with stable identity", category: "Protocols", availability: "Swift 5.1+", source: .swiftStdlib),
        API(name: "CustomStringConvertible", description: "Protocol for custom string representation", category: "Protocols", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "Sendable", description: "Protocol for thread-safe types", category: "Protocols", availability: "Swift 5.5+", source: .swiftStdlib),
        API(name: "CopyableNoncopyable", description: "Move-only type support", category: "Protocols", availability: "Swift 5.9+", source: .swiftStdlib),

        // Concurrency (Swift)
        API(name: "async/await", description: "Asynchronous function syntax", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "Task", description: "Unit of asynchronous work", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0, example: "Task { await fetch() }"),
        API(name: "TaskGroup", description: "Structured concurrency for parallel tasks", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "AsyncSequence", description: "Async iteration protocol", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "AsyncStream", description: "Bridge callbacks to async sequences", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "AsyncThrowingStream", description: "Throwing async stream", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "actor", description: "Reference type with isolated mutable state", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "MainActor", description: "Global actor for main thread", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "isolated", description: "Parameter isolation for actors", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "nonisolated", description: "Opt out of actor isolation", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "withCheckedContinuation", description: "Bridge completion handlers to async", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),
        API(name: "withTaskCancellationHandler", description: "Handle task cancellation", category: "Concurrency", availability: "Swift 5.5+", source: .swiftStdlib, ios: 15.0, macos: 12.0),

        // Memory
        API(name: "UnsafePointer", description: "Typed pointer to immutable memory", category: "Memory", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "UnsafeMutablePointer", description: "Typed pointer to mutable memory", category: "Memory", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "UnsafeBufferPointer", description: "Pointer to contiguous typed memory", category: "Memory", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "UnsafeRawPointer", description: "Untyped pointer to immutable memory", category: "Memory", availability: "Swift 3.0+", source: .swiftStdlib),
        API(name: "withUnsafePointer", description: "Scoped access to pointer", category: "Memory", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "ManagedBuffer", description: "Heap-allocated buffer with header", category: "Memory", availability: "Swift 1.0+", source: .swiftStdlib),
        API(name: "MemoryLayout", description: "Query type memory characteristics", category: "Memory", availability: "Swift 3.0+", source: .swiftStdlib),

        // Macros (Swift 5.9+)
        API(name: "@attached", description: "Attached macro declaration", category: "Macros", availability: "Swift 5.9+", source: .swiftStdlib),
        API(name: "@freestanding", description: "Freestanding macro declaration", category: "Macros", availability: "Swift 5.9+", source: .swiftStdlib),
        API(name: "#stringify", description: "Convert expression to string", category: "Macros", availability: "Swift 5.9+", source: .swiftStdlib),
        API(name: "#file/#line/#function", description: "Source location macros", category: "Macros", availability: "Swift 1.0+", source: .swiftStdlib),

        // Key Paths
        API(name: "KeyPath", description: "Immutable key path to property", category: "Key Paths", availability: "Swift 4.0+", source: .swiftStdlib, example: "\\Person.name"),
        API(name: "WritableKeyPath", description: "Mutable key path to property", category: "Key Paths", availability: "Swift 4.0+", source: .swiftStdlib),
        API(name: "ReferenceWritableKeyPath", description: "Key path for reference types", category: "Key Paths", availability: "Swift 4.0+", source: .swiftStdlib),
        API(name: "PartialKeyPath", description: "Type-erased key path", category: "Key Paths", availability: "Swift 4.0+", source: .swiftStdlib),

        // Property Wrappers
        API(name: "@propertyWrapper", description: "Define custom property behaviors", category: "Property Wrappers", availability: "Swift 5.1+", source: .swiftStdlib),
        API(name: "projectedValue", description: "Secondary value exposed via $", category: "Property Wrappers", availability: "Swift 5.1+", source: .swiftStdlib),

        // Result Builders
        API(name: "@resultBuilder", description: "DSL for declarative syntax", category: "Result Builders", availability: "Swift 5.4+", source: .swiftStdlib),
        API(name: "buildBlock", description: "Combine multiple components", category: "Result Builders", availability: "Swift 5.4+", source: .swiftStdlib),
        API(name: "buildOptional", description: "Handle optional components", category: "Result Builders", availability: "Swift 5.4+", source: .swiftStdlib),
        API(name: "buildEither", description: "Handle conditional branches", category: "Result Builders", availability: "Swift 5.4+", source: .swiftStdlib),

        // Regex (Swift 5.7+)
        API(name: "Regex", description: "Type-safe regular expression", category: "Regex", availability: "Swift 5.7+", source: .swiftStdlib, ios: 16.0, macos: 13.0),
        API(name: "RegexBuilder", description: "DSL for building regex patterns", category: "Regex", availability: "Swift 5.7+", source: .swiftStdlib, ios: 16.0, macos: 13.0),
        API(name: "firstMatch(of:)", description: "Find first regex match", category: "Regex", availability: "Swift 5.7+", source: .swiftStdlib, ios: 16.0, macos: 13.0),
        API(name: "wholeMatch(of:)", description: "Match entire string", category: "Regex", availability: "Swift 5.7+", source: .swiftStdlib, ios: 16.0, macos: 13.0),
    ]

    // MARK: - Apple SDK APIs

    static let appleSDKAPIs: [API] = [
        // Foundation
        API(name: "URL", description: "Uniform Resource Locator", category: "Foundation", availability: "iOS 7.0+, macOS 10.9+", source: .appleSDK, ios: 7.0, macos: 10.9),
        API(name: "URLSession", description: "HTTP/HTTPS networking", category: "Foundation", availability: "iOS 7.0+, macOS 10.9+", source: .appleSDK, ios: 7.0, macos: 10.9),
        API(name: "URLRequest", description: "HTTP request configuration", category: "Foundation", availability: "iOS 2.0+, macOS 10.2+", source: .appleSDK, ios: 2.0, macos: 10.2),
        API(name: "URLCache", description: "URL response caching", category: "Foundation", availability: "iOS 2.0+, macOS 10.2+", source: .appleSDK, ios: 2.0, macos: 10.2),
        API(name: "FileManager", description: "File system operations", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "Data", description: "Raw byte buffer", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "Date", description: "Point in time", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "DateFormatter", description: "Date/string conversion", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "Calendar", description: "Calendar calculations", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "TimeZone", description: "Time zone information", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "Locale", description: "Regional settings", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "UUID", description: "Universally unique identifier", category: "Foundation", availability: "iOS 6.0+, macOS 10.8+", source: .appleSDK, ios: 6.0, macos: 10.8),
        API(name: "JSONEncoder", description: "Encode to JSON", category: "Foundation", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "JSONDecoder", description: "Decode from JSON", category: "Foundation", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "PropertyListEncoder", description: "Encode to plist", category: "Foundation", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "PropertyListDecoder", description: "Decode from plist", category: "Foundation", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "UserDefaults", description: "Persistent key-value storage", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "NotificationCenter", description: "Broadcast notifications", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "Timer", description: "Scheduled events", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "DispatchQueue", description: "Task execution queues", category: "Foundation", availability: "iOS 4.0+, macOS 10.6+", source: .appleSDK, ios: 4.0, macos: 10.6),
        API(name: "OperationQueue", description: "High-level operation scheduling", category: "Foundation", availability: "iOS 2.0+, macOS 10.5+", source: .appleSDK, ios: 2.0, macos: 10.5),
        API(name: "ProcessInfo", description: "Process environment", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "Bundle", description: "App resources access", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "AttributedString", description: "Rich text with attributes", category: "Foundation", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: "Measurement", description: "Type-safe unit conversions", category: "Foundation", availability: "iOS 10.0+, macOS 10.12+", source: .appleSDK, ios: 10.0, macos: 10.12),
        API(name: "NumberFormatter", description: "Number formatting", category: "Foundation", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "ByteCountFormatter", description: "File size formatting", category: "Foundation", availability: "iOS 6.0+, macOS 10.8+", source: .appleSDK, ios: 6.0, macos: 10.8),

        // Process (macOS)
        API(name: "Process", description: "Run external processes", category: "Process", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "Pipe", description: "Inter-process communication", category: "Process", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "FileHandle", description: "File descriptor wrapper", category: "Process", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),

        // SwiftUI
        API(name: "View", description: "UI component protocol", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "@State", description: "Local view state", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "@Binding", description: "Two-way data binding", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "@ObservedObject", description: "External observable object", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "@StateObject", description: "Owned observable object", category: "SwiftUI", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: "@EnvironmentObject", description: "Shared environment data", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "@Environment", description: "System environment values", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "@Observable", description: "Modern observation macro", category: "SwiftUI", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "@Bindable", description: "Bindable for @Observable", category: "SwiftUI", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "NavigationStack", description: "Value-based navigation", category: "SwiftUI", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),
        API(name: "NavigationSplitView", description: "Multi-column navigation", category: "SwiftUI", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),
        API(name: "List", description: "Scrollable list", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "LazyVStack/LazyHStack", description: "Lazy loading stacks", category: "SwiftUI", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: "LazyVGrid/LazyHGrid", description: "Lazy loading grids", category: "SwiftUI", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: "Form", description: "Data entry form", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "Sheet", description: "Modal presentation", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "Alert", description: "Alert dialogs", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "AsyncImage", description: "Async image loading", category: "SwiftUI", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: "Canvas", description: "Immediate mode drawing", category: "SwiftUI", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: "TimelineView", description: "Time-based updates", category: "SwiftUI", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: ".task", description: "Async task modifier", category: "SwiftUI", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: ".refreshable", description: "Pull-to-refresh", category: "SwiftUI", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: ".searchable", description: "Search interface", category: "SwiftUI", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: "@FocusState", description: "Focus management", category: "SwiftUI", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: "@AppStorage", description: "UserDefaults binding", category: "SwiftUI", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: "@SceneStorage", description: "Scene-level state persistence", category: "SwiftUI", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: "ViewModifier", description: "Reusable view modifications", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "GeometryReader", description: "Access container geometry", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "PreferenceKey", description: "Child-to-parent data flow", category: "SwiftUI", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),

        // UIKit
        API(name: "UIViewController", description: "View controller lifecycle", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UIView", description: "Visual content display", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UITableView", description: "Scrollable row list", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UICollectionView", description: "Flexible grid layout", category: "UIKit", availability: "iOS 6.0+", source: .appleSDK, ios: 6.0),
        API(name: "UINavigationController", description: "Hierarchical navigation", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UITabBarController", description: "Tab-based interface", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UIStackView", description: "Auto-layout stack", category: "UIKit", availability: "iOS 9.0+", source: .appleSDK, ios: 9.0),
        API(name: "UIScrollView", description: "Scrollable content", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UIImage", description: "Image representation", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UIColor", description: "Color representation", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UIFont", description: "Font representation", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UIBezierPath", description: "Vector path drawing", category: "UIKit", availability: "iOS 3.2+", source: .appleSDK, ios: 3.2),
        API(name: "UIGestureRecognizer", description: "Touch gesture handling", category: "UIKit", availability: "iOS 3.2+", source: .appleSDK, ios: 3.2),
        API(name: "UIApplication", description: "App lifecycle", category: "UIKit", availability: "iOS 2.0+", source: .appleSDK, ios: 2.0),
        API(name: "UIScene", description: "Multi-window support", category: "UIKit", availability: "iOS 13.0+", source: .appleSDK, ios: 13.0),
        API(name: "UIDiffableDataSource", description: "Diffable data source", category: "UIKit", availability: "iOS 13.0+", source: .appleSDK, ios: 13.0),
        API(name: "UICollectionViewCompositionalLayout", description: "Flexible collection layout", category: "UIKit", availability: "iOS 13.0+", source: .appleSDK, ios: 13.0),

        // AppKit (macOS)
        API(name: "NSViewController", description: "View controller (macOS)", category: "AppKit", availability: "macOS 10.5+", source: .appleSDK, macos: 10.5),
        API(name: "NSView", description: "Visual content (macOS)", category: "AppKit", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "NSWindow", description: "Window management", category: "AppKit", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "NSApplication", description: "App lifecycle (macOS)", category: "AppKit", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "NSTableView", description: "Table display (macOS)", category: "AppKit", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "NSOutlineView", description: "Hierarchical list (macOS)", category: "AppKit", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "NSMenu", description: "Menu system", category: "AppKit", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),
        API(name: "NSToolbar", description: "Window toolbar", category: "AppKit", availability: "macOS 10.0+", source: .appleSDK, macos: 10.0),

        // Combine
        API(name: "Publisher", description: "Value producer protocol", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "Subscriber", description: "Value consumer protocol", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "Subject", description: "Publisher you can send to", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "PassthroughSubject", description: "Broadcasts values", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "CurrentValueSubject", description: "Holds current value", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "@Published", description: "Auto-publishing property", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "AnyPublisher", description: "Type-erased publisher", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "Just", description: "Single value publisher", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "Future", description: "Single async value", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: ".map/.filter/.flatMap", description: "Transform operators", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: ".sink", description: "Subscribe to values", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: ".assign", description: "Bind to property", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "AnyCancellable", description: "Subscription lifecycle", category: "Combine", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),

        // Data Persistence
        API(name: "CoreData (NSManagedObject)", description: "Object-relational mapping", category: "Data Persistence", availability: "iOS 3.0+, macOS 10.4+", source: .appleSDK, ios: 3.0, macos: 10.4),
        API(name: "NSPersistentContainer", description: "Core Data stack setup", category: "Data Persistence", availability: "iOS 10.0+, macOS 10.12+", source: .appleSDK, ios: 10.0, macos: 10.12),
        API(name: "NSFetchRequest", description: "Core Data query", category: "Data Persistence", availability: "iOS 3.0+, macOS 10.4+", source: .appleSDK, ios: 3.0, macos: 10.4),
        API(name: "@Model", description: "SwiftData model macro", category: "Data Persistence", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "ModelContainer", description: "SwiftData container", category: "Data Persistence", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "ModelContext", description: "SwiftData context", category: "Data Persistence", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "@Query", description: "SwiftData fetch", category: "Data Persistence", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "Keychain Services", description: "Secure credential storage", category: "Data Persistence", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),

        // CloudKit
        API(name: "CKContainer", description: "CloudKit container", category: "CloudKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),
        API(name: "CKDatabase", description: "CloudKit database", category: "CloudKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),
        API(name: "CKRecord", description: "CloudKit record", category: "CloudKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),
        API(name: "CKQuery", description: "CloudKit query", category: "CloudKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),
        API(name: "CKSubscription", description: "CloudKit push notifications", category: "CloudKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),

        // Observation
        API(name: "Observation framework", description: "Swift-native observation", category: "Observation", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "withObservationTracking", description: "Track property access", category: "Observation", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),

        // Core Graphics
        API(name: "CGContext", description: "2D drawing context", category: "Core Graphics", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "CGImage", description: "Bitmap image", category: "Core Graphics", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "CGPath", description: "Graphics path", category: "Core Graphics", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "CGRect/CGPoint/CGSize", description: "Geometry types", category: "Core Graphics", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "CGAffineTransform", description: "2D affine transformations", category: "Core Graphics", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "CGColor", description: "Core Graphics color", category: "Core Graphics", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),

        // Core Animation
        API(name: "CALayer", description: "Layer-based rendering", category: "Core Animation", availability: "iOS 2.0+, macOS 10.5+", source: .appleSDK, ios: 2.0, macos: 10.5),
        API(name: "CABasicAnimation", description: "Single-property animation", category: "Core Animation", availability: "iOS 2.0+, macOS 10.5+", source: .appleSDK, ios: 2.0, macos: 10.5),
        API(name: "CAKeyframeAnimation", description: "Keyframe animation", category: "Core Animation", availability: "iOS 2.0+, macOS 10.5+", source: .appleSDK, ios: 2.0, macos: 10.5),
        API(name: "CATransaction", description: "Animation transaction", category: "Core Animation", availability: "iOS 2.0+, macOS 10.5+", source: .appleSDK, ios: 2.0, macos: 10.5),
        API(name: "CADisplayLink", description: "Display refresh sync", category: "Core Animation", availability: "iOS 3.1+", source: .appleSDK, ios: 3.1),

        // AVFoundation
        API(name: "AVPlayer", description: "Media playback", category: "AVFoundation", availability: "iOS 4.0+, macOS 10.7+", source: .appleSDK, ios: 4.0, macos: 10.7),
        API(name: "AVPlayerViewController", description: "Video player UI", category: "AVFoundation", availability: "iOS 8.0+", source: .appleSDK, ios: 8.0),
        API(name: "AVAudioPlayer", description: "Audio playback", category: "AVFoundation", availability: "iOS 2.2+, macOS 10.7+", source: .appleSDK, ios: 2.2, macos: 10.7),
        API(name: "AVAudioRecorder", description: "Audio recording", category: "AVFoundation", availability: "iOS 3.0+, macOS 10.7+", source: .appleSDK, ios: 3.0, macos: 10.7),
        API(name: "AVCaptureSession", description: "Camera/mic capture", category: "AVFoundation", availability: "iOS 4.0+, macOS 10.7+", source: .appleSDK, ios: 4.0, macos: 10.7),
        API(name: "AVAsset", description: "Media asset", category: "AVFoundation", availability: "iOS 4.0+, macOS 10.7+", source: .appleSDK, ios: 4.0, macos: 10.7),

        // Core Location
        API(name: "CLLocationManager", description: "Location services", category: "Core Location", availability: "iOS 2.0+, macOS 10.6+", source: .appleSDK, ios: 2.0, macos: 10.6),
        API(name: "CLLocation", description: "Geographic location", category: "Core Location", availability: "iOS 2.0+, macOS 10.6+", source: .appleSDK, ios: 2.0, macos: 10.6),
        API(name: "CLGeocoder", description: "Address/coordinate conversion", category: "Core Location", availability: "iOS 5.0+, macOS 10.8+", source: .appleSDK, ios: 5.0, macos: 10.8),
        API(name: "CLRegion", description: "Geographic region monitoring", category: "Core Location", availability: "iOS 4.0+, macOS 10.7+", source: .appleSDK, ios: 4.0, macos: 10.7),

        // MapKit
        API(name: "MKMapView", description: "Interactive map display", category: "MapKit", availability: "iOS 3.0+, macOS 10.9+", source: .appleSDK, ios: 3.0, macos: 10.9),
        API(name: "MKAnnotation", description: "Map annotations", category: "MapKit", availability: "iOS 3.0+, macOS 10.9+", source: .appleSDK, ios: 3.0, macos: 10.9),
        API(name: "MKDirections", description: "Route calculations", category: "MapKit", availability: "iOS 7.0+, macOS 10.9+", source: .appleSDK, ios: 7.0, macos: 10.9),
        API(name: "Map (SwiftUI)", description: "SwiftUI map view", category: "MapKit", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),

        // HealthKit
        API(name: "HKHealthStore", description: "Health data access", category: "HealthKit", availability: "iOS 8.0+", source: .appleSDK, ios: 8.0),
        API(name: "HKQuery", description: "Health data queries", category: "HealthKit", availability: "iOS 8.0+", source: .appleSDK, ios: 8.0),
        API(name: "HKWorkout", description: "Workout data", category: "HealthKit", availability: "iOS 8.0+", source: .appleSDK, ios: 8.0),

        // StoreKit
        API(name: "Product", description: "In-app purchase products", category: "StoreKit", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: "Transaction", description: "Purchase transactions", category: "StoreKit", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),
        API(name: "AppStore.sync()", description: "Sync transactions", category: "StoreKit", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),

        // UserNotifications
        API(name: "UNUserNotificationCenter", description: "Local/push notifications", category: "UserNotifications", availability: "iOS 10.0+, macOS 10.14+", source: .appleSDK, ios: 10.0, macos: 10.14),
        API(name: "UNNotificationRequest", description: "Notification scheduling", category: "UserNotifications", availability: "iOS 10.0+, macOS 10.14+", source: .appleSDK, ios: 10.0, macos: 10.14),
        API(name: "UNNotificationContent", description: "Notification content", category: "UserNotifications", availability: "iOS 10.0+, macOS 10.14+", source: .appleSDK, ios: 10.0, macos: 10.14),

        // Core ML
        API(name: "MLModel", description: "Machine learning model", category: "Core ML", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "VNCoreMLRequest", description: "Vision + Core ML", category: "Core ML", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "CreateML", description: "Train models on-device", category: "Core ML", availability: "iOS 15.0+, macOS 10.14+", source: .appleSDK, ios: 15.0, macos: 10.14),

        // Vision
        API(name: "VNImageRequestHandler", description: "Image analysis", category: "Vision", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "VNRecognizeTextRequest", description: "OCR text recognition", category: "Vision", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "VNDetectFaceRectanglesRequest", description: "Face detection", category: "Vision", availability: "iOS 11.0+, macOS 10.13+", source: .appleSDK, ios: 11.0, macos: 10.13),
        API(name: "VNGeneratePersonSegmentationRequest", description: "Person segmentation", category: "Vision", availability: "iOS 15.0+, macOS 12.0+", source: .appleSDK, ios: 15.0, macos: 12.0),

        // Natural Language
        API(name: "NLTokenizer", description: "Text tokenization", category: "Natural Language", availability: "iOS 12.0+, macOS 10.14+", source: .appleSDK, ios: 12.0, macos: 10.14),
        API(name: "NLTagger", description: "Part-of-speech tagging", category: "Natural Language", availability: "iOS 12.0+, macOS 10.14+", source: .appleSDK, ios: 12.0, macos: 10.14),
        API(name: "NLLanguageRecognizer", description: "Language detection", category: "Natural Language", availability: "iOS 12.0+, macOS 10.14+", source: .appleSDK, ios: 12.0, macos: 10.14),
        API(name: "NLEmbedding", description: "Word embeddings", category: "Natural Language", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),

        // Speech
        API(name: "SFSpeechRecognizer", description: "Speech-to-text", category: "Speech", availability: "iOS 10.0+, macOS 10.15+", source: .appleSDK, ios: 10.0, macos: 10.15),
        API(name: "AVSpeechSynthesizer", description: "Text-to-speech", category: "Speech", availability: "iOS 7.0+, macOS 10.14+", source: .appleSDK, ios: 7.0, macos: 10.14),

        // WebKit
        API(name: "WKWebView", description: "Web content display", category: "WebKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),
        API(name: "WKNavigationDelegate", description: "Web navigation handling", category: "WebKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),
        API(name: "WKScriptMessageHandler", description: "JS-Swift communication", category: "WebKit", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),

        // AuthenticationServices
        API(name: "ASAuthorizationController", description: "Sign in with Apple", category: "Authentication", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "ASWebAuthenticationSession", description: "OAuth web auth", category: "Authentication", availability: "iOS 12.0+, macOS 10.15+", source: .appleSDK, ios: 12.0, macos: 10.15),
        API(name: "LAContext", description: "Biometric authentication", category: "Authentication", availability: "iOS 8.0+, macOS 10.10+", source: .appleSDK, ios: 8.0, macos: 10.10),

        // Cryptography
        API(name: "CryptoKit", description: "Cryptographic operations", category: "Cryptography", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "SHA256/SHA384/SHA512", description: "Hash functions", category: "Cryptography", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "AES.GCM", description: "Symmetric encryption", category: "Cryptography", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: "P256/P384/P521", description: "Elliptic curve crypto", category: "Cryptography", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),

        // WidgetKit
        API(name: "Widget", description: "Home screen widgets", category: "WidgetKit", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: "TimelineProvider", description: "Widget timeline", category: "WidgetKit", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: "WidgetFamily", description: "Widget sizes", category: "WidgetKit", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),

        // App Intents
        API(name: "AppIntent", description: "Siri/Shortcuts integration", category: "App Intents", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),
        API(name: "AppShortcut", description: "App shortcuts", category: "App Intents", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),
        API(name: "AppEntity", description: "Shortcut entities", category: "App Intents", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),

        // Swift Charts
        API(name: "Chart", description: "Data visualization", category: "Swift Charts", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),
        API(name: "BarMark/LineMark/PointMark", description: "Chart marks", category: "Swift Charts", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),
        API(name: "ChartContent", description: "Chart content builder", category: "Swift Charts", availability: "iOS 16.0+, macOS 13.0+", source: .appleSDK, ios: 16.0, macos: 13.0),

        // TipKit
        API(name: "Tip", description: "Feature tips", category: "TipKit", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: "TipView", description: "Tip display", category: "TipKit", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),
        API(name: ".popoverTip", description: "Popover tips", category: "TipKit", availability: "iOS 17.0+, macOS 14.0+", source: .appleSDK, ios: 17.0, macos: 14.0),

        // Accessibility
        API(name: "AXCustomContent", description: "Custom accessibility content", category: "Accessibility", availability: "iOS 14.0+, macOS 11.0+", source: .appleSDK, ios: 14.0, macos: 11.0),
        API(name: ".accessibilityLabel", description: "VoiceOver label", category: "Accessibility", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: ".accessibilityHint", description: "VoiceOver hint", category: "Accessibility", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),
        API(name: ".accessibilityAction", description: "Custom actions", category: "Accessibility", availability: "iOS 13.0+, macOS 10.15+", source: .appleSDK, ios: 13.0, macos: 10.15),

        // Testing
        API(name: "XCTest", description: "Unit testing framework", category: "Testing", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "XCTestCase", description: "Test case class", category: "Testing", availability: "iOS 2.0+, macOS 10.0+", source: .appleSDK, ios: 2.0, macos: 10.0),
        API(name: "XCUIApplication", description: "UI testing", category: "Testing", availability: "iOS 9.0+, macOS 10.11+", source: .appleSDK, ios: 9.0, macos: 10.11),
        API(name: "Swift Testing (@Test)", description: "Modern testing framework", category: "Testing", availability: "iOS 18.0+, macOS 15.0+", source: .appleSDK, ios: 18.0, macos: 15.0),
        API(name: "#expect", description: "Swift Testing assertions", category: "Testing", availability: "iOS 18.0+, macOS 15.0+", source: .appleSDK, ios: 18.0, macos: 15.0),

        // ArgumentParser
        API(name: "ParsableCommand", description: "CLI command definition", category: "ArgumentParser", availability: "Swift Package", source: .appleSDK),
        API(name: "@Argument", description: "Positional argument", category: "ArgumentParser", availability: "Swift Package", source: .appleSDK),
        API(name: "@Option", description: "Named option", category: "ArgumentParser", availability: "Swift Package", source: .appleSDK),
        API(name: "@Flag", description: "Boolean flag", category: "ArgumentParser", availability: "Swift Package", source: .appleSDK),
    ]
}

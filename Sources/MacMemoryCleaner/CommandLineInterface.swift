import AppKit

/// Headless mode for scripts, Shortcuts, and cron. Run the binary inside the app bundle:
///
///     "/Applications/Mac Memory Cleaner.app/Contents/MacOS/MacMemoryCleaner" --clean
enum CommandLineInterface {
    private enum Command: Equatable {
        case stats, clean, status, setup, showRule, removeSetup, version, help
        case screenshots(directory: String)
    }

    private struct Invocation {
        var command: Command
        var json = false
        var demo = false
        var skipFlush = false
        var skipPressure = false
        var skipPurge = false
        var pressure: PressureStrength?
    }

    private struct UsageError: Error {
        let message: String
    }

    private static let commandNames: [String: Command] = [
        "--stats": .stats, "--clean": .clean, "--status": .status, "--setup": .setup,
        "--show-rule": .showRule, "--remove-setup": .removeSetup, "--version": .version,
        "--help": .help, "-h": .help,
    ]

    /// Any dash argument selects the command line, so a typo fails with a usage error
    /// instead of starting a second menu bar app. Arguments that macOS and Xcode pass to
    /// apps, such as `-NSDocumentRevisionsDebugMode YES`, still start the app.
    static func handles(_ arguments: [String]) -> Bool {
        let systemPrefixes = ["-NS", "-Apple", "-psn_", "-com.apple."]
        return arguments.contains { argument in
            argument.hasPrefix("-") && !systemPrefixes.contains { argument.hasPrefix($0) }
        }
    }

    static func run(_ arguments: [String]) -> Never {
        let invocation: Invocation
        do {
            invocation = try parse(arguments)
        } catch {
            printError("\(error.message)\nRun with --help for usage.")
            exit(64)
        }

        Task {
            exit(await execute(invocation))
        }
        if case .screenshots = invocation.command {
            // Rendering SwiftUI needs a running NSApplication, but not a Dock icon.
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.run()
        }
        dispatchMain()
    }

    // MARK: Parsing

    private static func parse(_ arguments: [String]) throws(UsageError) -> Invocation {
        var command: Command?
        var invocation = Invocation(command: .help)
        var remaining = arguments[...]

        func setCommand(_ new: Command, _ argument: String) throws(UsageError) {
            guard command == nil else { throw UsageError(message: "Use only one command. Found an extra \(argument).") }
            command = new
        }

        while let argument = remaining.popFirst() {
            if let named = commandNames[argument] {
                try setCommand(named, argument)
                continue
            }
            switch argument {
            case "--screenshots":
                guard let directory = remaining.popFirst(), !directory.hasPrefix("--") else {
                    throw UsageError(message: "--screenshots needs a folder, for example: --screenshots docs")
                }
                try setCommand(.screenshots(directory: directory), argument)
            case "--json": invocation.json = true
            case "--demo": invocation.demo = true
            case "--no-sync": invocation.skipFlush = true
            case "--no-pressure": invocation.skipPressure = true
            case "--no-purge": invocation.skipPurge = true
            case _ where argument.hasPrefix("--pressure="):
                let value = argument.dropFirst("--pressure=".count).lowercased()
                guard let strength = PressureStrength.allCases.first(where: { $0.rawValue == value || $0.title.lowercased() == value }) else {
                    throw UsageError(message: "--pressure must be standard or strong (or warn or critical).")
                }
                invocation.pressure = strength
            default:
                throw UsageError(message: "Unknown argument: \(argument)")
            }
        }

        invocation.command = command ?? .help
        if command == nil, arguments.contains(where: { $0 != "--help" && $0 != "-h" }) {
            throw UsageError(message: "Add a command, for example --stats or --clean.")
        }

        if invocation.pressure != nil && invocation.skipPressure {
            throw UsageError(message: "--pressure= and --no-pressure cannot be used together.")
        }
        let cleanOptionsUsed = invocation.skipFlush || invocation.skipPressure || invocation.skipPurge || invocation.pressure != nil
        if cleanOptionsUsed && invocation.command != .clean {
            throw UsageError(message: "--no-sync, --no-pressure, --no-purge, and --pressure= work only with --clean.")
        }
        if invocation.json && ![.stats, .clean, .status].contains(invocation.command) {
            throw UsageError(message: "--json works only with --stats, --clean, and --status.")
        }
        if invocation.demo, case .screenshots = invocation.command {} else if invocation.demo {
            throw UsageError(message: "--demo works only with --screenshots.")
        }
        return invocation
    }

    // MARK: Commands

    private static func execute(_ invocation: Invocation) async -> Int32 {
        Preference.registerDefaults()
        let json = invocation.json

        switch invocation.command {
        case .help:
            print(usage)
            return 0

        case .version:
            print("\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))")
            return 0

        case .stats:
            guard let snapshot = MemorySnapshot.current() else {
                printError("macOS did not report memory statistics.")
                return 1
            }
            print(json ? encode(snapshot) : describe(snapshot))
            return 0

        case .status:
            let installed = await AdminAccess.isInstalled()
            print(json ? encode(["adminAccess": installed]) : "Admin access: \(installed ? "set up" : "not set up")")
            return installed ? 0 : 2

        case .showRule:
            print(AdminAccess.sudoersRule)
            return 0

        case .setup:
            do {
                try await AdminAccess.install()
                print("Admin access is set up. Cleaning no longer needs your password.")
                return 0
            } catch {
                printError(error.localizedDescription)
                return 1
            }

        case .removeSetup:
            do {
                try await AdminAccess.uninstall()
                print("Admin access removed.")
                return 0
            } catch {
                printError(error.localizedDescription)
                return 1
            }

        case .clean:
            return await clean(invocation)

        case .screenshots(let directory):
            return await Screenshots.render(to: URL(filePath: directory), demo: invocation.demo)
        }
    }

    private static func clean(_ invocation: Invocation) async -> Int32 {
        var options = UserDefaults.standard.cleanOptions
        if invocation.skipFlush { options.flushWrites = false }
        if let pressure = invocation.pressure { options.pressureSignal = pressure }
        if invocation.skipPressure { options.pressureSignal = nil }
        if invocation.skipPurge { options.purgeDiskCache = false }
        guard !options.isEmpty else {
            printError("Every cleaning step is turned off. Turn one on in Settings › Cleaning.")
            return 64
        }

        let json = invocation.json
        guard let report = await Cleaner.clean(options: options, trigger: .commandLine, progress: { step in
            if !json { print(step.progressTitle) }
        }) else {
            printError("Another clean is already running.")
            return 1
        }

        if json {
            print(encode(report))
        } else {
            print("")
            print("Before  \(describe(report.before))")
            print("After   \(describe(report.after))")
            for result in report.steps {
                switch result.outcome {
                case .done: print("  ✓ \(result.step.title)")
                case .needsSetup: print("  – \(result.step.title): skipped. Run --setup once to allow it.")
                case .failed(let message): print("  ✗ \(result.step.title): \(message)")
                }
            }
            let seconds = report.duration.formatted(.number.precision(.fractionLength(1)))
            var sources: [String] = []
            if report.freed > 0, report.cachedFilesCleared > 0 { sources.append("cached files −\(ByteFormat.string(report.cachedFilesCleared))") }
            if report.freed > 0, report.appMemoryReleased > 0 { sources.append("app memory −\(ByteFormat.string(report.appMemoryReleased))") }
            let detail = sources.isEmpty ? "" : " (\(sources.joined(separator: ", ")))"
            print("Freed \(ByteFormat.string(max(report.freed, 0))) in \(seconds) s\(detail)")
        }

        if !report.failures.isEmpty { return 1 }
        return report.needsSetup ? 2 : 0
    }

    // MARK: Output

    private static func describe(_ snapshot: MemorySnapshot) -> String {
        [
            "used \(ByteFormat.string(snapshot.used)) of \(ByteFormat.string(snapshot.total))",
            "free \(ByteFormat.string(snapshot.free))",
            "cached files \(ByteFormat.string(snapshot.cachedFiles))",
            "compressed \(ByteFormat.string(snapshot.compressed))",
            "swap \(ByteFormat.string(snapshot.swapUsed))",
            "available \(snapshot.availablePercent)%",
            "pressure \(snapshot.pressure.title.lowercased())",
        ].joined(separator: " · ")
    }

    private static func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }

    private static let usage = """
        Usage: MacMemoryCleaner <command> [options]

        Without a command, the app starts in the menu bar.

        Commands:
          --stats              Print current memory use.
          --clean              Clean memory with the steps chosen in Settings.
              --no-sync            Skip "Flush pending writes".
              --no-pressure        Skip "Ask apps to release memory".
              --pressure=LEVEL     Signal strength: standard or strong.
              --no-purge           Skip "Purge disk cache".
          --status             Show whether admin access is set up. Exit status 2 if not.
          --setup              Set up admin access. Shows the macOS password prompt.
          --show-rule          Print the sudoers rule that --setup installs.
          --remove-setup       Remove admin access. Shows the macOS password prompt.
          --version            Print the app version.
          --help               Print this help.

        Options:
          --json               Print JSON. Works with --stats, --clean, and --status.

        Development:
          --screenshots DIR    Save PNG renders of the panel and Settings in DIR.
              --demo               Use sample data instead of this Mac's apps.

        Exit status: 0 success, 1 a step failed or another clean was running,
        2 admin access is not set up, 64 usage error.
        """
}

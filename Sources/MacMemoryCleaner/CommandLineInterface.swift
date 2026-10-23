import AppKit
import SwiftUI

/// Headless mode for scripts, Shortcuts, and cron. Run the binary inside the app bundle:
///
///     "/Applications/Mac Memory Cleaner.app/Contents/MacOS/MacMemoryCleaner" --clean
enum CommandLineInterface {
    private static let commands: Set<String> = ["--stats", "--clean", "--setup", "--show-rule", "--remove-setup", "--status", "--screenshots", "--help", "-h"]

    static func handles(_ arguments: [String]) -> Bool {
        arguments.contains { commands.contains($0) }
    }

    static func run(_ arguments: [String]) -> Never {
        Task {
            let status = await execute(arguments)
            exit(status)
        }
        if arguments.contains("--screenshots") {
            // Rendering SwiftUI needs a running NSApplication, but not a Dock icon.
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.run()
        }
        dispatchMain()
    }

    private static func execute(_ arguments: [String]) async -> Int32 {
        Preference.registerDefaults()
        let json = arguments.contains("--json")

        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            return 0
        }
        if arguments.contains("--stats") {
            let snapshot = MemorySnapshot.current()
            print(json ? encode(snapshot) : describe(snapshot))
            return 0
        }
        if arguments.contains("--status") {
            let installed = await AdminAccess.isInstalled()
            print(json ? encode(["adminAccess": installed]) : "Admin access: \(installed ? "set up" : "not set up")")
            return installed ? 0 : 2
        }
        if arguments.contains("--show-rule") {
            print(AdminAccess.sudoersRule)
            return 0
        }
        if arguments.contains("--setup") {
            do {
                try await AdminAccess.install()
                print("Admin access is set up. Deep clean no longer asks for a password.")
                return 0
            } catch {
                printError(error.localizedDescription)
                return 1
            }
        }
        if arguments.contains("--remove-setup") {
            do {
                try await AdminAccess.uninstall()
                print("Admin access removed.")
                return 0
            } catch {
                printError(error.localizedDescription)
                return 1
            }
        }
        if arguments.contains("--clean") {
            return await clean(arguments, json: json)
        }
        if let index = arguments.firstIndex(of: "--screenshots") {
            let directory = arguments.indices.contains(index + 1) ? arguments[index + 1] : "screenshots"
            return await Screenshots.render(to: URL(filePath: directory))
        }
        return 64
    }

    private static func clean(_ arguments: [String], json: Bool) async -> Int32 {
        var options = UserDefaults.standard.cleanOptions
        if arguments.contains("--no-sync") { options.flushWrites = false }
        if arguments.contains("--no-pressure") { options.pressureSignal = nil }
        if arguments.contains("--no-purge") { options.purgeDiskCache = false }
        if let value = arguments.first(where: { $0.hasPrefix("--pressure=") })?.split(separator: "=").last {
            guard let strength = PressureStrength(rawValue: String(value)) else {
                printError("--pressure must be warn or critical.")
                return 64
            }
            options.pressureSignal = strength
        }
        guard !options.isEmpty else {
            printError("Every cleaning step is turned off.")
            return 64
        }

        let report = await Cleaner.clean(options: options, trigger: .commandLine) { step in
            if !json { print(step.progressTitle) }
        }

        if json {
            print(encode(report))
        } else {
            print("")
            print("Before  \(describe(report.before))")
            print("After   \(describe(report.after))")
            for result in report.steps {
                switch result.outcome {
                case .done: print("  ✓ \(result.step.rawValue)")
                case .needsSetup: print("  – \(result.step.rawValue): skipped, run --setup once to allow it")
                case .failed(let message): print("  ✗ \(result.step.rawValue): \(message)")
                }
            }
            let seconds = report.duration.formatted(.number.precision(.fractionLength(1)))
            print("Freed \(ByteFormat.string(max(report.freed, 0))) in \(seconds) s")
        }

        if !report.failures.isEmpty { return 1 }
        return report.needsSetup ? 2 : 0
    }

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
        Usage: MacMemoryCleaner [command] [options]

        Without a command, the app starts in the menu bar.

        Commands:
          --stats            Print current memory use.
          --clean            Clean memory with the steps chosen in Settings.
              --no-sync          Skip flushing pending writes.
              --no-pressure      Skip the memory-pressure signal.
              --pressure=LEVEL   Signal level: warn or critical.
              --no-purge         Skip purging the disk cache.
          --status           Tell whether admin access is set up (exit 2 if not).
          --setup            Set up admin access. Shows the macOS password prompt.
          --show-rule        Print the sudoers rule that --setup installs.
          --remove-setup     Remove admin access.
          --screenshots DIR  Save PNG renders of the panel and settings to DIR.

        Options:
          --json             Print machine-readable output.

        Exit status: 0 success, 1 a step failed, 2 admin access is not set up.
        """
}

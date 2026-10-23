import Foundation

/// The two cleaning commands need root. A one-time setup installs a sudoers rule that lets
/// the current user run exactly these command lines without a password, and nothing else.
nonisolated enum AdminAccess {
    enum PrivilegedCommand: Sendable, CaseIterable {
        case purge
        case pressureSignal(PressureStrength)

        static let allCases: [PrivilegedCommand] = [.purge] + PressureStrength.allCases.map { .pressureSignal($0) }

        var arguments: [String] {
            switch self {
            case .purge:
                ["/usr/sbin/purge"]
            case .pressureSignal(let strength):
                ["/usr/bin/memory_pressure", "-S", "-l", strength.rawValue, "-s", "2"]
            }
        }
    }

    enum SetupError: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Setup was cancelled."
            case .failed(let output): "Setup failed: \(output)"
            }
        }
    }

    static let sudoersPath = "/private/etc/sudoers.d/macmemorycleaner"

    /// The rule names the account by numeric user ID, so no account name can turn into a
    /// sudoers keyword such as ALL. It defines no aliases, so it cannot clash with other rules.
    static var sudoersRule: String {
        let commands = PrivilegedCommand.allCases.map { $0.arguments.joined(separator: " ") }
        return [
            "# Added by Mac Memory Cleaner. It lets user ID \(getuid()) run the memory cleaning",
            "# commands below as root without a password. Remove it in the app Settings,",
            "# or run: sudo rm /etc/sudoers.d/macmemorycleaner",
            "#\(getuid()) ALL = (root) NOPASSWD: " + commands.joined(separator: ", "),
        ].joined(separator: "\n")
    }

    /// True when sudo runs every cleaning command without a password. `sudo -ll` shows the
    /// rule that matches each exact command line, and "!authenticate" means no password.
    static func isInstalled() async -> Bool {
        for command in PrivilegedCommand.allCases {
            let listing = await Shell.run("/usr/bin/sudo", ["-n", "-ll"] + command.arguments, timeout: .seconds(10))
            guard listing.succeeded, listing.output.contains("!authenticate") else { return false }
        }
        return true
    }

    static func run(_ command: PrivilegedCommand) async -> ShellResult {
        await Shell.run("/usr/bin/sudo", ["-n"] + command.arguments)
    }

    /// Shows the macOS administrator prompt once and installs the sudoers rule.
    static func install() async throws {
        // printf with single-quoted arguments keeps the rule free of shell expansion.
        // The rule must not contain single quotes.
        let lines = sudoersRule.split(separator: "\n").map { "'\($0)'" }.joined(separator: " ")

        // Write to a dot-file first (sudo ignores names with a dot), check it with visudo,
        // then move it into place. A broken rule never goes live.
        let script = [
            "set -e",
            "tmp=$(/usr/bin/mktemp /private/etc/sudoers.d/.macmemorycleaner.XXXXXX)",
            "trap '/bin/rm -f \"$tmp\"' EXIT",
            "/usr/bin/printf '%s\\n' \(lines) > \"$tmp\"",
            "/usr/sbin/chown root:wheel \"$tmp\"",
            "/bin/chmod 0440 \"$tmp\"",
            "/usr/sbin/visudo -cqf \"$tmp\"",
            "/bin/mv -f \"$tmp\" \(sudoersPath)",
        ].joined(separator: "; ")

        try await runAsAdministrator(
            script,
            prompt: "Mac Memory Cleaner needs your password once. After this, it can clean memory without asking."
        )
    }

    static func uninstall() async throws {
        try await runAsAdministrator(
            "/bin/rm -f \(sudoersPath)",
            prompt: "Mac Memory Cleaner needs your password to remove its admin access."
        )
    }

    private static func runAsAdministrator(_ shellScript: String, prompt: String) async throws {
        let appleScript = "do shell script \(appleScriptString(shellScript)) with prompt \(appleScriptString(prompt)) with administrator privileges"
        // The password prompt waits for the user, so give it far longer than a normal command.
        let result = await Shell.run("/usr/bin/osascript", ["-e", appleScript], timeout: .seconds(600))
        guard result.succeeded else {
            if result.output.contains("-128") { throw SetupError.cancelled }
            throw SetupError.failed(result.output)
        }
    }

    private static func appleScriptString(_ string: String) -> String {
        "\"" + string.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}

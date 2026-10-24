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

        /// The command as the sudoers rule spells it. In sudoers, a bare path allows any
        /// arguments, and `""` allows none.
        var sudoersCommand: String {
            arguments.count == 1 ? arguments[0] + " \"\"" : arguments.joined(separator: " ")
        }
    }

    enum SetupError: LocalizedError {
        case canceled
        case installFailed(String)
        case removeFailed(String)

        var errorDescription: String? {
            switch self {
            case .canceled: "You canceled the password prompt."
            case .installFailed(let output): "Couldn’t set up admin access: \(output)"
            case .removeFailed(let output): "Couldn’t remove admin access: \(output)"
            }
        }
    }

    /// One file per account, so two accounts on one Mac never overwrite each other's rule.
    /// sudo skips file names that contain a dot, so the name has none.
    static var sudoersPath: String { "/private/etc/sudoers.d/macmemorycleaner-\(getuid())" }

    /// Where builds before 1.0 put the rule. Setup and removal delete it.
    private static let legacySudoersPath = "/private/etc/sudoers.d/macmemorycleaner"

    /// The rule names the account by numeric user ID, so no account name can turn into a
    /// sudoers keyword such as ALL. It defines no aliases, so it cannot clash with other rules.
    static var sudoersRule: String {
        let commands = PrivilegedCommand.allCases.map(\.sudoersCommand)
        return [
            "# Added by Mac Memory Cleaner. It lets user ID \(getuid()) run the memory cleaning",
            "# commands below as root without a password. Remove it in the app Settings,",
            "# or run: sudo rm \(sudoersPath.replacing("/private/etc", with: "/etc"))",
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
        // Killing memory_pressure mid-run would leave macOS at the simulated level until the
        // next run, so a slow pressure signal is left to finish on its own.
        let killOnTimeout = if case .purge = command { true } else { false }
        return await Shell.run("/usr/bin/sudo", ["-n"] + command.arguments, killOnTimeout: killOnTimeout)
    }

    /// Shows the macOS administrator prompt once and installs the sudoers rule.
    static func install() async throws {
        // printf with single-quoted arguments keeps the rule free of shell expansion.
        // The rule must not contain single quotes. (It contains double quotes, which the
        // AppleScript string escapes.)
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
            "/bin/rm -f \(legacySudoersPath)",
        ].joined(separator: "; ")

        try await runAsAdministrator(
            script,
            prompt: "Mac Memory Cleaner wants to let your account run purge and memory_pressure as root without a password. You only need to do this once.",
            failure: SetupError.installFailed
        )
    }

    static func uninstall() async throws {
        try await runAsAdministrator(
            "/bin/rm -f \(sudoersPath) \(legacySudoersPath)",
            prompt: "Mac Memory Cleaner wants to remove the rule that lets it clean memory without your password.",
            failure: SetupError.removeFailed
        )
    }

    private static func runAsAdministrator(_ shellScript: String, prompt: String, failure: (String) -> SetupError) async throws {
        let appleScript = "do shell script \(appleScriptString(shellScript)) with prompt \(appleScriptString(prompt)) with administrator privileges"
        // The password prompt waits for the user, so give it far longer than a normal command.
        let result = await Shell.run("/usr/bin/osascript", ["-e", appleScript], timeout: .seconds(600))
        guard result.succeeded else {
            if result.output.contains("-128") { throw SetupError.canceled }
            throw failure(result.output)
        }
    }

    private static func appleScriptString(_ string: String) -> String {
        "\"" + string.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}

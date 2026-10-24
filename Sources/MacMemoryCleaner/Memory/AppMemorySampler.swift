import AppKit
import Darwin

/// A running app and the memory it holds, including its helper processes.
struct AppMemoryUsage: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let bytes: UInt64
    /// The app to quit. `nil` only for the sample rows of `--screenshots --demo`.
    let app: NSRunningApplication?

    init(app: NSRunningApplication, bytes: UInt64) {
        id = app.processIdentifier
        name = app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)"
        icon = app.icon ?? NSWorkspace.shared.icon(for: .application)
        self.bytes = bytes
        self.app = app
    }

    init(sampleID id: pid_t, name: String, appPath: String, bytes: UInt64) {
        self.id = id
        self.name = name
        // Resolve links: /Applications/Safari.app is one, and its icon would get an arrow badge.
        icon = NSWorkspace.shared.icon(forFile: URL(filePath: appPath).resolvingSymlinksInPath().path)
        self.bytes = bytes
        app = nil
    }
}

enum AppMemorySampler {
    /// Returns the apps that hold the most memory, biggest first.
    ///
    /// Each app's total is the physical footprint of every process macOS holds that app
    /// responsible for (browser tabs, renderers, XPC helpers), which is close to what
    /// Activity Monitor shows when you group by app.
    static func topApps(limit: Int) async -> [AppMemoryUsage] {
        let footprints = await footprintsByResponsiblePID()
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.processIdentifier != ownPID, !app.isTerminated else { return false }
                guard app.bundleIdentifier != "com.apple.finder" else { return false }
                switch app.activationPolicy {
                case .regular:
                    return true
                case .accessory:
                    // Third-party menu bar apps are fair game. Apple's own UI agents
                    // (Control Center, Spotlight, ...) relaunch the moment they quit.
                    return !(app.bundleIdentifier ?? "com.apple.").hasPrefix("com.apple.")
                default:
                    return false
                }
            }
            .compactMap { app in
                footprints[app.processIdentifier].map { AppMemoryUsage(app: app, bytes: $0) }
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map(\.self)
    }

    @concurrent
    private static func footprintsByResponsiblePID() async -> [pid_t: UInt64] {
        let capacity = Int(proc_listallpids(nil, 0)) + 128
        var pids = [pid_t](repeating: 0, count: capacity)
        let found = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }

        var totals: [pid_t: UInt64] = [:]
        for pid in pids.prefix(Int(max(found, 0))) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            // Fails with EPERM for other users' processes, which we skip anyway.
            guard status == 0 else { continue }
            totals[responsiblePID(for: pid), default: 0] += info.ri_phys_footprint
        }
        return totals
    }

    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t

    /// `responsibility_get_pid_responsible_for_pid` is the private libSystem call Activity
    /// Monitor uses to group helpers under their app. If it ever disappears, every process
    /// simply counts for itself.
    nonisolated private static let responsibilityFunction: ResponsibilityFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()

    nonisolated private static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let responsibilityFunction else { return pid }
        let responsible = responsibilityFunction(pid)
        return responsible > 0 ? responsible : pid
    }
}

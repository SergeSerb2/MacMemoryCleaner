import Foundation

/// How hard the memory-pressure signal pushes.
nonisolated enum PressureStrength: String, Sendable, CaseIterable, Identifiable {
    /// The "warn" level. Apps trim caches they can rebuild cheaply.
    case standard = "warn"
    /// The "critical" level. Apps release as much memory as they can.
    case strong = "critical"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .strong: "Strong"
        }
    }
}

nonisolated struct CleanOptions: Sendable {
    var flushWrites: Bool
    /// `nil` skips the memory-pressure signal.
    var pressureSignal: PressureStrength?
    var purgeDiskCache: Bool

    var isEmpty: Bool { !flushWrites && pressureSignal == nil && !purgeDiskCache }
}

nonisolated enum CleanStep: String, Sendable, Codable, CaseIterable {
    case flushWrites
    case releaseAppMemory
    case purgeDiskCache

    /// Matches the toggle in Settings › Cleaning.
    var title: String {
        switch self {
        case .flushWrites: "Flush pending writes"
        case .releaseAppMemory: "Ask apps to release memory"
        case .purgeDiskCache: "Purge disk cache"
        }
    }

    var progressTitle: String {
        switch self {
        case .flushWrites: "Flushing pending writes…"
        case .releaseAppMemory: "Asking apps to release memory…"
        case .purgeDiskCache: "Purging disk cache…"
        }
    }

    var needsAdmin: Bool { self != .flushWrites }
}

nonisolated enum StepOutcome: Sendable, Codable, Equatable {
    case done
    case needsSetup
    case failed(String)
}

nonisolated struct StepResult: Sendable, Codable {
    var step: CleanStep
    var outcome: StepOutcome
}

nonisolated enum CleanTrigger: Sendable, Codable, Equatable {
    case manual
    case hotKey
    case memoryPressure
    case lowAvailableMemory(percent: Int)
    case commandLine

    var title: String {
        switch self {
        case .manual: "Cleaned from the panel"
        case .hotKey: "Cleaned with the keyboard shortcut"
        case .memoryPressure: "Cleaned automatically: memory pressure"
        case .lowAvailableMemory(let percent): "Cleaned automatically: available memory fell to \(percent)%"
        case .commandLine: "Cleaned from the command line"
        }
    }
}

nonisolated struct CleanReport: Sendable, Codable {
    var trigger: CleanTrigger
    var finished: Date
    var duration: TimeInterval
    var before: MemorySnapshot
    var after: MemorySnapshot
    var steps: [StepResult]

    /// Growth in truly free RAM. Can be negative if something allocated during the clean.
    var freed: Int64 { Int64(after.free) - Int64(before.free) }

    /// Where the freed memory came from. Most of it is usually cached files, which macOS
    /// could also have dropped on its own; the rest is memory apps handed back.
    var cachedFilesCleared: Int64 { Int64(before.cachedFiles) - Int64(after.cachedFiles) }
    var appMemoryReleased: Int64 {
        Int64(before.appMemory + before.compressed) - Int64(after.appMemory + after.compressed)
    }

    var needsSetup: Bool { steps.contains { $0.outcome == .needsSetup } }

    var failures: [(step: CleanStep, message: String)] {
        steps.compactMap { result in
            if case .failed(let message) = result.outcome { (result.step, message) } else { nil }
        }
    }
}

enum Cleaner {
    private static let lastCleanFinishedKey = "state.lastCleanFinished"

    /// When the last clean in any process (app or command line) finished. A time in the
    /// future means the clock was set back, so it counts as long ago.
    static var lastCleanFinished: Date? {
        guard let date = UserDefaults.standard.object(forKey: lastCleanFinishedKey) as? Date, date <= .now else { return nil }
        return date
    }

    /// Runs the enabled steps in order and measures memory before and after. Returns `nil`
    /// without doing anything if another clean is running, in this process or another one.
    ///
    /// The order matters: flush writes so dirty pages become clean, signal pressure so apps
    /// hand back caches, then purge so the now-clean file cache leaves RAM.
    static func clean(
        options: CleanOptions,
        trigger: CleanTrigger,
        progress: (CleanStep) -> Void = { _ in }
    ) async -> CleanReport? {
        guard let lock = CleanLock.acquire() else { return nil }
        defer { lock.release() }

        let start = Date.now
        let before = MemorySnapshot.current() ?? .empty
        var results: [StepResult] = []

        if options.flushWrites {
            progress(.flushWrites)
            let result = await Shell.run("/bin/sync")
            results.append(StepResult(step: .flushWrites, outcome: result.succeeded ? .done : .failed(result.output)))
        }

        if let strength = options.pressureSignal {
            progress(.releaseAppMemory)
            results.append(StepResult(step: .releaseAppMemory, outcome: await runPrivileged(.pressureSignal(strength))))
        }

        if options.purgeDiskCache {
            progress(.purgeDiskCache)
            results.append(StepResult(step: .purgeDiskCache, outcome: await runPrivileged(.purge)))
        }

        // Apps answer the pressure signal asynchronously. Give them a moment before measuring.
        if results.contains(where: { $0.step.needsAdmin && $0.outcome == .done }) {
            try? await Task.sleep(for: .seconds(1))
        }

        UserDefaults.standard.set(Date.now, forKey: lastCleanFinishedKey)
        return CleanReport(
            trigger: trigger,
            finished: .now,
            duration: Date.now.timeIntervalSince(start),
            before: before,
            after: MemorySnapshot.current() ?? .empty,
            steps: results
        )
    }

    private static func runPrivileged(_ command: AdminAccess.PrivilegedCommand) async -> StepOutcome {
        let result = await AdminAccess.run(command)
        if result.succeeded { return .done }
        if result.output.contains("password is required") { return .needsSetup }
        return .failed(result.output.isEmpty ? "exit status \(result.status)" : result.output)
    }
}

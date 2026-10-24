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

nonisolated enum CleanResult: Sendable {
    case finished(CleanReport)
    /// Another clean was running, in this process or another one.
    case busy
    /// A clean finished less than `minimumGap` ago.
    case tooSoon
}

enum Cleaner {
    /// Runs the enabled steps in order and measures memory before and after.
    ///
    /// Only one clean runs at a time across all processes. With `minimumGap`, the clean
    /// also skips itself if any clean finished within that time; the check happens after
    /// taking the lock, so two processes can never both pass it.
    ///
    /// The order matters: flush writes so dirty pages become clean, signal pressure so apps
    /// hand back caches, then purge so the now-clean file cache leaves RAM.
    static func clean(
        options: CleanOptions,
        trigger: CleanTrigger,
        minimumGap: TimeInterval? = nil,
        progress: (CleanStep) -> Void = { _ in }
    ) async -> CleanResult {
        guard let lock = CleanLock.acquire() else { return .busy }
        if let minimumGap, let last = CleanLock.lastCleanFinished, Date.now.timeIntervalSince(last) < minimumGap {
            lock.release(finished: nil)
            return .tooSoon
        }

        let start = Date.now
        let before = MemorySnapshot.current()
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

        let finished = Date.now
        lock.release(finished: finished)
        // If one reading failed, report no change rather than a made-up difference.
        let after = MemorySnapshot.current()
        let measuredBefore = before ?? after ?? .empty
        return .finished(CleanReport(
            trigger: trigger,
            finished: finished,
            duration: finished.timeIntervalSince(start),
            before: measuredBefore,
            after: after ?? measuredBefore,
            steps: results
        ))
    }

    private static func runPrivileged(_ command: AdminAccess.PrivilegedCommand) async -> StepOutcome {
        let result = await AdminAccess.run(command)
        if result.succeeded { return .done }
        if result.output.contains("password is required") { return .needsSetup }
        return .failed(result.output.isEmpty ? "exit status \(result.status)" : result.output)
    }
}

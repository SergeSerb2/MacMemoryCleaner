import Foundation

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

    var progressTitle: String {
        switch self {
        case .flushWrites: "Writing pending changes to disk…"
        case .releaseAppMemory: "Asking apps to release memory…"
        case .purgeDiskCache: "Purging the disk cache…"
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
        case .manual: "Manual clean"
        case .hotKey: "Shortcut clean"
        case .memoryPressure: "Auto-clean: memory pressure"
        case .lowAvailableMemory(let percent): "Auto-clean: available memory at \(percent)%"
        case .commandLine: "Command-line clean"
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

    var needsSetup: Bool { steps.contains { $0.outcome == .needsSetup } }

    var failures: [String] {
        steps.compactMap { if case .failed(let message) = $0.outcome { message } else { nil } }
    }
}

enum Cleaner {
    /// Runs the enabled steps in order and measures memory before and after.
    ///
    /// The order matters: flush writes so dirty pages become clean, signal pressure so apps
    /// hand back caches, then purge so the now-clean file cache leaves RAM.
    static func clean(
        options: CleanOptions,
        trigger: CleanTrigger,
        progress: (CleanStep) -> Void = { _ in }
    ) async -> CleanReport {
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

        return CleanReport(
            trigger: trigger,
            finished: .now,
            duration: Date.now.timeIntervalSince(start),
            before: before,
            after: MemorySnapshot.current(),
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

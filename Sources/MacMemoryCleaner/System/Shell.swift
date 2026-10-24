import Foundation
import os

nonisolated struct ShellResult: Sendable {
    var status: Int32
    var output: String
    var timedOut = false

    var succeeded: Bool { status == 0 && !timedOut }
}

nonisolated enum Shell {
    /// Runs a program and waits for it without blocking the calling thread.
    ///
    /// After `timeout` the call returns even if the program is still running (for example
    /// `sync` stuck on a dead network volume). With `killOnTimeout`, the program also gets
    /// SIGTERM; sudo passes the signal on to the command it runs.
    static func run(
        _ executable: String,
        _ arguments: [String] = [],
        timeout: Duration = .seconds(120),
        killOnTimeout: Bool = true
    ) async -> ShellResult {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // One reader drains the pipe while the program runs, so a chatty program never
        // blocks on a full pipe. It stops at end of file, when the program exits.
        let output = OSAllocatedUnfairLock(initialState: Data())
        let outputRead = DispatchGroup()

        // Whichever of exit and timeout comes first resumes the continuation.
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let claim: @Sendable () -> Bool = { resumed.withLock { done in defer { done = true }; return !done } }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                // A child that keeps the pipe open must not hold up the result for long.
                _ = outputRead.wait(timeout: .now() + 2)
                guard claim() else { return }
                let data = output.withLock { $0 }
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: ShellResult(status: process.terminationStatus, output: text))
            }
            outputRead.enter()
            do {
                try process.run()
            } catch {
                outputRead.leave()
                process.terminationHandler = nil
                if claim() {
                    continuation.resume(returning: ShellResult(status: -1, output: error.localizedDescription))
                }
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                output.withLock { $0 = data }
                outputRead.leave()
            }
            Task {
                try? await Task.sleep(for: timeout)
                guard claim() else { return }
                if killOnTimeout { process.terminate() }
                continuation.resume(returning: ShellResult(
                    status: -1,
                    output: "Timed out after \(timeout.components.seconds) seconds.",
                    timedOut: true
                ))
            }
        }
    }
}

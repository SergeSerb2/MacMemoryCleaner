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
    /// `sync` stuck on a dead network volume), and the program gets SIGTERM. sudo passes the
    /// signal on to the command it runs.
    static func run(_ executable: String, _ arguments: [String] = [], timeout: Duration = .seconds(120)) async -> ShellResult {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Whichever of exit and timeout comes first resumes the continuation.
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let claim: @Sendable () -> Bool = { resumed.withLock { done in defer { done = true }; return !done } }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard claim() else { return }
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: ShellResult(status: process.terminationStatus, output: output))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                if claim() {
                    continuation.resume(returning: ShellResult(status: -1, output: error.localizedDescription))
                }
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                guard claim() else { return }
                process.terminate()
                continuation.resume(returning: ShellResult(
                    status: -1,
                    output: "Timed out after \(timeout.components.seconds) seconds.",
                    timedOut: true
                ))
            }
        }
    }
}

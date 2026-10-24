import Darwin
import Foundation

/// A lock that only one clean can hold at a time, across all processes of this user. The
/// lock file also records when the last clean finished.
///
/// It matters because a clean sends a system-wide memory-pressure signal. Without the lock,
/// a clean started from the command line would make the menu bar app auto-clean at the
/// same time.
nonisolated struct CleanLock {
    private let descriptor: Int32

    /// The per-user temporary folder from the system, not `$TMPDIR`, so the app and a
    /// command-line run with a different environment always use the same file.
    private static let path: String = {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        // `length` counts the terminating NUL.
        let directory = length > 1
            ? String(decoding: buffer.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : NSTemporaryDirectory()
        return (directory as NSString).appendingPathComponent("com.serbinenko.MacMemoryCleaner.clean.lock")
    }()

    /// Returns `nil` if another clean holds the lock. The kernel drops the lock if the
    /// holder crashes, so it can never stay stuck.
    static func acquire() -> CleanLock? {
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            // Clean anyway: a missed lock is better than a clean that never runs.
            Log.app.error("Cannot open the clean lock file: \(String(cString: strerror(errno)), privacy: .public)")
            return CleanLock(descriptor: -1)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return CleanLock(descriptor: descriptor)
    }

    /// When the last clean finished, in this process or another one. A time in the future
    /// means the clock was set back, so it counts as long ago.
    static var lastCleanFinished: Date? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        return date <= .now ? date : nil
    }

    /// Records `finished`, if given, then unlocks. Only the lock holder writes the file.
    func release(finished: Date?) {
        guard descriptor >= 0 else { return }
        if let finished {
            let bytes = Array(String(finished.timeIntervalSince1970).utf8)
            ftruncate(descriptor, 0)
            _ = pwrite(descriptor, bytes, bytes.count, 0)
        }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

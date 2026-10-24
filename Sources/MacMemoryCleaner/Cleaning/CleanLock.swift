import Darwin
import Foundation

/// A lock that only one clean can hold at a time, across all processes of this user.
///
/// It matters because a clean sends a system-wide memory-pressure signal. Without the lock,
/// a clean started from the command line would make the menu bar app auto-clean at the
/// same time.
nonisolated struct CleanLock {
    private let descriptor: Int32

    private static let path = FileManager.default.temporaryDirectory
        .appending(path: "com.serbinenko.MacMemoryCleaner.clean.lock").path

    /// Returns `nil` if another clean holds the lock. The kernel drops the lock if the
    /// holder crashes, so it can never stay stuck.
    static func acquire() -> CleanLock? {
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        // If the file cannot be opened, clean anyway: a missed lock is better than no clean.
        guard descriptor >= 0 else { return CleanLock(descriptor: -1) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return CleanLock(descriptor: descriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

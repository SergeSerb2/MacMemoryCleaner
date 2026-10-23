import os

/// View with: log stream --predicate 'subsystem == "com.serbinenko.MacMemoryCleaner"'
nonisolated enum Log {
    static let app = Logger(subsystem: "com.serbinenko.MacMemoryCleaner", category: "app")
}

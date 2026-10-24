import Darwin
import Foundation

/// The kernel's memory-pressure level, as reported by `kern.memorystatus_vm_pressure_level`.
nonisolated enum MemoryPressure: String, Sendable, Codable {
    case normal
    case warning
    case critical

    /// Maps the kernel's level (1, 2, or 4) to a case.
    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }
}

/// One reading of system memory, split the same way Activity Monitor splits it.
nonisolated struct MemorySnapshot: Sendable, Equatable, Codable {
    var total: UInt64
    /// Pages that hold nothing at all, like "Pages free" in `vm_stat`.
    var free: UInt64
    /// Anonymous memory owned by processes, minus purgeable memory.
    var appMemory: UInt64
    /// Memory the kernel cannot page out or compress.
    var wired: UInt64
    /// RAM taken up by the memory compressor.
    var compressed: UInt64
    /// File-backed pages (read-ahead pages included) plus purgeable memory. macOS can drop
    /// these at any time.
    var cachedFiles: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    /// Free RAM plus cached files, as a share of all RAM, 0–100. This is what macOS can
    /// hand out without compressing or swapping app memory. (`kern.memorystatus_level`
    /// is no good here: on macOS it counts app memory as available too.)
    var availablePercent: Int
    var pressure: MemoryPressure

    /// "Memory Used" in Activity Monitor.
    var used: UInt64 { appMemory + wired + compressed }

    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    /// Reads memory statistics from the kernel. Returns `nil` in the unlikely case the kernel
    /// refuses, instead of a reading of all zeros that would look like memory ran out.
    static func current() -> MemorySnapshot? {
        var hostPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &hostPageSize)
        let pageSize = UInt64(hostPageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let anonymous = UInt64(stats.internal_page_count) * pageSize
        // free_count includes speculative pages, which external_page_count counts too.
        let free = UInt64(stats.free_count > stats.speculative_count ? stats.free_count - stats.speculative_count : 0) * pageSize
        let cachedFiles = UInt64(stats.external_page_count) * pageSize + purgeable
        let total = ProcessInfo.processInfo.physicalMemory
        let swap: xsw_usage = sysctlValue("vm.swapusage") ?? xsw_usage()
        let pressureLevel: Int32 = sysctlValue("kern.memorystatus_vm_pressure_level") ?? 1

        return MemorySnapshot(
            total: total,
            free: free,
            appMemory: anonymous > purgeable ? anonymous - purgeable : 0,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            cachedFiles: cachedFiles,
            swapUsed: swap.xsu_used,
            swapTotal: swap.xsu_total,
            availablePercent: total == 0 ? 100 : Int((Double(free + cachedFiles) / Double(total) * 100).rounded()),
            pressure: MemoryPressure(kernelLevel: pressureLevel)
        )
    }

    /// Placeholder until the first reading arrives.
    static let empty = MemorySnapshot(
        total: ProcessInfo.processInfo.physicalMemory, free: 0, appMemory: 0, wired: 0, compressed: 0,
        cachedFiles: 0, swapUsed: 0, swapTotal: 0, availablePercent: 100, pressure: .normal
    )

    private static func sysctlValue<T>(_ name: String) -> T? {
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, value, &size, nil, 0) == 0 else { return nil }
        return value.pointee
    }
}

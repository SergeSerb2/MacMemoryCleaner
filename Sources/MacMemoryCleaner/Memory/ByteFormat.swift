import Foundation

nonisolated enum ByteFormat {
    /// Formats bytes the way Activity Monitor does (base 1024, one decimal).
    static func string(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return gib.formatted(.number.precision(.fractionLength(gib >= 100 ? 0 : 1))) + " GB"
        }
        let mib = Double(bytes) / 1_048_576
        return mib.formatted(.number.precision(.fractionLength(0))) + " MB"
    }

    static func string(_ bytes: Int64) -> String {
        bytes < 0 ? "−" + string(bytes.magnitude) : string(bytes.magnitude)
    }
}

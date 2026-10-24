import Foundation

nonisolated enum AppInfo {
    static let name = "Mac Memory Cleaner"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

    static let repository = URL(string: "https://github.com/SergeSerb2/MacMemoryCleaner")!
    static let issues = URL(string: "https://github.com/SergeSerb2/MacMemoryCleaner/issues")!
}

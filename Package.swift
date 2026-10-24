// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacMemoryCleaner",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "MacMemoryCleaner",
            path: "Sources/MacMemoryCleaner",
            swiftSettings: [
                // Everything runs on the main actor unless marked `nonisolated` or `@concurrent`.
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)

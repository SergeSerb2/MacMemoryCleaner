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
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TVRemote",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "TVRemote", targets: ["TVRemote"]),
    ],
    targets: [
        .target(
            name: "TVRemote",
            // Same settings as the app: MainActor default isolation and "Approachable Concurrency".
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

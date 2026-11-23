// swift-tools-version:5.9
import PackageDescription

// BedtimeCore is the platform-independent game engine: rules, content loading,
// deterministic RNG and save state. It imports only Foundation, so it builds
// and tests on macOS, iOS and Linux. The SwiftUI app (../App) depends on it.
let package = Package(
    name: "BedtimeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BedtimeCore", targets: ["BedtimeCore"]),
    ],
    targets: [
        .target(
            name: "BedtimeCore",
            resources: [.copy("Resources/content.json")]
        ),
        .testTarget(
            name: "BedtimeCoreTests",
            dependencies: ["BedtimeCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

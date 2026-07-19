// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIUsageWidget",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AIUsageWidget", targets: ["AIUsageWidget"])
    ],
    targets: [
        .executableTarget(
            name: "AIUsageWidget",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "AIUsageWidgetTests",
            dependencies: ["AIUsageWidget"]
        )
    ]
)

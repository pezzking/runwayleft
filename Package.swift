// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunwayLeft",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RunwayLeft", targets: ["RunwayLeft"])
    ],
    dependencies: [
        // Opens and closes the MenuBarExtra popover programmatically; SwiftUI has no public API for it.
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.1")
    ],
    targets: [
        .executableTarget(
            name: "RunwayLeft",
            dependencies: [
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "RunwayLeftTests",
            dependencies: ["RunwayLeft"]
        )
    ]
)

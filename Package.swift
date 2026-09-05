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
    targets: [
        .executableTarget(
            name: "RunwayLeft",
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

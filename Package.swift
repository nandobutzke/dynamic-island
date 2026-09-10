// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"])
    ],
    targets: [
        .executableTarget(
            name: "DynamicIsland",
            path: "Sources/DynamicIsland",
            exclude: ["graphify-out"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bt-flapper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bt-flapper", targets: ["BTFlapper"])
    ],
    targets: [
        .target(
            name: "BTFlapperCore",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "BTFlapper",
            dependencies: ["BTFlapperCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "BTFlapperTests",
            dependencies: ["BTFlapperCore"],
            path: "Tests/BTFlapperTests"
        )
    ]
)

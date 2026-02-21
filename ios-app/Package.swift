// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MooIOSRelay",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "MooIOSRelay", targets: ["MooIOSRelay"]),
        .executable(name: "MooIOSRelaySelfTest", targets: ["MooIOSRelaySelfTest"]),
    ],
    targets: [
        .target(
            name: "MooIOSRelay",
            path: "Sources/MooIOSRelay"
        ),
        .executableTarget(
            name: "MooIOSRelaySelfTest",
            dependencies: ["MooIOSRelay"],
            path: "Sources/MooIOSRelaySelfTest"
        ),
        .testTarget(
            name: "MooIOSRelayTests",
            dependencies: ["MooIOSRelay"],
            path: "Tests/MooIOSRelayTests"
        ),
    ]
)

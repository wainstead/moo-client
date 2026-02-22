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
        .library(name: "MooIOSCore", targets: ["MooIOSCore"]),
        .library(name: "MooIOSUI", targets: ["MooIOSUI"]),
        .executable(name: "MooIOSRelaySelfTest", targets: ["MooIOSRelaySelfTest"]),
        .executable(name: "MooIOSCoreFixtureRunner", targets: ["MooIOSCoreFixtureRunner"]),
    ],
    targets: [
        .target(
            name: "MooIOSRelay",
            path: "Sources/MooIOSRelay"
        ),
        .target(
            name: "MooIOSCore",
            path: "Sources/MooIOSCore"
        ),
        .target(
            name: "MooIOSUI",
            dependencies: ["MooIOSRelay", "MooIOSCore"],
            path: "Sources/MooIOSUI"
        ),
        .executableTarget(
            name: "MooIOSRelaySelfTest",
            dependencies: ["MooIOSRelay"],
            path: "Sources/MooIOSRelaySelfTest"
        ),
        .executableTarget(
            name: "MooIOSCoreFixtureRunner",
            dependencies: ["MooIOSCore"],
            path: "Sources/MooIOSCoreFixtureRunner"
        ),
        .testTarget(
            name: "MooIOSRelayTests",
            dependencies: ["MooIOSRelay", "MooIOSCore", "MooIOSUI"],
            path: "Tests/MooIOSRelayTests"
        ),
    ]
)

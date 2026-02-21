// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MooMacApp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "MooMacApp", targets: ["MooMacApp"]),
    ],
    targets: [
        .executableTarget(
            name: "MooMacApp",
            path: "Sources/MooMacApp"
        ),
    ]
)

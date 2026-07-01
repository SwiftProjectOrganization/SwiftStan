// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftStan",
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        .library(name: "SwiftStan", targets: ["SwiftStan"]),
        .executable(name: "swiftstan", targets: ["swiftstan-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SwiftStan"
        ),
        .executableTarget(
            name: "swiftstan-cli",
            dependencies: [
                "SwiftStan",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SwiftStanTests",
            dependencies: ["SwiftStan"],
            path: "Tests",
            resources: [.copy("TestDataFiles")]
        ),
    ]
)

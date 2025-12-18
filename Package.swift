// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UsefulThings",
    platforms: [.macOS("11.0"), .iOS("13.0"), .watchOS("10.0"), .tvOS("17.0"), .visionOS("1.0")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "UsefulThings",
            targets: ["UsefulThings"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "UsefulThings"),
        .testTarget(
            name: "UsefulThingsTests",
            dependencies: ["UsefulThings"]
        ),
    ]
)

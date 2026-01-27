// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UsefulThings",
    // Because we use FileHandle and it has
    // @available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *)
    // public func read(upToCount count: Int) throws -> Data?
    platforms: [.macOS("14.0"), .iOS("17.0"), .watchOS("7.0"), .tvOS("14.0"), .visionOS("1.0")],
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

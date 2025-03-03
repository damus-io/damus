// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "damus",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "damus",
            targets: ["damus"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jb55/secp256k1.swift.git", branch: "main")
    ],
    targets: [
        .target(
            name: "damus",
            dependencies: [
                .product(name: "secp256k1", package: "secp256k1.swift")
            ],
            path: "damus"),
        .testTarget(
            name: "damusTests",
            dependencies: ["damus"],
            path: "damusTests"),
    ]
)

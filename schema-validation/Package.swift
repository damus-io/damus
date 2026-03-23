// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kind1ValidationTests",
    dependencies: [
        .package(url: "https://github.com/nostrability/schemata-validator-swift.git", branch: "main")
    ],
    targets: [
        .testTarget(
            name: "Kind1ValidationTests",
            dependencies: [
                .product(name: "SchemataValidator", package: "schemata-validator-swift")
            ]
        )
    ]
)

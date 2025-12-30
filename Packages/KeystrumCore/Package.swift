// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KeystrumCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "KeystrumCore",
            targets: ["KeystrumCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3")
    ],
    targets: [
        .target(
            name: "KeystrumCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ]
        ),
    ]
)

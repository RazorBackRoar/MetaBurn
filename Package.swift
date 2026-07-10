// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MetaBurn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "MetaBurn",
            targets: ["MetaBurn"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MetaBurn",
            path: "Sources/MetaBurn",
            resources: [
                .process("Resources")
            ],
            swiftSettings: []
        ),

    ]
)

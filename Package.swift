// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MetaBurn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "MetaBurn",
            targets: ["MetaBurn"]
        ),
        .library(
            name: "MetaBurnCore",
            targets: ["MetaBurnCore"]
        )
    ],
    targets: [
        .target(
            name: "MetaBurnCore",
            path: "Sources/MetaBurnCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MetaBurn",
            dependencies: ["MetaBurnCore"],
            path: "Sources/MetaBurn",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MetaBurnTests",
            dependencies: ["MetaBurnCore"],
            path: "Tests/MetaBurnTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

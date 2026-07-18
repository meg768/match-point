// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MatchPoint",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MatchPoint", targets: ["MatchPoint"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MatchPoint",
            dependencies: [],
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)

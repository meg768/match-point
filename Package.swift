// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MatchRoom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MatchRoom", targets: ["MatchRoom"])
    ],
    targets: [
        .executableTarget(
            name: "MatchRoom",
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)

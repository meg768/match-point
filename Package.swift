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
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.9.1")
    ],
    targets: [
        .executableTarget(
            name: "MatchRoom",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio")
            ],
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)

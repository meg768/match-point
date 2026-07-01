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
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.9.1")
    ],
    targets: [
        .executableTarget(
            name: "MatchPoint",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio")
            ],
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)

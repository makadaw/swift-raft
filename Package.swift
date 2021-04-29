// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-raft",
    platforms: [.macOS("10.12")],
    products: [
        .library(
            name: "RaftNIO",
            targets: ["RaftNIO"]),
        .executable(
            name: "local-cluster",
            targets: ["local-cluster"]),
        .executable(
            name: "maelstrom-node",
            targets: ["maelstrom-node"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio",
            .revision("72f5a563286c395e60cc12fa1aecf345b559722e")),
        // Use version from main, wait for next release.
        .package(url: "https://github.com/apple/swift-system", .revision("2e9c1a71185c828416751283b40697725da550b6")),
        .package(url: "https://github.com/apple/swift-collections", from: "0.0.1"),
        .package(url: "https://github.com/apple/swift-log", from: "1.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "1.0.0-alpha.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.2"),
        .package(url: "https://github.com/Realm/SwiftLint", from: "0.43.0"),
    ],
    targets: [
        .target(
            name: "local-cluster",
            dependencies: [
                "RaftNIO",
                .product(name: "Lifecycle", package: "swift-service-lifecycle"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["Proto/example.proto"]),
        .target(
            name: "maelstrom-node",
            dependencies: [
                "MaelstromRaft",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Lifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-disable-availability-checking",
                    "-Xfrontend", "-enable-experimental-concurrency"
                ])
            ]),
        .target(
            name: "SwiftRaft",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-experimental-concurrency"])
            ]),
        .target(
            name: "RaftNIO",
            dependencies: [
                "SwiftRaft",
                .product(name: "_NIOConcurrency", package: "swift-nio"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: ["Proto/raft.proto"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-experimental-concurrency"])
            ]),
        .target(
            name: "MaelstromRaft",
            dependencies: [
                "SwiftRaft",
                "RaftNIO",
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-experimental-concurrency"])
            ]),
        /// Test tragets
        .testTarget(
            name: "SwiftRaftTests",
            dependencies: [
                "SwiftRaft"
            ]),
        .testTarget(
            name: "RaftNIOTests",
            dependencies: [
                "RaftNIO"
            ]),
        .testTarget(
            name: "MaelstromRaftTests",
            dependencies: [
                "MaelstromRaft"
            ]),
    ]
)

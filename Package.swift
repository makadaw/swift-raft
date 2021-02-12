// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-raft",
    platforms: [.macOS("10.12")],
    products: [
        .library(
            name: "Raft",
            targets: ["Raft"]),
        .executable(
            name: "LocalCluster",
            targets: ["LocalCluster"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "1.0.0-alpha.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.2"),
    ],
    targets: [
        .target(
            name: "LocalCluster",
            dependencies: [
                "Raft",
                .product(name: "Lifecycle", package: "swift-service-lifecycle"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["Proto/example.proto", "Proto/log.proto"]),
        .target(
            name: "Raft",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: ["Proto/raft.proto"]),
        .testTarget(
            name: "RaftTests",
            dependencies: [
                "Raft"
            ]),
    ]
)

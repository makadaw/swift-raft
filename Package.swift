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
    ],
    dependencies: [
        // Use version from main, wait for next release.
        // We need last commit `2e9c1a71185c828416751283b40697725da550b6` but currently it failed to compile
        // on the last toolchain. Wait until this MR will be in snapshot https://github.com/apple/swift/pull/35897
        .package(url: "https://github.com/apple/swift-system", .revision("920ef3085d4c0a3abad12bdaa265e0670db98fc0")),
        .package(url: "https://github.com/apple/swift-log", from: "1.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "1.0.0-alpha.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.2"),
    ],
    targets: [
        .target(
            name: "local-cluster",
            dependencies: [
                "RaftNIO",
                .product(name: "Lifecycle", package: "swift-service-lifecycle"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["Proto/example.proto", "Proto/log.proto"]),
        .target(
            name: "Raft",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-experimental-concurrency"])
            ]),
        .target(
            name: "RaftNIO",
            dependencies: [
                "Raft",
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: ["Proto/raft.proto"]),
        .testTarget(
            name: "RaftTests",
            dependencies: [
                "Raft"
            ]),
        .testTarget(
            name: "RaftNIOTests",
            dependencies: [
                "RaftNIO"
            ]),
    ]
)

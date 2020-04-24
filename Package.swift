// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "compress-nio",
    products: [
        .library(name: "CompressNIO", targets: ["CompressNIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.9.0"),
    ],
    targets: [
        .target(name: "CompressNIO", dependencies: ["NIO", "CCompressZlib", "CLZ4"]),
        .target(name: "CCompressZlib",
                dependencies: [],
                linkerSettings: [
                    .linkedLibrary("z")
                ]),
        .target(name: "CLZ4"),
        .testTarget(name: "CompressNIOTests", dependencies: ["CompressNIO"]),
    ]
)

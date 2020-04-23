// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "swift-nio-extras",
    products: [
        .library(name: "NIOCompress", targets: ["NIOCompress"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.9.0"),
    ],
    targets: [
        .target(name: "NIOCompress", dependencies: ["NIO", "CNIOCompressZlib"]),
        .target(name: "CNIOCompressZlib",
                dependencies: [],
                linkerSettings: [
                    .linkedLibrary("z")
                ]),
        .testTarget(name: "NIOCompressTests", dependencies: ["NIOCompress"]),
    ]
)

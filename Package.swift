// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "compress-nio",
    products: [
        .library(name: "CompressNIO", targets: ["CompressNIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
    ],
    targets: [
        .target(name: "CompressNIO", dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .byName(name: "CCompressZlib")
        ]),
        .target(
            name: "CCompressZlib",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(name: "CompressNIOTests", dependencies: ["CompressNIO"]),
    ]
)

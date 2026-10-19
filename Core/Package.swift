// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ESPCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "ESPCore", type: .static, targets: ["ESPCore"]),
    ],
    targets: [
        .target(name: "ESPCore"),
        .testTarget(name: "ESPCoreTests", dependencies: ["ESPCore"]),
    ]
)

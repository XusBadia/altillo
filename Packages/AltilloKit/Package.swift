// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AltilloKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AltilloCore", targets: ["AltilloCore"]),
        .library(name: "AltilloDesign", targets: ["AltilloDesign"]),
        .library(name: "AltilloUsage", targets: ["AltilloUsage"]),
    ],
    targets: [
        .target(name: "AltilloCore"),
        .target(name: "AltilloDesign", dependencies: ["AltilloCore"], resources: [.process("Resources")]),
        .target(name: "AltilloUsage", dependencies: ["AltilloCore"]),
        .testTarget(name: "AltilloCoreTests", dependencies: ["AltilloCore"]),
        .testTarget(name: "AltilloUsageTests", dependencies: ["AltilloUsage"]),
        .testTarget(name: "AltilloDesignTests", dependencies: ["AltilloDesign"]),
    ]
)

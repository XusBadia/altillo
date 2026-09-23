// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AltilloKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AltilloCore", targets: ["AltilloCore"]),
        .library(name: "AltilloDesign", targets: ["AltilloDesign"]),
    ],
    targets: [
        .target(name: "AltilloCore"),
        .target(name: "AltilloDesign", dependencies: ["AltilloCore"], resources: [.process("Resources")]),
        .testTarget(name: "AltilloCoreTests", dependencies: ["AltilloCore"]),
        .testTarget(name: "AltilloDesignTests", dependencies: ["AltilloDesign"]),
    ]
)

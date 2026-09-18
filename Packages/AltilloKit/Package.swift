// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AltilloKit",
    defaultLocalization: "es",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AltilloCore", targets: ["AltilloCore"]),
        .library(name: "AltilloDesign", targets: ["AltilloDesign"]),
    ],
    targets: [
        .target(name: "AltilloCore"),
        .target(name: "AltilloDesign", dependencies: ["AltilloCore"]),
        .testTarget(name: "AltilloCoreTests", dependencies: ["AltilloCore"]),
        .testTarget(name: "AltilloDesignTests", dependencies: ["AltilloDesign"]),
    ]
)

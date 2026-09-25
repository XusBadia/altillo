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
        .library(name: "AltilloAgents", targets: ["AltilloAgents"]),
    ],
    targets: [
        .target(name: "AltilloCore"),
        .target(name: "AltilloDesign", dependencies: ["AltilloCore"], resources: [.process("Resources")]),
        .target(name: "AltilloUsage", dependencies: ["AltilloCore"]),
        // Live agents (PLAN §5.3): hook payload parsers, the state machine, the danger classifier, session-file
        // readers and the hook <-> app wire protocol. Pure Foundation so `altillo-hook` can link it and stay fast.
        .target(name: "AltilloAgents", dependencies: ["AltilloCore"]),
        .testTarget(name: "AltilloCoreTests", dependencies: ["AltilloCore"]),
        .testTarget(name: "AltilloUsageTests", dependencies: ["AltilloUsage"]),
        .testTarget(name: "AltilloDesignTests", dependencies: ["AltilloDesign"]),
        .testTarget(name: "AltilloAgentsTests", dependencies: ["AltilloAgents"], resources: [.copy("Fixtures")]),
    ]
)

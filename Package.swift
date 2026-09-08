// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentAura",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AuraCore"),
        .target(name: "AuraHookFile", dependencies: ["AuraCore"]),
        .executableTarget(name: "aura-hook", dependencies: ["AuraCore", "AuraHookFile"]),
        .executableTarget(name: "AgentAuraApp", dependencies: ["AuraCore", "AuraHookFile"]),
        .testTarget(
            name: "AuraCoreTests",
            dependencies: ["AuraCore", "AuraHookFile"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

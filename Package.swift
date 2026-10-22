// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexTaskPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentPet", targets: ["AgentPet"])
    ],
    targets: [
        .executableTarget(
            name: "AgentPet",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)

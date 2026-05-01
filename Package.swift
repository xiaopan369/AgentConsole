// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgentConsoleWorkspace",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "AgentConsole",
            targets: ["AgentConsole"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "AgentConsole",
            path: "Sources/AgentConsole"
        ),
    ]
)

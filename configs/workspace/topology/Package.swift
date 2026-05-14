// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WorkspaceTopology",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ws-topology", targets: ["ws-topology"]),
        .executable(name: "ws-topologyd", targets: ["ws-topologyd"]),
        .executable(name: "ws-cheatsheet", targets: ["ws-cheatsheet"]),
        .executable(name: "ws-prompt", targets: ["ws-prompt"]),
        .executable(name: "ws-autohide", targets: ["ws-autohide"]),
        .executable(name: "ws-snap", targets: ["ws-snap"]),
        .library(name: "DisplayTopology", targets: ["DisplayTopology"]),
        .library(name: "LayoutPolicy", targets: ["LayoutPolicy"]),
        .library(name: "WorkspaceState", targets: ["WorkspaceState"]),
        .library(name: "AdaptersAppKit", targets: ["AdaptersAppKit"]),
        .library(name: "WsUI", targets: ["WsUI"]),
    ],
    targets: [
        .target(
            name: "DisplayTopology",
            path: "Sources/DisplayTopology"
        ),
        // Shared SwiftUI helpers used by every overlay binary. Tiny by
        // design — anything app-specific (palette, controllers) belongs
        // in the executable target.
        .target(
            name: "WsUI",
            path: "Sources/WsUI"
        ),
        .target(
            name: "LayoutPolicy",
            dependencies: ["DisplayTopology"],
            path: "Sources/LayoutPolicy"
        ),
        .target(
            name: "WorkspaceState",
            path: "Sources/WorkspaceState"
        ),
        .target(
            name: "AdaptersAppKitObjC",
            path: "Sources/AdaptersAppKit",
            sources: ["ObjCBridge.m"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "AdaptersAppKit",
            dependencies: ["DisplayTopology", "LayoutPolicy", "AdaptersAppKitObjC"],
            path: "Sources/AdaptersAppKit",
            exclude: ["ObjCBridge.m", "include"],
            sources: [
                "WorkspaceWindowDelegate.swift",
                "AccessibilityProbe.swift",
            ]
        ),
        .executableTarget(
            name: "ws-topology",
            dependencies: ["DisplayTopology", "LayoutPolicy", "WorkspaceState"],
            path: "Sources/ws-topology"
        ),
        .executableTarget(
            name: "ws-topologyd",
            dependencies: ["DisplayTopology", "LayoutPolicy", "WorkspaceState", "AdaptersAppKit"],
            path: "Sources/ws-topologyd"
        ),
        .executableTarget(
            name: "ws-cheatsheet",
            dependencies: ["DisplayTopology", "WsUI"],
            path: "Sources/ws-cheatsheet"
        ),
        .executableTarget(
            name: "ws-prompt",
            dependencies: ["WsUI"],
            path: "Sources/ws-prompt"
        ),
        .executableTarget(
            name: "ws-autohide",
            path: "Sources/ws-autohide"
        ),
        .executableTarget(
            name: "ws-snap",
            path: "Sources/ws-snap"
        ),
        .testTarget(
            name: "DisplayTopologyTests",
            dependencies: ["DisplayTopology"],
            path: "Tests/DisplayTopologyTests"
        ),
        .testTarget(
            name: "LayoutPolicyTests",
            dependencies: ["LayoutPolicy", "DisplayTopology"],
            path: "Tests/LayoutPolicyTests"
        ),
        .testTarget(
            name: "WorkspaceStateTests",
            dependencies: ["WorkspaceState"],
            path: "Tests/WorkspaceStateTests"
        ),
        .testTarget(
            name: "UITests",
            dependencies: ["AdaptersAppKit", "DisplayTopology", "LayoutPolicy"],
            path: "Tests/UITests"
        ),
    ]
)

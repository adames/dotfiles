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
        .library(name: "DisplayTopology", targets: ["DisplayTopology"]),
        .library(name: "LayoutPolicy", targets: ["LayoutPolicy"]),
        .library(name: "WorkspaceState", targets: ["WorkspaceState"]),
        .library(name: "AdaptersAppKit", targets: ["AdaptersAppKit"]),
    ],
    targets: [
        .target(
            name: "DisplayTopology",
            path: "Sources/DisplayTopology"
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

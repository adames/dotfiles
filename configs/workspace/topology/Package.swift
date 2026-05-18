// swift-tools-version:6.0
//
// The manifest is Swift 6.0 so we can declare Swift Testing test
// targets, but `swiftLanguageModes: [.v5]` keeps the rest of the code
// out of Swift 6's strict concurrency checking — that's a separate,
// much larger migration. Test targets opt themselves into Swift Testing
// just by `import Testing`.
//
// Running tests requires full Xcode, not Command Line Tools.
// CLT 26.5 ships the Testing.framework + lib_TestingInterop.dylib
// (so the test bundle compiles) and a `swiftpm-testing-helper` binary,
// but the helper silently no-ops on Swift Testing bundles — invoking
// the test entry point is something Xcode's test runner does and CLT
// doesn't. `swift build -c release` works fine on CLT; only `swift
// test` is blocked.
import PackageDescription

// Framework search path + explicit link + runtime rpath for Swift
// Testing under Command Line Tools. swiftc doesn't add CLT's
// Frameworks dir to its default search path, the linker doesn't pull
// Testing in without `-framework Testing`, and dyld doesn't know
// where to find Testing.framework at runtime without an rpath. All
// three are pinned to the same CLT Frameworks directory.
//
// Harmless when CLT isn't installed — swiftc / ld silently skip
// nonexistent `-F` and `-rpath` paths.
let cltFrameworksPath  = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltTestingLibPath  = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let swiftTestingSettings: [SwiftSetting] = [
    .unsafeFlags(["-F", cltFrameworksPath])
]
let swiftTestingLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-F", cltFrameworksPath,
        "-framework", "Testing",
        // dyld rpaths: Testing.framework lives in CLT's Frameworks dir,
        // its companion lib_TestingInterop.dylib lives in CLT's
        // Developer/usr/lib dir. Both rpaths are needed at runtime.
        "-Xlinker", "-rpath", "-Xlinker", cltFrameworksPath,
        "-Xlinker", "-rpath", "-Xlinker", cltTestingLibPath
    ])
]

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
        .executable(name: "ws-picker", targets: ["ws-picker"]),
        .executable(name: "ws-autohide", targets: ["ws-autohide"]),
        .executable(name: "ws-snap", targets: ["ws-snap"]),
        .executable(name: "ws-statusbar", targets: ["ws-statusbar"]),
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
            name: "ws-picker",
            dependencies: ["WsUI"],
            path: "Sources/ws-picker"
        ),
        .executableTarget(
            name: "ws-autohide",
            path: "Sources/ws-autohide"
        ),
        .executableTarget(
            name: "ws-snap",
            path: "Sources/ws-snap"
        ),
        .executableTarget(
            name: "ws-statusbar",
            dependencies: ["WorkspaceState"],
            path: "Sources/ws-statusbar"
        ),
        // Test targets use Swift Testing (`import Testing`) rather than
        // XCTest. The framework ships with the Swift toolchain, but
        // swiftc doesn't add Command Line Tools' Frameworks directory
        // to its default search path — so we have to point at it
        // explicitly. The path is harmless when not present (e.g. on a
        // box that uses Xcode rather than CLT for its toolchain).
        .testTarget(
            name: "DisplayTopologyTests",
            dependencies: ["DisplayTopology"],
            path: "Tests/DisplayTopologyTests",
            swiftSettings: swiftTestingSettings,
            linkerSettings: swiftTestingLinkerSettings
        ),
        .testTarget(
            name: "LayoutPolicyTests",
            dependencies: ["LayoutPolicy", "DisplayTopology"],
            path: "Tests/LayoutPolicyTests",
            swiftSettings: swiftTestingSettings,
            linkerSettings: swiftTestingLinkerSettings
        ),
        .testTarget(
            name: "WorkspaceStateTests",
            dependencies: ["WorkspaceState"],
            path: "Tests/WorkspaceStateTests",
            swiftSettings: swiftTestingSettings,
            linkerSettings: swiftTestingLinkerSettings
        ),
        .testTarget(
            name: "UITests",
            dependencies: ["AdaptersAppKit", "DisplayTopology", "LayoutPolicy"],
            path: "Tests/UITests",
            swiftSettings: swiftTestingSettings,
            linkerSettings: swiftTestingLinkerSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)

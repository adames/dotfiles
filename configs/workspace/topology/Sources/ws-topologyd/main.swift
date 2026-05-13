import AdaptersAppKit
import AppKit
import CoreGraphics
import DisplayTopology
import Foundation
import LayoutPolicy
import OSLog
import WorkspaceState

// The daemon needs NSScreen access, which requires a WindowServer connection.
// `LSUIElement=true` (set in the LaunchAgent plist) + `.accessory` activation
// policy keeps the process out of the Dock and command-tab.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let daemon = TopologyDaemon()
daemon.start()

app.run()

final class TopologyDaemon: @unchecked Sendable {
    let cacheDir: URL
    private lazy var coalescer: ReconfigCoalescer = ReconfigCoalescer { [weak self] in
        self?.publish()
    }
    private var lastTopologyJSON: String?
    private var lastLayoutEnv: String?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheDir = home.appendingPathComponent(".cache/workspace")
    }

    func start() {
        TopologyLog.topology.info("ws-topologyd starting; cache dir=\(self.cacheDir.path, privacy: .public)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        registerCGCallback()
        registerAppKitNotifications()
        publish()
    }

    private func registerCGCallback() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let status = CGDisplayRegisterReconfigurationCallback({ (_, _, userInfo) in
            guard let userInfo else { return }
            let daemon = Unmanaged<TopologyDaemon>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                daemon.coalescer.bump()
            }
        }, opaque)
        if status != .success {
            TopologyLog.topology.error("CGDisplayRegisterReconfigurationCallback failed: \(String(describing: status), privacy: .public)")
        }
    }

    private func registerAppKitNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.coalescer.bump()
        }
    }

    private func publish() {
        MainActor.assumeIsolated {
            self.publishOnMain()
        }
    }

    @MainActor
    private func publishOnMain() {
        let snapshot = DisplayTopologyService.snapshot()
        let access   = AccessibilityProbe.current()
        let policies = LayoutPolicyEngine.policies(
            for: snapshot.displays,
            reduceMotion: access.reduceMotion,
            increaseContrast: access.increaseContrast
        )

        do {
            let json = try CacheEncoding.encode(EnrichedTopology(
                topology: snapshot,
                policies: policies,
                accessibility: access
            ))
            if json != lastTopologyJSON {
                try CacheEncoding.atomicWrite(
                    json,
                    to: cacheDir.appendingPathComponent("topology.json")
                )
                lastTopologyJSON = json
                TopologyLog.topology.info("topology.json updated: \(snapshot.displays.count, privacy: .public) display(s)")
                logDiff(snapshot: snapshot, policies: policies)
            }
        } catch {
            TopologyLog.topology.error("topology.json encode failed: \(String(describing: error), privacy: .public)")
        }

        let env = LayoutEnvRenderer.render(
            snapshot: snapshot,
            policies: policies,
            accessibility: access
        )
        if env != lastLayoutEnv {
            do {
                try CacheEncoding.atomicWrite(
                    env,
                    to: cacheDir.appendingPathComponent("layout.env")
                )
                lastLayoutEnv = env
            } catch {
                TopologyLog.topology.error("layout.env write failed: \(String(describing: error), privacy: .public)")
            }
        }

        triggerSketchybar()
        firePostMutateHook()
    }

    private func logDiff(snapshot: TopologySnapshot, policies: LayoutPolicySet) {
        for d in snapshot.displays {
            TopologyLog.topology.debug("display id=\(d.id) builtIn=\(d.isBuiltIn) primary=\(d.isPrimaryMenuBarDisplay) frame=\(String(describing: d.framePoints), privacy: .public) density=\(d.densityClass.rawValue, privacy: .public)")
        }
        for p in policies.policies {
            TopologyLog.policy.debug("policy id=\(p.displayID) class=\(p.layoutClass.rawValue, privacy: .public) barH=\(p.barHeightPoints) maxSlots=\(p.maxVisibleSlots) aux=\(p.shouldUseAuxiliaryTopAreas)")
        }
    }

    private func triggerSketchybar() {
        runIfAvailable("/bin/sh", ["-c", "command -v sketchybar >/dev/null 2>&1 && sketchybar --trigger workspace_changed >/dev/null 2>&1"])
    }

    private func firePostMutateHook() {
        let hook = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/workspace/hooks/post-mutate.sh")
        guard FileManager.default.isExecutableFile(atPath: hook.path) else { return }
        runIfAvailable(hook.path, ["topology"])
    }

    private func runIfAvailable(_ launchPath: String, _ args: [String]) {
        let proc = Process()
        proc.launchPath = launchPath
        proc.arguments = args
        do { try proc.run() } catch { /* daemon swallows; the next bump will retry */ }
    }
}

import AppKit
import CoreGraphics
import Foundation

// MARK: - SketchyBar per-display autohide
//
// For each display, hide that display's pills (per-item y_offset=-100)
// when the cursor enters the top 2px of THAT display. macOS's auto-hide
// menu bar reveals on the same trigger, so the two strips tag-out
// display-locally. When the cursor leaves the trigger band, the pills
// slide back. Pills on other displays are unaffected.
//
// Why 100ms polling: an eventtap would need Input-Monitoring permission
// and wasn't reliable in practice (the old Lua module documented this
// trade-off). Cost per idle tick is now negligible — see the perf notes
// at AutohideDaemon's top — but the cadence stays at 100ms so the
// hide-on-edge response feels immediate.
//
// Replaces configs/hammerspoon-sketchybar-autohide.lua. Shipped as a
// launchd-managed daemon so Hammerspoon is no longer required.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let daemon = AutohideDaemon()
daemon.start()

app.run()

// MARK: - Daemon
//
// Steady-state per-tick cost is intentionally tiny:
//
//   1. CGEvent(source: nil).location           ~µs in-process call
//   2. screen-containing-point lookup           linear in NSScreen.screens, ~µs
//   3. displayIndexCache[DisplayKey(frame)]     dictionary lookup, ~µs
//   4. relY / menuBarInset arithmetic           ~ns
//   5. anyPopupMenuOpen() — GATED               only invoked when an
//                                               unhide path is reachable
//                                               (cursor below menu bar
//                                               OR some display is
//                                               currently hidden).
//                                               Most idle ticks skip it.
//
// Total: zero subprocess spawns when nothing's hidden and the cursor
// is mid-screen — which is the overwhelmingly common case. Compare
// to the previous shape, which spawned /bin/sh + yabai + jq AND ran
// CGWindowListCopyWindowInfo on every single tick (10/sec, all day).

final class AutohideDaemon {
    private let pollInterval: DispatchTimeInterval = .milliseconds(100)
    private let hideAtRelY: CGFloat = 2     // cursor inside top 2px of current display
    private let hiddenYOffset = -100
    private let shownYOffset  = 0

    private let yabaiPath: String?
    private let sketchybarPath: String?

    private var timer: DispatchSourceTimer?
    private var hiddenPerDisplay: [Int: Bool] = [:]
    private var screenObserver: NSObjectProtocol?

    /// Frame-keyed cache of yabai display indices. Rebuilt lazily on the
    /// next tick after `cacheDirty` flips true — set at init and on
    /// every `NSApplication.didChangeScreenParametersNotification`
    /// (display add/remove/reconfig). yabai re-numbers displays only on
    /// those same events, so the cache stays consistent.
    private var displayIndexCache: [DisplayKey: Int] = [:]
    private var cacheDirty: Bool = true

    init() {
        self.yabaiPath      = AutohideDaemon.findBinary(name: "yabai")
        self.sketchybarPath = AutohideDaemon.findBinary(name: "sketchybar")
    }

    deinit {
        if let obs = screenObserver { NotificationCenter.default.removeObserver(obs) }
        timer?.cancel()
    }

    func start() {
        guard yabaiPath != nil, sketchybarPath != nil else {
            FileHandle.standardError.write(Data(
                "ws-autohide: yabai or sketchybar not on PATH — exiting\n".utf8))
            exit(0)
        }

        // Invalidate the display-index cache whenever macOS reconfigures
        // screens. Cheaper + more correct than polling yabai every tick.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.cacheDirty = true }

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
    }

    // MARK: - Tick

    private func tick() {
        if cacheDirty {
            rebuildDisplayCache()
            cacheDirty = false
        }

        // CGEvent's mouseLocation uses CG (flipped) coords with origin at
        // the top of the primary display. NSScreen.screens uses AppKit
        // (un-flipped) coords. Match against AppKit by flipping the
        // cursor y into AppKit space.
        guard let event = CGEvent(source: nil) else { return }
        let cgLocation = event.location
        let appKitY = Self.appKitY(forCGY: cgLocation.y)
        let appKitPoint = CGPoint(x: cgLocation.x, y: appKitY)

        guard let screen = Self.screen(containing: appKitPoint) else { return }
        guard let yidx = displayIndexCache[DisplayKey(screen.frame)] else {
            // Cache miss → mark dirty so we rebuild next tick. Happens if
            // screen-config changed without a notification, or if yabai
            // wasn't up at the previous rebuild.
            cacheDirty = true
            return
        }

        let topOfDisplay = screen.frame.maxY
        let relY = topOfDisplay - appKitPoint.y
        let menuBarInset = screen.frame.maxY - screen.visibleFrame.maxY

        // Popup-menu suppression: NSMenu pull-downs (Apple menu, app
        // menu, status-bar drop-downs, right-click context menus) all
        // live at kCGPopUpMenuWindowLevel. When one is open we suppress
        // *unhide* paths so the pills don't bounce back while the user
        // is still navigating the menu (which extends below the trigger
        // band). The *hide* path is unaffected — entering the top 2 px
        // still hides as before.
        //
        // Gate: only query window list if we're potentially about to
        // unhide something. Cursor mid-screen with nothing hidden → no
        // popup query needed. That's the steady-state most of the day.
        let belowMenuBar  = relY >= menuBarInset
        let othersHidden  = hiddenPerDisplay.contains { $0.key != yidx && $0.value }
        let anyUnhidePath = belowMenuBar || othersHidden
        let popupOpen     = anyUnhidePath && Self.anyPopupMenuOpen()

        if relY < hideAtRelY {
            setDisplayHidden(yidx: yidx, hidden: true)
        } else if belowMenuBar && !popupOpen {
            setDisplayHidden(yidx: yidx, hidden: false)
        }

        // Any OTHER display the cursor isn't on should be shown — otherwise
        // it could stay hidden indefinitely after the cursor jumps from
        // its top edge into another display. Coarse popup gating: a popup
        // anywhere holds every hidden display. Acceptable because popups
        // are transient.
        if othersHidden && !popupOpen {
            for (other, hidden) in hiddenPerDisplay where other != yidx && hidden {
                setDisplayHidden(yidx: other, hidden: false)
            }
        }
    }

    // MARK: - Display-index cache

    /// Identity key for an NSScreen / yabai-display match. Rounding to
    /// integer points avoids floating-point equality flakiness — yabai
    /// reports `frame.x` as a JSON number which can drift slightly from
    /// what NSScreen reports for the same display.
    private struct DisplayKey: Hashable {
        let x: Int
        let y: Int
        let w: Int
        let h: Int
        init(_ frame: CGRect) {
            self.x = Int(frame.origin.x.rounded())
            self.y = Int(frame.origin.y.rounded())
            self.w = Int(frame.width.rounded())
            self.h = Int(frame.height.rounded())
        }
    }

    /// One yabai query → parse → fill cache. Parses JSON in-process via
    /// JSONSerialization (no /bin/sh + jq chain). Resilient to yabai
    /// being briefly unreachable — leaves cache empty, next miss flips
    /// dirty again.
    private func rebuildDisplayCache() {
        displayIndexCache = [:]
        guard let yabai = yabaiPath else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: yabai)
        task.arguments = ["-m", "query", "--displays"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return }
        guard task.terminationStatus == 0 else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        for display in arr {
            guard let idx = display["index"] as? Int,
                  let frame = display["frame"] as? [String: Any],
                  let x = frame["x"] as? Double,
                  let y = frame["y"] as? Double,
                  let w = frame["w"] as? Double,
                  let h = frame["h"] as? Double
            else { continue }
            let key = DisplayKey(
                CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
            )
            displayIndexCache[key] = idx
        }
    }

    // MARK: - Popup-menu detection
    //
    // CGWindowListCopyWindowInfo is a public CG call — no Accessibility,
    // no Screen Recording, no private framework. kCGWindowLayer/Bounds
    // are free fields that don't trigger the Screen-Recording prompt.
    // Moderately expensive (snapshots all on-screen windows) so the
    // caller gates on need.

    private static func anyPopupMenuOpen() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let popupLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return info.contains { ($0[kCGWindowLayer as String] as? Int) == popupLevel }
    }

    // MARK: - State change
    //
    // Fires once per transition, not per tick. setDisplayHidden is
    // idempotent on no-op (`if hiddenPerDisplay[yidx] == hidden` early
    // return) so callers don't have to gate.

    private func setDisplayHidden(yidx: Int, hidden: Bool) {
        if hiddenPerDisplay[yidx] == hidden { return }
        hiddenPerDisplay[yidx] = hidden
        let offset = hidden ? hiddenYOffset : shownYOffset
        guard let yabai = yabaiPath, let sketchybar = sketchybarPath else { return }

        // Bulk update: one shell pipeline yielding one sketchybar call per
        // space.* pill on this display, then a final set for the
        // workspace.name.<yidx> chip so it hides/shows in lockstep with
        // the pills it labels. Only path that still uses /bin/sh — and
        // it only fires on transitions, not every tick.
        let cmd = """
        \(yabai) -m query --spaces \
        | /usr/bin/jq -r '.[] | select(.display == \(yidx)) | .index' \
        | while read sid; do \(sketchybar) --set "space.$sid" y_offset=\(offset) >/dev/null 2>&1; done
        \(sketchybar) --set "workspace.name.\(yidx)" y_offset=\(offset) >/dev/null 2>&1
        """
        runShell(cmd)
    }

    // MARK: - Coordinate helpers

    private static func appKitY(forCGY cgY: CGFloat) -> CGFloat {
        // CG origin is at the top of the primary screen; AppKit origin
        // is at the bottom. `NSScreen.screens.first` is the primary.
        guard let primary = NSScreen.screens.first else { return cgY }
        return primary.frame.maxY - cgY
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        for s in NSScreen.screens where s.frame.contains(point) {
            return s
        }
        // Cursor briefly outside any screen during display reconfig —
        // fall back to whichever is main, the caller will retry next tick.
        return NSScreen.main
    }

    // MARK: - Shell helpers

    private static func findBinary(name: String) -> String? {
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func runShell(_ cmd: String) {
        let proc = Process()
        proc.launchPath = "/bin/sh"
        proc.arguments = ["-c", cmd]
        do { try proc.run() } catch { /* swallowed; next tick retries */ }
    }
}

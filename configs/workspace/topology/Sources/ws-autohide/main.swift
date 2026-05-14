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
// 100ms polling is intentional. An eventtap would need Input-Monitoring
// permission and wasn't reliable in practice (the old Lua module
// documented this trade-off). Cost per idle tick: one CGEvent location
// read + one screen lookup. Cost per transition: one yabai+sketchybar
// shell call. Negligible.
//
// Replaces configs/hammerspoon-sketchybar-autohide.lua. Shipped as a
// launchd-managed daemon so Hammerspoon is no longer required.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let daemon = AutohideDaemon()
daemon.start()

app.run()

final class AutohideDaemon {
    private let pollInterval: DispatchTimeInterval = .milliseconds(100)
    private let hideAtRelY: CGFloat = 2     // cursor inside top 2px of current display
    private let hiddenYOffset = -100
    private let shownYOffset  = 0

    private let yabaiPath: String?
    private let sketchybarPath: String?

    private var timer: DispatchSourceTimer?
    private var hiddenPerDisplay: [Int: Bool] = [:]

    init() {
        self.yabaiPath      = AutohideDaemon.findBinary(name: "yabai")
        self.sketchybarPath = AutohideDaemon.findBinary(name: "sketchybar")
    }

    func start() {
        guard yabaiPath != nil, sketchybarPath != nil else {
            FileHandle.standardError.write(Data("ws-autohide: yabai or sketchybar not on PATH — exiting\n".utf8))
            exit(0)
        }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
    }

    // MARK: - Tick

    private func tick() {
        // CGEvent's mouseLocation uses CG (flipped) coords with origin at
        // the top of the primary display. NSScreen.screens uses AppKit
        // (un-flipped) coords. We match against AppKit by flipping the
        // cursor y into AppKit space.
        guard let event = CGEvent(source: nil) else { return }
        let cgLocation = event.location
        let appKitY = AutohideDaemon.appKitY(forCGY: cgLocation.y)
        let appKitPoint = CGPoint(x: cgLocation.x, y: appKitY)

        guard let screen = AutohideDaemon.screen(containing: appKitPoint) else { return }
        guard let yidx = yabaiDisplayIndex(for: screen) else { return }

        // rel_y is "how far the cursor is from the top of this display"
        // in AppKit-relative coords where the menu bar sits at the top
        // of `frame` and is offset by (frame.maxY - visibleFrame.maxY).
        let topOfDisplay = screen.frame.maxY
        let relY = topOfDisplay - appKitPoint.y

        let menuBarInset = screen.frame.maxY - screen.visibleFrame.maxY

        // If a menu pull-down is open, suppress the *unhide* paths so the
        // pills don't bounce back while the user is still navigating an
        // Apple/app menu (which extends below the trigger band) or any
        // other popup at kCGPopUpMenuWindowLevel. The *hide* path is
        // unaffected — entering the top 2 px still hides as before.
        let popupOpen = anyPopupMenuOpen()

        if relY < hideAtRelY {
            setDisplayHidden(yidx: yidx, hidden: true)
        } else if relY >= menuBarInset && !popupOpen {
            setDisplayHidden(yidx: yidx, hidden: false)
        }

        // Any OTHER display the cursor isn't on should be shown — otherwise
        // it could stay hidden indefinitely after the cursor jumps from
        // its top edge into another display. Coarse popup gating: a popup
        // anywhere holds every hidden display. Acceptable because popups
        // are transient; per-display attribution is a future refinement.
        for (other, hidden) in hiddenPerDisplay where other != yidx && hidden && !popupOpen {
            setDisplayHidden(yidx: other, hidden: false)
        }
    }

    // MARK: - Popup-menu detection
    //
    // NSMenu pull-downs (Apple menu, app menu, status-bar drop-downs,
    // right-click context menus) all live at kCGPopUpMenuWindowLevel.
    // CGWindowListCopyWindowInfo is a public CG call — no Accessibility,
    // no Screen Recording, no private framework. kCGWindowLayer/Bounds
    // are free fields that don't trigger the Screen-Recording prompt.

    private func anyPopupMenuOpen() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let popupLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return info.contains { ($0[kCGWindowLayer as String] as? Int) == popupLevel }
    }

    // MARK: - State change

    private func setDisplayHidden(yidx: Int, hidden: Bool) {
        if hiddenPerDisplay[yidx] == hidden { return }
        hiddenPerDisplay[yidx] = hidden
        let offset = hidden ? hiddenYOffset : shownYOffset
        guard let yabai = yabaiPath, let sketchybar = sketchybarPath else { return }
        // Bulk update: one shell pipeline yielding one sketchybar call per
        // space.* pill on this display, then a final set for the
        // workspace.name.<yidx> chip so it hides/shows in lockstep with
        // the pills it labels. The redirect avoids any stray output the
        // launchd log might capture.
        let cmd = """
        \(yabai) -m query --spaces \
        | /usr/bin/jq -r '.[] | select(.display == \(yidx)) | .index' \
        | while read sid; do \(sketchybar) --set "space.$sid" y_offset=\(offset) >/dev/null 2>&1; done
        \(sketchybar) --set "workspace.name.\(yidx)" y_offset=\(offset) >/dev/null 2>&1
        """
        runShell(cmd)
    }

    // MARK: - Yabai display lookup
    //
    // Yabai reports display.frame in the same global coordinate space
    // NSScreen does, so equality on (x, y) is the canonical match. We
    // re-resolve every tick because display IDs renumber on hot-plug
    // and this is the cheapest reliable mapping. ~ms-fast yabai RPC.

    private func yabaiDisplayIndex(for screen: NSScreen) -> Int? {
        guard let yabai = yabaiPath else { return nil }
        let f = screen.frame
        let cmd = """
        \(yabai) -m query --displays \
        | /usr/bin/jq '[.[] | select(.frame.x == \(f.origin.x) and .frame.y == \(f.origin.y)) | .index] | first'
        """
        guard let out = captureShell(cmd) else { return nil }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
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

    private func captureShell(_ cmd: String) -> String? {
        let proc = Process()
        proc.launchPath = "/bin/sh"
        proc.arguments = ["-c", cmd]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

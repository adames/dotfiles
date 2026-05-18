import AppKit
import Foundation

/// Workspace status bar indicator using NSStatusItem.
/// Shows colored pills for each workspace with current one highlighted.
/// Replaces the SketchyBar-based workspace pill strip.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = StatusBarController()
controller.start()
app.run()

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var workspaces: [WorkspaceInfo] = []
    private var currentSlot: Int = 1
    private var configPath: String {
        ProcessInfo.processInfo.environment["WS_CONFIG"]
            ?? "\(NSHomeDirectory())/.config/workspace/spaces.json"
    }
    
    func start() {
        setupMenu()
        
        // Initial load
        loadWorkspaces()
        updateDisplay()
        
        // Listen for workspace changes via DistributedNotification
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleWorkspaceChanged),
            name: .init("workspace_changed"),
            object: nil
        )
        
        // Also poll periodically as fallback (every 2 seconds)
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.loadWorkspaces()
            self?.updateDisplay()
        }
    }
    
    private func setupMenu() {
        let menu = setupStaticMenu()
        statusItem.menu = menu
        menu.delegate = self
    }
    
    /// Called just before menu opens - rebuild with current workspaces
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        
        // Clear existing items (keep first two: Workspaces header + separator)
        while menu.items.count > 2 {
            menu.removeItem(at: 2)
        }
        
        // Add workspace items
        for workspace in workspaces {
            let item = NSMenuItem(
                title: "\(workspace.index): \(workspace.name)",
                action: #selector(menuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = workspace.index
            item.state = workspace.index == currentSlot ? .on : .off
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    /// Initial menu setup - creates static header items only
    private func setupStaticMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        return menu
    }
    
    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        let slot = sender.tag
        focusWorkspace(slot: slot)
    }
    
    @objc private func refresh() {
        loadWorkspaces()
        updateDisplay()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func handleWorkspaceChanged() {
        loadWorkspaces()
        updateDisplay()
    }
    
    private func loadWorkspaces() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let slots = json["slots"] as? [[String: Any]] else {
            return
        }
        
        var newWorkspaces: [WorkspaceInfo] = []
        for (index, slot) in slots.enumerated() {
            let slotIndex = index + 1
            let name = slot["name"] as? String ?? "\(slotIndex)"
            let icon = slot["icon"] as? String
            let colorHex = slot["color"] as? String
            
            newWorkspaces.append(WorkspaceInfo(
                index: slotIndex,
                name: name,
                icon: icon,
                colorHex: colorHex
            ))
        }
        
        // Determine current slot from yabai or cache
        currentSlot = getCurrentSlot()
        workspaces = newWorkspaces
    }
    
    private func getCurrentSlot() -> Int {
        // Try to read from yabai directly
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "yabai -m query --spaces --space 2>/dev/null | jq '.index' 2>/dev/null || echo 1"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let index = Int(output), index > 0 {
                return index
            }
        } catch {
            // Fall through to cache
        }
        
        // Fallback: read from cache file
        let cachePath = "\(NSHomeDirectory())/.cache/workspace/current.env"
        if let content = try? String(contentsOfFile: cachePath, encoding: .utf8),
           let match = content.range(of: "WORKSPACE_SLOT=[0-9]+", options: .regularExpression),
           let slotStr = content[match].split(separator: "=").last,
           let slot = Int(slotStr) {
            return slot
        }
        
        return 1
    }
    
    private func updateDisplay() {
        let attributedTitle = renderPills()
        statusItem.button?.attributedTitle = attributedTitle
    }
    
    private func renderPills() -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        for workspace in workspaces {
            let isCurrent = workspace.index == currentSlot
            let pill = renderPill(workspace: workspace, isCurrent: isCurrent)
            result.append(pill)
            result.append(NSAttributedString(string: "  "))
        }
        
        return result
    }
    
    private func renderPill(workspace: WorkspaceInfo, isCurrent: Bool) -> NSAttributedString {
        // Get color from hex or use default
        let color = colorFromHex(workspace.colorHex) ?? NSColor.systemGray
        
        // Use icon if available, otherwise number
        let text: String
        if let icon = workspace.icon, !icon.isEmpty {
            text = icon
        } else {
            text = "\(workspace.index)"
        }
        
        var attributes: [NSAttributedString.Key: Any] = [:]
        
        if isCurrent {
            // Current: filled background, dark text
            attributes[.foregroundColor] = NSColor.black
            attributes[.backgroundColor] = color
            attributes[.font] = NSFont.systemFont(ofSize: 12, weight: .bold)
        } else {
            // Inactive: no background, colored text
            attributes[.foregroundColor] = color
            attributes[.font] = NSFont.systemFont(ofSize: 12)
        }
        
        // Add some padding via paragraph style
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributes[.paragraphStyle] = paragraph
        
        return NSAttributedString(string: " \(text) ", attributes: attributes)
    }
    
    private func colorFromHex(_ hex: String?) -> NSColor? {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        
        var hexSanitized = hex
        if hexSanitized.hasPrefix("#") {
            hexSanitized = String(hexSanitized.dropFirst())
        }
        
        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }
        
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        
        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    private func focusWorkspace(slot: Int) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "yabai -m space --focus \(slot) 2>/dev/null || true"]
        try? task.run()
    }
}

struct WorkspaceInfo {
    let index: Int
    let name: String
    let icon: String?
    let colorHex: String?
}

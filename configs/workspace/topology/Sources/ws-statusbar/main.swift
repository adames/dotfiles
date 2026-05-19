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
        
        // Debug: log what we loaded
        let workspaceCount = workspaces.count
        let debugMsg = "ws-statusbar: loaded \(workspaceCount) workspaces, current=\(currentSlot)\n"
        FileHandle.standardError.write(Data(debugMsg.utf8))
        
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
        
        // Add workspace items: "# name" with SF Symbol icon on right
        for workspace in workspaces {
            let displayName = workspace.name.isEmpty ? "ws\(workspace.index)" : workspace.name
            let title = "\(workspace.index)  \(displayName)"
            
            let item = NSMenuItem(
                title: title,
                action: #selector(menuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = workspace.index
            item.state = workspace.index == currentSlot ? .on : .off
            
            // Set SF Symbol image on right (Apple menu bar aesthetic like Karabiner)
            let sfName = iconForWorkspace(name: workspace.name)
            if let image = NSImage(systemSymbolName: sfName, accessibilityDescription: nil) {
                // White tint for menu bar consistency
                image.isTemplate = true
                item.image = image
            }
            
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Workspace actions section
        let changeItem = NSMenuItem(
            title: "Change...",
            action: #selector(openChangeWorkspace),
            keyEquivalent: "c"
        )
        changeItem.target = self
        menu.addItem(changeItem)
        
        let focusItem = NSMenuItem(
            title: "Focus",
            action: #selector(openFocusWorkspace),
            keyEquivalent: "f"
        )
        focusItem.target = self
        menu.addItem(focusItem)
        
        let goItem = NSMenuItem(
            title: "Go",
            action: #selector(openGoWorkspace),
            keyEquivalent: "g"
        )
        goItem.target = self
        menu.addItem(goItem)
        
        let editItem = NSMenuItem(
            title: "Edit...",
            action: #selector(openEditWorkspace),
            keyEquivalent: "e"
        )
        editItem.target = self
        menu.addItem(editItem)
        
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
    
    /// Returns SF Symbol name for workspace type (Apple menu bar aesthetic)
    private func iconForWorkspace(name: String) -> String {
        let lowerName = name.lowercased()
        
        switch lowerName {
        case "home", "main", "start":
            return "house.fill"
        case "web", "browser", "internet", "www":
            return "globe"
        case "code", "dev", "ide", "programming", "swift", "python":
            return "chevron.left.forwardslash.chevron.right"
        case "term", "shell", "zsh", "bash", "console", "cli":
            return "terminal.fill"
        case "ai", "ml", "gpt", "claude", "llm", "neural":
            return "brain.head.profile"
        case "git", "github", "vcs", "repo", "source":
            return "arrow.triangle.branch"
        case "db", "database", "sql", "postgres", "mysql":
            return "cylinder.split.1x2.fill"
        case "docker", "container", "k8s", "kubernetes":
            return "shippingbox.fill"
        case "mail", "email", "inbox", "gmail":
            return "envelope.fill"
        case "chat", "slack", "discord", "messages", "im":
            return "bubble.left.fill"
        case "docs", "notes", "obsidian", "wiki", "notion":
            return "doc.text.fill"
        case "music", "audio", "spotify", "applemusic":
            return "music.note"
        case "video", "media", "youtube", "netflix":
            return "play.rectangle.fill"
        case "cloud", "aws", "azure", "gcp", "dropbox":
            return "cloud.fill"
        case "monitor", "logs", "metrics", "grafana", "prometheus":
            return "chart.line.uptrend.xyaxis"
        case "test", "testing", "spec", "pytest":
            return "checkmark.seal.fill"
        case "build", "ci", "pipeline", "jenkins":
            return "hammer.fill"
        case "calendar", "schedule", "meetings":
            return "calendar"
        case "settings", "config", "prefs", "system":
            return "gearshape.fill"
        case "shop", "store", "cart", "amazon":
            return "cart.fill"
        case "social", "twitter", "mastodon", "bluesky", "x":
            return "at"
        case "games", "gaming", "steam":
            return "gamecontroller.fill"
        case "photos", "images", "gallery":
            return "photo.fill"
        case "design", "figma", "sketch":
            return "paintbrush.fill"
        case "security", "vpn", "1password", "bitwarden":
            return "lock.fill"
        case "news", "rss", "reading":
            return "newspaper.fill"
        case "finance", "money", "banking":
            return "dollarsign.circle.fill"
        case "health", "fitness", "workout":
            return "heart.fill"
        case "travel", "maps", "navigation":
            return "map.fill"
        default:
            return "square.grid.2x2"  // Generic workspace grid
        }
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
    
    // MARK: - Workspace Actions
    
    @objc private func openChangeWorkspace() {
        // "change" mode opens ws-picker (window-based workspace change)
        spawnProcess(name: "ws-picker", args: [])
    }
    
    @objc private func openFocusWorkspace() {
        spawnProcess(name: "ws-prompt", args: ["focus"])
    }
    
    @objc private func openGoWorkspace() {
        // "send" mode moves window and follows it (go/send)
        spawnProcess(name: "ws-prompt", args: ["send"])
    }
    
    @objc private func openEditWorkspace() {
        // "manage" mode for edit workspace
        spawnProcess(name: "ws-prompt", args: ["manage"])
    }
    
    private func spawnProcess(name: String, args: [String]) {
        let task = Process()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binaryPath = home.appendingPathComponent(".local/bin/\(name)").path
        task.launchPath = binaryPath
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.environment = ProcessInfo.processInfo.environment
        do {
            try task.run()
        } catch {
            print("Failed to launch \(name) at \(binaryPath): \(error)")
        }
    }
    
    @objc private func handleWorkspaceChanged() {
        loadWorkspaces()
        updateDisplay()
    }
    
    private func loadWorkspaces() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let spaces = json["spaces"] as? [String: [String: Any]] else {
            return
        }
        
        var newWorkspaces: [WorkspaceInfo] = []
        
        // Sort by slot number to maintain order
        let sortedKeys = spaces.keys.compactMap(Int.init).sorted()
        for slotIndex in sortedKeys {
            let key = String(slotIndex)
            guard let slot = spaces[key] else { continue }
            
            let name = slot["name"] as? String ?? "\(slotIndex)"
            
            // Icon can be from 'icon' field or extracted from iconSpec
            var icon = slot["icon"] as? String
            if icon == nil, let iconSpec = slot["iconSpec"] as? [String: Any] {
                // Try codepoint first, then symbolName, then fallbackText
                if let codepoint = iconSpec["codepoint"] as? String {
                    // Decode \uXXXX escape sequences to actual unicode characters
                    icon = decodeUnicodeEscapes(codepoint)
                }
                if icon == nil {
                    icon = iconSpec["symbolName"] as? String
                }
                if icon == nil {
                    icon = iconSpec["fallbackText"] as? String
                }
            }
            
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
        // Elevation design: current workspace sits on a "platform" (_n_)
        // Others are flat, creating visual hierarchy of elevation
        let text: String
        if isCurrent {
            // Current: raised on underscore platform (appears elevated)
            text = "_\(workspace.index)_"
        } else {
            // Others: flat baseline (appears lower)
            text = " \(workspace.index) "
        }
        
        let color = NSColor.white
        // Current is bold and larger (visually more prominent)
        let fontSize: CGFloat = isCurrent ? 14 : 11
        let weight: NSFont.Weight = isCurrent ? .bold : .regular
        
        return NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight)
            ]
        )
    }
    
    /// Map workspace name/index to SF Symbol name
    private func sfSymbolForWorkspace(name: String, index: Int) -> String {
        let lowerName = name.lowercased()
        
        // Common workspace mappings
        switch lowerName {
        case "home", "main", "start":
            return "house.fill"
        case "web", "browser", "internet", "www":
            return "globe"
        case "code", "dev", "programming", "ide":
            return "terminal.fill"
        case "ai", "ml", "gpt", "claude", "llm":
            return "cpu.fill"
        case "mail", "email", "inbox":
            return "envelope.fill"
        case "chat", "slack", "discord", "messages":
            return "bubble.left.fill"
        case "music", "audio", "spotify":
            return "music.note"
        case "video", "youtube", "media":
            return "play.rectangle.fill"
        case "docs", "documents", "files", "notes", "obsidian":
            return "doc.text.fill"
        case "term", "shell", "zsh", "bash":
            return "terminal"
        case "git", "github", "vcs":
            return "number"
        case "docker", "container":
            return "shippingbox.fill"
        case "db", "database", "sql":
            return "cylinder.split.1x2.fill"
        case "test", "testing":
            return "checkmark.shield.fill"
        case "build", "ci", "pipeline":
            return "hammer.fill"
        case "cloud", "aws", "azure", "gcp":
            return "cloud.fill"
        case "monitor", "metrics", "logs", "grafana":
            return "chart.line.uptrend.xyaxis"
        case "social", "twitter", "x", "mastodon":
            return "person.2.fill"
        case "shop", "store", "ecommerce":
            return "cart.fill"
        case "calendar", "schedule", "plan":
            return "calendar"
        case "settings", "config", "prefs":
            return "gear"
        default:
            // Fallback: use numbered circle or square
            if index <= 12 {
                return "\(index).circle.fill"
            } else {
                return "\(index).square.fill"
            }
        }
    }
    
    /// ASCII art icons for menu dropdown - minimal & delightful
    private func asciiIconForWorkspace(name: String, index: Int) -> String {
        let lowerName = name.lowercased()
        
        switch lowerName {
        case "home", "main", "start":
            return "<🏠>"  // Home
        case "web", "browser", "internet", "www":
            return "</>"   // Web/Code
        case "code", "dev", "ide", "programming":
            return "{ }"   // Code braces
        case "term", "shell", "zsh", "bash", "console":
            return "$_"   // Terminal prompt
        case "ai", "ml", "gpt", "claude", "llm":
            return "(*)"  // AI/brain
        case "git", "github", "vcs", "repo":
            return "(Y)"  // Git branch-ish
        case "db", "database", "sql", "postgres":
            return "[|]" // Database cylinder
        case "docker", "container", "k8s":
            return "[#]" // Container box
        case "mail", "email", "inbox":
            return "[@]"  // Email at
        case "chat", "slack", "discord", "messages":
            return "(:)" // Chat bubble
        case "docs", "notes", "obsidian", "wiki":
            return "[=]"  // Document lines
        case "music", "audio", "spotify":
            return "|>"  // Play button
        case "video", "media", "youtube":
            return "|>"  // Play
        case "cloud", "aws", "azure", "gcp":
            return "(~)" // Cloud
        case "monitor", "logs", "metrics":
            return "|^|" // Monitor/chart
        case "test", "testing", "spec":
            return "[?]" // Test check
        case "build", "ci", "pipeline":
            return "|+|" // Build hammer
        case "calendar", "schedule":
            return "[#]" // Calendar
        case "settings", "config", "prefs":
            return "[%]" // Gear-ish
        case "shop", "store", "cart":
            return "[$]"  // Shopping
        case "social", "twitter", "mastodon":
            return "(@)" // Social
        default:
            // Minimal fallback using index
            let symbols = ["|", "/", "\\", "<", ">", "^", "_", "-", "+", "="]
            let symbol = symbols[(index - 1) % symbols.count]
            return "(\(symbol))"
        }
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
    
    /// Decode \uXXXX escape sequences to actual unicode characters
    private func decodeUnicodeEscapes(_ input: String) -> String {
        var result = input
        let pattern = "\\\\u([0-9a-fA-F]{4})"
        
        // Find all \uXXXX patterns and replace with actual unicode characters
        while let range = result.range(of: pattern, options: .regularExpression) {
            let hexStart = result.index(range.lowerBound, offsetBy: 2) // Skip \\u
            let hexEnd = range.upperBound
            let hexString = String(result[hexStart..<hexEnd])
            
            if let codepoint = UInt32(hexString, radix: 16),
               let scalar = UnicodeScalar(codepoint) {
                result.replaceSubrange(range, with: String(scalar))
            } else {
                // If decoding fails, just remove the escape
                result.replaceSubrange(range, with: "")
            }
        }
        
        return result
    }
}

struct WorkspaceInfo {
    let index: Int
    let name: String
    let icon: String?
    let colorHex: String?
}

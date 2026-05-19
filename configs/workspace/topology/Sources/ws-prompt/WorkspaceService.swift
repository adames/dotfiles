import Foundation

/// Outcome of a long-running command (ws / yabai). `output` is stdout +
/// stderr concatenated because the ws CLI writes its `ok`/`err` helpers
/// to stderr; the manage overlay surfaces all of it in the result panel.
struct CommandResult: Equatable {
    let success: Bool
    let output: String
}

/// One entry in the SF Symbol catalog. Used by the manage
/// overlay's icon picker to fuzzy-search and preview icons.
/// Nerd Font mapping available for cross-platform use via separate adapter.
struct IconCatalogEntry: Equatable {
    let sfName: String   // "play.fill"
    let glyph: String    // Deprecated: was Nerd Font codepoint, now empty
}

/// The single seam between the controllers and the outside world.
///
/// Everything that talks to yabai, the `ws` CLI, or the file system
/// goes through this protocol — `Process()` invocations, reads of
/// `~/.config/workspace/spaces.json` and `~/.config/workspace/lib/sf-to-nerd.json`,
/// invocations of helper scripts. The production implementation
/// (`ProductionWorkspaceService`) does the real thing; tests inject a
/// fake that records calls and returns canned data.
///
/// Sync methods read state at the moment of call. Command methods run
/// on a background queue and fire `completion` on the main queue, so
/// callers can update SwiftUI state without dispatch boilerplate.
protocol WorkspaceService {
    // MARK: Sync reads
    func loadWorkspaces() -> [Workspace]
    func focusedSpaceIndex() -> Int?
    func listSnapshots() -> [String]
    func iconResolvable(_ name: String) -> Bool
    /// SF Symbol catalog. Previously mapped to Nerd Font for
    /// cross-platform use; now stores SF names directly.
    func iconCatalog() -> [IconCatalogEntry]

    // MARK: Async commands (capture stdout+stderr; complete on main queue)
    func runWs(args: [String], completion: @escaping (CommandResult) -> Void)
    func runYabai(args: [String], completion: @escaping (CommandResult) -> Void)
    /// Composite: `yabai space --create` + `ws name <new-index> NAME` +
    /// optionally `ws icon <new-index> ICON`. Surfaces the combined
    /// result.
    func runAdd(name: String, icon: String?, completion: @escaping (CommandResult) -> Void)

    // MARK: Fire-and-forget helpers (focus/send don't show a panel)
    func spawnFocus(slot: Int)
    func spawnSend(slot: Int)

    /// Fire sketchybar's optimistic-pre-paint trigger. Called from the
    /// overlay the instant a focus/send chord commits, so the pill
    /// updates before yabai's transition animation even starts. Pure
    /// fire-and-forget; ws-focus / ws-send-follow's bash-side trigger
    /// is the redundant fallback for direct CLI invocations.
    func fireOptimisticPrePaint(newSlot: Int, oldSlot: Int, display: Int)
}

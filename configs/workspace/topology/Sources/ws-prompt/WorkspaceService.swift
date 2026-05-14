import Foundation

/// Outcome of a long-running command (ws / yabai). `output` is stdout +
/// stderr concatenated because the ws CLI writes its `ok`/`err` helpers
/// to stderr; the manage overlay surfaces all of it in the result panel.
struct CommandResult: Equatable {
    let success: Bool
    let output: String
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
}
